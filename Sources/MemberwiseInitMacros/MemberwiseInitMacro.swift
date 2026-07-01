import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Macro

/// Adds a memberwise `init` to the struct, class, or actor it is attached to, at the
/// type's own access level.
///
/// Swift only *synthesizes* an `internal` memberwise initializer for a struct, and
/// only when you write no init of your own; a class or actor gets none at all. This
/// member macro writes an explicit one that matches the type — so a `public struct`
/// gets the `public init` Swift won't synthesize, and an `@Observable final class`
/// gets the memberwise `init` it otherwise needs by hand.
public enum MemberwiseInitMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self)
                || declaration.is(ActorDeclSyntax.self)
        else {
            context.diagnose(
                Diagnostic(node: node, message: MemberwiseInitDiagnostic.notADataType)
            )
            return []
        }
        guard let properties = collectStoredProperties(of: declaration, in: context) else {
            return []
        }
        let access = accessLevel(of: declaration)
        return [
            DeclSyntax(stringLiteral: renderMemberwiseInit(properties: properties, access: access))
        ]
    }
}

// MARK: - Stored-property model

/// A stored property that participates in a memberwise initializer.
struct StoredProperty {
    let name: String
    let type: TypeSyntax?
    let isLet: Bool
    let defaultValue: ExprSyntax?
    /// The property-wrapper type name (`Binding`, `State`, `Environment`, …), or nil.
    let wrapperName: String?
    /// True if the property is declared `private` or `fileprivate` — implementation
    /// detail, excluded from the init. This is also what keeps view-owned wrappers
    /// out: `@State`, `@Environment`, … are always private.
    let isPrivate: Bool

    /// `@Binding` is the one property wrapper the init threads through (as a
    /// projected `Binding<T>` parameter). Every other wrapper is view-owned or
    /// injected (`@State`, `@Environment`, `@StateObject`, …) and self-initializes.
    var isBinding: Bool {
        wrapperName == "Binding"
    }

    /// `@ViewBuilder` — the parameter carries the attribute so callers get trailing
    /// builder syntax. When the property stores the built value (`let vb: Content`)
    /// the parameter is a `() -> Content` the init calls; when it stores the closure
    /// (`let vb: () -> Content`) the parameter is that `@escaping` closure.
    var isViewBuilder: Bool {
        wrapperName == "ViewBuilder"
    }
}

// MARK: - Collection

/// Collect the stored properties of a struct that participate in a memberwise init.
///
/// Skips computed properties, `static`/`class` members, and non-identifier bindings
/// (tuple destructuring). Returns `nil` if a diagnostic was emitted — an init
/// parameter lacking an explicit type (the macro is syntax-only and can't infer it).
func collectStoredProperties(
    of decl: some DeclGroupSyntax,
    in context: some MacroExpansionContext
) -> [StoredProperty]? {
    var properties: [StoredProperty] = []
    var hadError = false

    for member in decl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

        // Skip static / class members — not part of a memberwise init.
        let isStatic = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        if isStatic { continue }

        let isPrivate = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }

        let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

        for binding in varDecl.bindings {
            // Only simple identifier patterns (no tuple destructuring).
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

            // Skip computed properties (a getter accessor block). Stored properties
            // with only willSet/didSet observers are kept, observers dropped.
            if let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) { continue }

            let property = StoredProperty(
                name: pattern.identifier.text,
                type: binding.typeAnnotation?.type,
                isLet: isLet,
                defaultValue: binding.initializer?.value,
                wrapperName: propertyWrapperName(varDecl.attributes),
                isPrivate: isPrivate
            )

            // Only init parameters need a written type. Non-parameter properties —
            // inline-initialized `let` constants, and view-owned wrappers like
            // `@State`/`@Environment` — are exempt (`@State private var ole = 0`
            // needs no annotation and takes no init parameter).
            if !property.isPrivate, property.type == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: MemberwiseInitDiagnostic.missingType(property.name)
                    )
                )
                hadError = true
                continue
            }

            properties.append(property)
        }
    }

    return hadError ? nil : properties
}

// MARK: - Rendering

