# MemberwiseInit

A Swift `member` macro that writes a memberwise `init` for the type it's attached to,
**at the type's own access level**. It fills the initializers Swift won't synthesize:
the `public init` a public struct needs, and *any* init for a `class` or `actor` —
including an `@Observable final class`.

```swift
@MemberwiseInit
public struct User {
    public let id: UUID
    public var isActive: Bool = false
}
// generates:
// public init(id: UUID, isActive: Bool = false) {
//     self.id = id
//     self.isActive = isActive
// }
```

Works the same on a `class` or `actor`:

```swift
@MemberwiseInit
@Observable final class Counter {
    var count: Int = 0
}
// init(count: Int = 0) { self.count = count }
```

## Install

```swift
// Package.swift
.package(url: "https://github.com/sisoje/swift-memberwise-init-macro", branch: "main"),

// target dependency
.product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
```

Then `import MemberwiseInit` and add `@MemberwiseInit` to a struct, class, or actor.

## What it does

- **Mirrors the access level** — `public struct` → `public init`, an internal type →
  unmodified `init`, and so on.
- **`var` defaults carry through** — `var x: Int = 0` → parameter `x: Int = 0`.
- **Function-typed properties get `@escaping`**, attributed types included
  (`@MainActor () -> Void`, `@Sendable (Int) -> Void`).
- **Skips** computed properties and `static`/`class` members; keeps stored properties
  that have only `willSet`/`didSet` observers.

## SwiftUI

- **`private` properties are excluded** from the init. Since SwiftUI's view-owned
  wrappers — `@State`, `@Environment`, `@StateObject`, … — are always `private`, they
  fall out automatically. No configuration, no per-wrapper list.
- **`@Binding`** is threaded in as a projected `Binding<T>` parameter, assigned to the
  backing storage (`self._x = x`).
- **`@ViewBuilder`** carries onto the parameter so callers get trailing-closure syntax.
  A stored closure (`let vb: () -> Content`) becomes `@ViewBuilder vb: @escaping () -> Content`;
  a stored value (`let vb2: Content`) becomes `@ViewBuilder vb2: () -> Content` and the
  init calls it (`self.vb2 = vb2()`).

```swift
@MemberwiseInit
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme   // excluded (private)
    @State private var expanded = false              // excluded (private)
    @Binding var isOn: Bool                           // init param: Binding<Bool>
    let title: String
    @ViewBuilder let content: Content                 // init param: @ViewBuilder () -> Content

    var body: some View { /* ... */ }
}
// init(isOn: Binding<Bool>, title: String, @ViewBuilder content: () -> Content)
```

## Design: for pure data

- **No type inference.** It's syntax-only: a non-private property that becomes a
  parameter needs an explicit type. `var count: Int = 0`, not `var count = 0` (the
  latter is a compile error).
- **No stored `let` constants.** A constant isn't per-instance data — use `static let`.
  The macro doesn't special-case an instance `let`: `let version: Int = 1` generates
  `self.version = version` (a `let`-reassignment error), and untyped `let version = 1`
  hits the missing-type rule above. Either way it won't compile.
- **`private` means private.** If a value is meant to be passed in, it isn't private.

## Requirements

Swift 6.3+ (declared `swift-tools-version: 6.3`; developed on 6.4 / Xcode 27). Builds
across the whole swift-syntax 6xx line.
