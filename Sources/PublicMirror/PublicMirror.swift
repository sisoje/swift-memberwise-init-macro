/// Generates a `public` twin of an internal struct.
///
/// Attach `@PublicMirror` to an **internal** struct whose name begins with an
/// underscore. The macro emits, as a sibling in the same scope, a `public struct`
/// with the underscore stripped from the name, `public` stored properties, and a
/// `public` memberwise initializer.
///
/// ```swift
/// enum Models {
///     @PublicMirror
///     struct _User {            // internal source of truth (the ugly name is deliberate)
///         let id: UUID
///         let name: String
///         var isActive: Bool = false
///     }
///     // expands to a peer, here inside `Models`:
///     //
///     // public struct User {
///     //     public let id: UUID
///     //     public let name: String
///     //     public var isActive: Bool = false
///     //     public init(id: UUID, name: String, isActive: Bool = false) {
///     //         self.id = id
///     //         self.name = name
///     //         self.isActive = isActive
///     //     }
///     // }
/// }
/// ```
///
/// Consumers (your app and your other packages) reference the generated public
/// type — e.g. `Models.User`. The underscored original is write-only macro input
/// that nothing else should reference.
///
/// ## What it mirrors
/// - Stored `let` / `var` properties with explicit type annotations.
/// - Inline default values (kept as defaulted initializer parameters for `var`).
/// - `let` constants initialized inline (mirrored as constants, excluded from `init`).
/// - The struct's generic parameter clause, `where` clause, and conformance list.
///
/// ## What it skips / requires
/// - Computed properties and `static`/`class` members are skipped.
/// - Properties that become initializer parameters **must** carry an explicit type
///   annotation (the macro works on syntax and can't infer types).
/// - The struct name must begin with `_`.
@attached(peer, names: arbitrary)
public macro PublicMirror() = #externalMacro(
    module: "PublicMirrorMacros",
    type: "PublicMirrorMacro"
)
