# CLAUDE.md

`@MemberwiseInit` — a `member` macro that writes a memberwise `init` at the type's own
access level, for a **struct, class, or actor**. Fills what Swift won't synthesize: a
public type's `public init`, and any init at all for a class/actor (e.g. an
`@Observable final class`).

Impl: `Sources/MemberwiseInitMacros/MemberwiseInitMacro.swift`. Tests: `Tests/`.
Examples: `Examples/main.swift`. Targets Swift 6.4 (Xcode 27); swift-syntax APIs used
are stable across the 6xx line.

- Build/test: `swift build && swift test`
- Format: `swift format --in-place --recursive Sources Tests Examples`

## Tricky points

- **Syntax-only, no type inference.** A non-private property that becomes a parameter
  needs an explicit type — `var count: Int = 0`, not `var count = 0` (the latter is a
  compile error). The macro can't read a type off a literal.
- **`private` is the one exclusion rule.** Every `private`/`fileprivate` property is
  dropped from the init. That single rule also keeps SwiftUI's view-owned wrappers out
  — `@State`/`@Environment`/`@StateObject` are always private — so there's no
  per-wrapper allow/deny list.
- **`@Binding` is the kept exception:** threaded as a projected `Binding<T>`, assigned
  `self._x = x`.
- **`@ViewBuilder` has two forms.** Stored closure `let vb: () -> Content` →
  `@ViewBuilder vb: @escaping () -> Content`, `self.vb = vb`. Stored value
  `let vb2: Content` → `@ViewBuilder vb2: () -> Content`, `self.vb2 = vb2()` — the init
  *calls* the builder.
- **Function-typed properties get `@escaping`**, attributed types included
  (`@MainActor () -> Void`, `@Sendable (Int) -> Void`).
- **No stored `let` constants.** `let version = 1` as a property is *not* special-cased;
  it yields a `let`-reassignment compile error. Use `static let`.
- **Skipped:** computed properties and `static`/`class` members. **Kept:** stored
  properties with only `willSet`/`didSet` observers.
- **Tests are whitespace-sensitive** (`assertMacroExpansion`). On a formatting-only
  failure, paste the "actual" block into `expandedSource`. Diagnostic specs anchor
  `line`/`column` at the property's name, not the line start.
