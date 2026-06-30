# CLAUDE.md

Operating guide for any agent working on this Swift **shared-models package**.
Read this fully before proposing changes. Several "obvious" ideas here are
dead ends that were already investigated and rejected — they're listed so you
don't re-propose them.

---

## 1. What this project is

A **pure data-oriented Swift package**: plain `public` value-type structs (DTOs)
with no behavior, consumed by **both the app and other packages**. Its job is to
let those modules couple only through shared *data definitions*, not behavior.

Because multiple separate packages depend on it, the module boundary is real and
intended. That has consequences (Section 2) that drive every other decision here.

The package sits at the **bottom of the dependency graph**: it depends on nothing
in this codebase, and everything depends on it. It must never import a feature
package. If it starts importing app/feature code, the decoupling is gone — treat
that as a red flag.

---

## 2. Hard constraints (do not fight these)

These are language-level facts, confirmed, not preferences:

- **You cannot change Swift's default access level.** There is no compiler flag,
  no `Package.swift` setting, no build option to make declarations default to
  `public`. The default is `internal`, by design. `public` at a module boundary
  is mandatory and not configurable. Do not look for a switch — there isn't one.
- **`package` access does not help here.** The `package` modifier only grants
  visibility to other modules *inside the same Swift package*. Separate packages
  are outside it, so `package` cannot replace `public` for our consumers.
- **Cannot fold into the app target.** Other packages need these types too, so the
  code can't live in the app — the boundary is unavoidable.
