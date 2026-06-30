import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Macro

public enum PublicMirrorMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // 1. Must be attached to a struct.
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: PublicMirrorDiagnostic.notAStruct))
            return []
        }

        // 2. Name must begin with an underscore. The twin takes the stripped name,
        //    and a peer macro emits into the *same* scope, so the two names must differ.
        let originalName = structDecl.name.text
        guard originalName.hasPrefix("_"), originalName.count > 1 else {
            context.diagnose(
                Diagnostic(node: Syntax(structDecl.name), message: PublicMirrorDiagnostic.nameUnderscore)
            )
            return []
        }
        let publicName = String(originalName.dropFirst())

        // 3. Collect stored properties, diagnosing anything that can't be mirrored.
        var properties: [StoredProperty] = []
        var hadError = false

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Skip static / class members — not part of a memberwise init.
            let isStatic = varDecl.modifiers.contains {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            }
            if isStatic { continue }

            let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

            for binding in varDecl.bindings {
                // Only simple identifier patterns (no tuple destructuring).
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    context.diagnose(
                        Diagnostic(node: Syntax(binding), message: PublicMirrorDiagnostic.unsupportedPattern)
                    )
                    hadError = true
                    continue
                }

                // Skip computed properties (a getter accessor block). Stored properties
                // with only willSet/didSet observers are kept, with observers dropped.
                if let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) {
                    continue
                }

                let name = pattern.identifier.text
                let type = binding.typeAnnotation?.type
                let defaultValue = binding.initializer?.value

                // A property that becomes an init parameter needs a written type.
                // (An inline-initialized `let` is a constant and is exempt — it isn't a param.)
                let isInitializedLet = isLet && defaultValue != nil
                if type == nil && !isInitializedLet {
                    context.diagnose(
                        Diagnostic(node: Syntax(binding), message: PublicMirrorDiagnostic.missingType(name))
                    )
                    hadError = true
                    continue
                }

                properties.append(
                    StoredProperty(name: name, type: type, isLet: isLet, defaultValue: defaultValue)
                )
            }
        }

        if hadError { return [] }

        // 4. Assemble the twin.
        let twin = renderTwin(
            name: publicName,
            generics: structDecl.genericParameterClause,
            inheritance: structDecl.inheritanceClause,
            whereClause: structDecl.genericWhereClause,
            properties: properties
        )

        return [DeclSyntax(stringLiteral: twin)]
    }
}

// MARK: - Stored property model

private struct StoredProperty {
    let name: String
    let type: TypeSyntax?
    let isLet: Bool
    let defaultValue: ExprSyntax?

    /// An inline-initialized `let` is a fixed constant, so it isn't an init parameter.
    var isInitParameter: Bool { !(isLet && defaultValue != nil) }
}

// MARK: - Rendering

private func renderTwin(
    name: String,
    generics: GenericParameterClauseSyntax?,
    inheritance: InheritanceClauseSyntax?,
    whereClause: GenericWhereClauseSyntax?,
    properties: [StoredProperty]
) -> String {
    // Header: public struct Name<...>: Conformances where ...
    var header = "public struct \(name)"
    if let generics { header += generics.trimmedDescription }
    if let inheritance {
        let types = inheritance.inheritedTypes
            .map { $0.type.trimmedDescription }
            .joined(separator: ", ")
        if !types.isEmpty { header += ": \(types)" }
    }
    if let whereClause { header += " " + whereClause.trimmedDescription }

    // Stored property declarations.
    var lines: [String] = []
    for p in properties {
        var line = "    public \(p.isLet ? "let" : "var") \(p.name)"
        if let type = p.type { line += ": \(type.trimmedDescription)" }
        if let def = p.defaultValue { line += " = \(def.trimmedDescription)" }
        lines.append(line)
    }

    // Initializer.
    let params = properties.filter(\.isInitParameter).map { p -> String in
        // Init params always have a type here (the macro diagnosed any that don't).
        var param = "\(p.name): \(p.type?.trimmedDescription ?? "")"
        // A `var` with an inline default gets the same default as the parameter,
        // mirroring Swift's own memberwise initializer.
        if !p.isLet, let def = p.defaultValue {
            param += " = \(def.trimmedDescription)"
        }
        return param
    }
    let assignments = properties.filter(\.isInitParameter)
        .map { "        self.\($0.name) = \($0.name)" }
        .joined(separator: "\n")

    let initDecl = """
        public init(\(params.joined(separator: ", "))) {
    \(assignments)
        }
    """

    let body = (lines + [initDecl]).joined(separator: "\n")
    return """
    \(header) {
    \(body)
    }
    """
}

// MARK: - Helpers

/// True if an accessor block represents a computed property (a getter), as opposed
/// to a stored property carrying only `willSet` / `didSet` observers.
private func isComputed(_ accessorBlock: AccessorBlockSyntax) -> Bool {
    switch accessorBlock.accessors {
    case .getter:
        // Shorthand `var x: Int { 5 }` — computed.
        return true
    case .accessors(let list):
        return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
    }
}

// MARK: - Diagnostics

private struct PublicMirrorDiagnostic: DiagnosticMessage {
    let message: String
    let id: String
    var severity: DiagnosticSeverity { .error }
    var diagnosticID: MessageID { MessageID(domain: "PublicMirror", id: id) }

    static let notAStruct = PublicMirrorDiagnostic(
        message: "@PublicMirror can only be attached to a struct.",
        id: "notAStruct"
    )

    static let nameUnderscore = PublicMirrorDiagnostic(
        message: """
        @PublicMirror requires the struct name to begin with an underscore (e.g. `_User`). \
        It generates the public twin with the underscore removed (`User`) in the same scope, \
        so the source-of-truth name must differ from the generated name.
        """,
        id: "nameUnderscore"
    )

    static let unsupportedPattern = PublicMirrorDiagnostic(
        message: "@PublicMirror does not support tuple-destructured properties. Use separate declarations.",
        id: "unsupportedPattern"
    )

    static func missingType(_ name: String) -> PublicMirrorDiagnostic {
        PublicMirrorDiagnostic(
            message: "Stored property '\(name)' needs an explicit type annotation so @PublicMirror can generate the public initializer.",
            id: "missingType"
        )
    }
}
