# PublicMirror

A Swift peer macro that generates a `public` twin of an internal struct, so you
can author plain `internal` model types and expose `public` API across module
boundaries without hand-writing `public` on every type, property, and initializer.

```swift
enum Models {
    @PublicMirror
    struct _User {                 // internal source of truth
        let id: UUID
        let name: String
        var isActive: Bool = false
    }
    // generates, as a peer inside `Models`:
    //
    // public struct User {
    //     public let id: UUID
    //     public let name: String
    //     public var isActive: Bool = false
    //     public init(id: UUID, name: String, isActive: Bool = false) { ... }
    // }
}

let user = Models.User(id: UUID(), name: "Ada")
```

## Why it's shaped this way

A peer macro emits its output into the **same lexical scope** as the declaration
it's attached to — it cannot redirect output into a different namespace, and it
cannot rewrite the original declaration's access level (attached macros are
strictly additive). Two consequences follow, and they define the ergonomics:

1. **The source-of-truth and the twin share a scope, so their names must differ.**
   The convention here: name the original with a leading underscore (`_User`);
   the macro strips it to produce the clean public name (`User`). The underscore
   is deliberate friction marking the original as write-only macro input.

2. **Namespacing is done with an `enum`, not the macro.** Put the underscored
   originals inside an `enum` namespace; the twins are emitted beside them, so
   they land in the same namespace. (Your package is already its own module-level
   namespace, so an inner `enum` is only needed if you want a second grouping
   level like `Models.Request.UpdateName`.)

## What it handles

- Stored `let` / `var` properties (with explicit type annotations).
- Inline default values — kept as defaulted initializer parameters for `var`.
- `let` constants initialized inline — mirrored as constants, excluded from `init`.
- Generic parameter clauses, `where` clauses, and conformance lists (so
  `Equatable` / `Codable` / `Hashable` / `Sendable` carry over to the twin).
- Computed properties and `static` / `class` members are skipped.

## Requirements and limitations

- **Struct only.** Attaching to a class/enum/actor is diagnosed.
- **Name must begin with `_`.** Diagnosed otherwise.
- **Init-parameter properties need an explicit type annotation.** The macro works
  at the syntax level and cannot infer a type from `var count = 0`; add `: Int`.
  (An inline-initialized `let` is exempt — it's a constant, not a parameter.)
- **Conformances are copied verbatim.** If the original conforms to an *internal*
  protocol, the public twin will too, which the compiler rejects (a public type
  can't conform to an internal protocol). Conform your DTOs to public protocols
  (the standard-library ones are public), or don't put the conformance on the
  underscored original.
- Tuple-destructured property declarations (`let (a, b): (Int, Int)`) are not
  supported — split them into separate declarations.

## Import discipline (important)

The internal `_User` and the generated `User` are **distinct types** — there is
no implicit bridging. For the decoupling to hold, nothing except the macro should
consume the underscored originals: your app, your other packages, and the rest of
this package's own code should all reference only the generated public twins.

## Build & test

This package was written against the stable swift-syntax macro APIs but was **not
compiled in the environment it was generated in** (no Swift toolchain available
there). Build and test it locally:

```bash
swift build
swift test
```

Targeting Swift 6.4 (swift-syntax 6xx). The `swift-syntax` dependency is pinned to
`600.0.0 ..< 700.0.0`, which resolves to the version matching your installed 6.x
toolchain.

Note: the expected-output strings in `Tests/PublicMirrorTests` are written to match
the macro's rendered indentation, but `assertMacroExpansion` is whitespace-sensitive.
If a test fails purely on formatting on first run, copy the "actual" block from the
failure message into the `expandedSource` — the generated *code* is what matters.

## Consuming it

Add the package as a dependency and depend on the `PublicMirror` product (the
library that vends the `@PublicMirror` attribute). The `PublicMirrorMacros` target
is the compiler plugin and is pulled in automatically; it never ships in your binary.