/// Render a memberwise initializer for `properties` at the given access level.
/// `access` is a modifier prefix such as `"public "` or `""` (internal).
func renderMemberwiseInit(properties: [StoredProperty], access: String) -> String {
    let initParams = properties.filter { !$0.isPrivate }

    let params = initParams.map { p -> String in
        // Init params always have a type here (the macro diagnosed any that don't).
        let typeStr = p.type?.trimmedDescription ?? ""
        // A `@Binding` is threaded through as its projected `Binding<T>` type.
        if p.isBinding {
            return "\(p.name): Binding<\(typeStr)>"
        }
        // A `@ViewBuilder` param carries the attribute. Stored-closure form is the
        // `@escaping` closure itself; stored-value form takes a `() -> Value` builder.
        if p.isViewBuilder {
            return (p.type.map(isFunctionType) ?? false)
                ? "@ViewBuilder \(p.name): @escaping \(typeStr)"
                : "@ViewBuilder \(p.name): () -> \(typeStr)"
        }
        let escaping = (p.type.map(isFunctionType) ?? false) ? "@escaping " : ""
        var param = "\(p.name): \(escaping)\(typeStr)"
        // A `var` with an inline default gets the same default as the parameter,
        // and an optional `var` is implicitly nil-initialized — both mirroring
        // Swift's own memberwise initializer.
        if !p.isLet, let def = p.defaultValue {
            param += " = \(def.trimmedDescription)"
        } else if !p.isLet, p.type.map(isOptionalType) ?? false {
            param += " = nil"
        }
        return param
    }

    let assignments = initParams.map { p -> String in
        // A `@Binding` assigns its backing storage (self._x). A `@ViewBuilder` that
        // stores the built value calls the builder closure (self.vb = vb()). Every
        // other property assigns directly.
        if p.isBinding { return "    self._\(p.name) = \(p.name)" }
        if p.isViewBuilder, !(p.type.map(isFunctionType) ?? false) {
            return "    self.\(p.name) = \(p.name)()"
        }
        return "    self.\(p.name) = \(p.name)"
    }.joined(separator: "\n")

    // One relative indentation level: the `init` header/brace at column 0, the body
    // at 4 spaces. The member macro's output is re-indented into the struct body.
    return """
        \(access)init(\(params.joined(separator: ", "))) {
        \(assignments)
        }
        """
}

// MARK: - Helpers

/// The struct's access modifier as a trailing-spaced prefix (`"public "`,
/// `"package "`, …), or `""` for the default internal.
func accessLevel(of decl: some DeclGroupSyntax) -> String {
    let accessKeywords: Set<TokenKind> = [
        .keyword(.public), .keyword(.package), .keyword(.internal),
        .keyword(.fileprivate), .keyword(.private),
    ]
    let modifier = decl.modifiers.first { accessKeywords.contains($0.name.tokenKind) }
    return modifier.map { "\($0.name.text) " } ?? ""
}

/// The name of the first attribute on a property (its property-wrapper type, e.g.
/// `Binding` for `@Binding`), or nil if the property carries no attributes.
func propertyWrapperName(_ attributes: AttributeListSyntax) -> String? {
    for case .attribute(let attr) in attributes {
        if let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
            return name
        }
    }
    return nil
}

/// True if a type is a function type (plain, attributed, or parenthesized),
/// meaning a stored-property init parameter needs `@escaping`. Optional function
/// types (`(() -> Void)?`) are deliberately *not* matched: an optional closure
/// parameter is already escaping, and `@escaping` on it is a compile error.
func isFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) { return true }
    // Attributed function types, e.g. `@MainActor () -> Void` or `@Sendable () -> Void`.
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
        tuple.elements.count == 1,
        let inner = tuple.elements.first?.type
    {
        return isFunctionType(inner)
    }
    return false
}

/// True if a type is optional (`T?` or `T!`) — a `var` of such a type is implicitly
/// nil-initialized, so its init parameter defaults to `nil` just like in Swift's
/// synthesized memberwise initializer.
func isOptionalType(_ type: TypeSyntax) -> Bool {
    type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
}

/// True if an accessor block represents a computed property (a getter), as opposed
/// to a stored property carrying only `willSet` / `didSet` observers.
func isComputed(_ accessorBlock: AccessorBlockSyntax) -> Bool {
    switch accessorBlock.accessors {
    case .getter:
        return true
    case .accessors(let list):
        return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
    }
}

// MARK: - Diagnostics

struct MemberwiseInitDiagnostic: DiagnosticMessage {
    let message: String
    let id: String
    var severity: DiagnosticSeverity {
        .error
    }

    var diagnosticID: MessageID {
        MessageID(domain: "MemberwiseInit", id: id)
    }

    static let notADataType = MemberwiseInitDiagnostic(
        message: "@MemberwiseInit can only be attached to a struct, class, or actor.",
        id: "notADataType"
    )

    static func missingType(_ name: String) -> MemberwiseInitDiagnostic {
        MemberwiseInitDiagnostic(
            message:
                "Stored property '\(name)' needs an explicit type annotation so @MemberwiseInit can generate the initializer.",
            id: "missingType"
        )
    }
}