- **Swift has no `namespace` keyword** (as of Swift 6.4). The module is the only
  built-in namespace; for sub-grouping use a **case-less `enum`** (the standard
  idiom, e.g. Combine's `Publishers`). A struct-with-private-init is inferior
  because the enum cannot be instantiated at all.

### Macro constraints (critical — the package uses a macro)

- **Attached macros are strictly additive.** They can add peers, members,
  member-attributes, accessors, or extensions. They **cannot rewrite the access
  level (or any modifier) of the declaration they're attached to.** So no macro
  can turn `struct User` into `public struct User` in place.
- **Peer macros emit into the *same lexical scope* as the attached declaration.**
  They cannot relocate output into a different namespace. `@Macro struct Foo` at
  file scope emits at file scope; it cannot wrap its output in
  `extension Models { ... }`.
- **Consequence:** source-of-truth and generated twin live in the same scope, so
  their **names must differ** → the underscore convention (Section 4).
- **Why the same-scope rule exists:** lazy name lookup. If an attached macro could
  inject names into arbitrary scopes, the compiler would have to expand every
  macro in the module before resolving any name. Locality keeps compilation
  tractable. Don't expect this to change.
- To emit at a *chosen* scope you use a **freestanding `#macro`** invoked at that
  scope — but then the type's fields become macro *arguments* (worse authoring).
  Attached macros are preferred despite the scope limitation.

---

## 3. The chosen solution: `@PublicMirror`

A **peer macro** that generates a `public` twin of an underscored internal struct.
Implemented in the `PublicMirror` package (Section 7).

```swift
extension Models {
    @PublicMirror
    struct _User {                 // internal source of truth (underscore is deliberate)
        let id: UUID
        let name: String
        var isActive: Bool = false
    }
    // generates a peer, here inside Models:
    // public struct User {
    //     public let id: UUID
    //     public let name: String
    //     public var isActive: Bool = false
    //     public init(id: UUID, name: String, isActive: Bool = false) { ... }
    // }
}
```

**Namespacing is done by the author, not the macro.** Wrap a group of underscored
originals in `extension Models { ... }`; the twins are emitted in place, inside
`Models`. The macro fills the namespace; it does not create it.

What the macro handles: stored `let`/`var` with explicit type annotations, inline
default values (kept as defaulted init params for `var`), inline-initialized `let`
constants (mirrored, excluded from `init`), generic/`where` clauses, and the
conformance list. It skips computed properties and `static`/`class` members.

What it requires/rejects (all diagnosed at compile time): struct only; name must
begin with `_`; any init-bound property must have an explicit type annotation
(the macro is syntax-only and can't infer types from `var x = 0`).

---

## 4. Conventions every agent must follow

- **Underscore the source of truth.** Author internal structs as `_User`; the twin
  becomes `User`. The ugly name marks it as write-only macro input.
- **Import discipline (non-negotiable).** `_User` and `User` are *distinct types*
  with no implicit bridging. Nothing except the macro should reference the
  underscored originals — the app, other packages, **and this package's own code**
  use only the generated twins (`Models.User`).
- **Group with `enum` namespaces** where a second grouping level is wanted
  (e.g. `Models.Request.UpdateName`). The package module name is already a
  namespace, so an inner enum is only for sub-grouping.

---

## 5. Per-type decisions (the do / don't rules)

### `Sendable` — add explicitly to every public DTO
Implicit `Sendable` on a value type is **only visible within the defining module**.
Public types need an explicit `: Sendable` or downstream packages won't see the
conformance and will hit concurrency errors. Adding it also fails to compile if a
non-Sendable member sneaks in — a useful alarm. **Default: yes, everywhere.**

### `@frozen` — do NOT blanket
It is a **no-op when building from source** (library evolution off). It only does
anything for a **binary framework (XCFramework) shipped with `-enable-library-evolution`**.
This package ships from source, so `@frozen` adds nothing. Only consider it,
per-type, if distribution changes to a binary framework *and* a type's stored-property
layout is genuinely permanent. Until then: **no.**

### Closure properties — must be `@Sendable`
A stored closure breaks the "all-value-members → Sendable" inference. Type the
property as a `@Sendable` function:

```swift
public struct Handler: Sendable {
    public let onChange: @Sendable (Int) -> Void
}
```

`@Sendable` is part of the *function type*, so it goes in the annotation; it also
forces capture-checking at the closure literal (the call site). Keep `: Sendable`
on the struct as well — the two do different jobs.

**Important:** a struct with a closure property is **no longer trivial** (the
closure carries a context pointer and pays ARC on every copy). Keep closure-bearing
structs mentally separate from plain-data DTOs; do **not** put them in hot loops.
Use `sending` for the rare single-use non-Sendable-capture case. `@unchecked Sendable`
is a last resort, never a default.

The `@PublicMirror` twin copies property types verbatim, so `@Sendable` carries to
the twin correctly — but the underscored original must itself include `: Sendable`
and `@Sendable` closure types, or the *twin* fails its conformance check.

---

## 6. Optimization guidance (data-oriented)

Two meanings of "data-oriented" — apply the right column:

**DTO-style (default for this package):** wins are correctness + ergonomics.
- Conformances **per-use, not blanket**: `Equatable`/`Hashable` are free and worth
  it where you diff, dedupe, or use types as keys/SwiftUI identity. `Identifiable`
  if they feed SwiftUI lists. **`Codable` is disciplined** — it adds real compile
  time and binary size, so put it only on types you actually serialize.
- **Typed ID wrappers** (`struct UserID: Hashable { let raw: UUID }`) to stop
  passing the wrong UUID — high value in ID-heavy data code.
- **Prefer `let` / immutability** — an all-`let` value struct is trivially Sendable
  and mutation-proof. Immutability *is* the optimization, not a tax.
- **Keep structs trivial:** value-only members (no class refs, no closures) → the
  copy is a `memcpy` with zero ARC traffic. A single reference/closure member
  forces retain/release on every copy. (`String`/`Array` are COW-cheap but not
  strictly trivial — fine except in very hot paths.)

**Cache-efficient Data-Oriented *Design* (only at measured large N):**
- `borrowing` / `consuming` on functions taking large structs to skip copies.
- `ContiguousArray` over `Array` for value types (no Obj-C bridging).
- `InlineArray<n, Element>` (inline storage) and `Span` (safe borrowed view, no
  copy). Swift 6.4's new iteration protocol lets `for-in` cover these noncopyable
  types without the copy penalty.
- **Struct-of-Arrays** over array-of-structs when iterating one field across many
  entities — better cache locality. **Architectural commitment; only when a
  profiler justifies it.**

**Skip / don't cargo-cult:** `@frozen` (no-op from source), blanket `@inlinable`
(makes the body part of your API; only on profiled cross-module hot functions),
`final` (no-op on structs). Do not reorganize to SoA on speculation.

---

## 7. The `PublicMirror` package

```
PublicMirror/
├── Package.swift                         # swift-tools 6.0; swift-syntax "600.0.0"..<"700.0.0"
├── Sources/
│   ├── PublicMirror/PublicMirror.swift   # @PublicMirror macro declaration (the public API)
│   └── PublicMirrorMacros/
│       ├── PublicMirrorMacro.swift       # PeerMacro implementation
│       └── Plugin.swift                  # CompilerPlugin entry point
├── Tests/PublicMirrorTests/              # assertMacroExpansion tests (XCTest)
└── Examples/Usage.swift                  # namespaced DTO usage pattern
```

Build / test:
```bash
swift build && swift test
```

**Caveat:** the package was written against the stable swift-syntax macro APIs but
was **not compiled in the environment that generated it** (no Swift toolchain
there). First build is local. If an expansion test fails purely on whitespace,
`assertMacroExpansion` is formatting-sensitive — paste the "actual" block from the
failure into `expandedSource`; the generated *code* is what matters. If the macro
*target* fails to compile, it's almost certainly an exact swift-syntax node API
name — fix that node, the logic is sound.

**Conformance caveat in the macro:** the inheritance clause is copied verbatim to
the twin. A `public` twin cannot conform to an `internal` protocol, so only put
**public** protocol conformances (the stdlib ones are public) on the underscored
originals.

---

## 8. Swift version

Target **Swift 6.4** (shipped WWDC 2026). Non-breaking upgrade over 6.x. Relevant
features: **module selectors (`::`)** for disambiguating name collisions (apt for
the `_User`/`User`/consumer-`User` situation), more accessible memberwise inits,
`~Sendable` opt-out, `weak let`, async `defer`, `anyAppleOS`, and XCTest ↔ Swift
Testing interop (useful for the macro tests). **Gating requirement:** Swift 6.4 is
in Xcode 27, which needs Apple Silicon + macOS Tahoe 26.4+. If any teammate/CI is
on Intel or older macOS, that's the real constraint — the package also builds fine
on 6.3.

---

## 9. Rejected alternatives — do NOT re-propose

- **Change the default access level to public.** Impossible. No such feature exists.
- **`@testable import MyData` from the app/packages.** Test-only mechanism; requires
  `-enable-testing` (Debug test builds only), won't survive Release, and exposes
  *all* internals indiscriminately — the opposite of a deliberate API. Wrong tool.
  Correct use of `@testable` is only inside MyData's *own* test target.
- **Sourcery (additive companion files).** Can generate the public `init`, but
  **cannot flip stored-property access** — companion files only add extensions, and
  property access lives in the type body. Same wall as the macro. (Generating a full
  public *mirror type* is possible but is just the macro with more setup + committed
  generated files + a drift guard.)
- **Source-rewriting codegen** (internal text → public text before compile). The only
  approach that literally rewrites in place, but it breaks debugging/IDE: stack
  traces and breakpoints point at generated line numbers, indexing/autocomplete get
  confused. Rejected — the tooling cost exceeds the keyword cost.
- **Generate a new package mid-build that sibling packages import.** Impossible:
  SwiftPM resolves the whole dependency graph *before* plugins/build phases run, so
  the graph is frozen. A generated public package must be **committed** (run Sourcery
  in CI/dev tooling, commit output, add a `git diff` drift check) — not produced
  during a consumer's build.
- **A macro that wraps its output in `extension Models { ... }`.** Impossible for an
  attached macro (same-scope rule, Section 2). Author the `extension Models` wrapper
  yourself and attach inside it.

---

## 10. Quick decision table

| Question | Answer |
|---|---|
| Make everything public by default? | No mechanism exists. Use `@PublicMirror` + explicit `public`. |
| `Sendable` on DTOs? | Yes, explicit, on every public type. |
| `@frozen` on DTOs? | No (no-op from source). Only for binary XCFramework + frozen layout. |
| `Codable` on every type? | No. Only where actually serialized. |
| `Equatable`/`Hashable`? | Where diffed/keyed/identity. Free, so liberal is fine. |
| Closure property + Sendable? | Type it `@Sendable (...) -> ...`; keep `: Sendable` on struct. |
| Closure-bearing struct in a hot loop? | No — not trivial, pays ARC per copy. |
| `final` on a struct? | No-op. Don't. |
| Namespace via macro? | No. Use `enum` + author the wrapper. |
| Use `package` access for our consumers? | No — they're separate packages. |
