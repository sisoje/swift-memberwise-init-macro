import Foundation
import MemberwiseInit
import SwiftUI

// @MemberwiseInit writes the memberwise initializer at the struct's own access
// level — the `public init` Swift refuses to synthesize for a public type.

@MemberwiseInit
public struct User {
    static let x: Int = 0
    static var y: Int { 0 }
    var x: Int { 0 }

    public let id: UUID
    public let name: String
    var isActive: Bool = false  // inline default → defaulted parameter
    public let onmain: @MainActor () -> Void
    public let onChange: () -> Void  // function type → @escaping param
    public let onRename: @Sendable (String) -> Void  // attributed function type → @escaping param
}

@MemberwiseInit
@Observable final class Zola {
    var ii: Int = 0
}

// On a View: @State/@Environment are private, so they're excluded; @Binding is
// threaded as Binding<Int>; @ViewBuilder carries onto the parameters. Generated init:
// `init(x: Binding<Int>, opa: Int,
//       @ViewBuilder vb: @escaping () -> Content, @ViewBuilder vb2: () -> Content)`.
@MemberwiseInit
public struct PubView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var x: Int
    @State private var ole = 0
    let opa: Int

    @ViewBuilder let vb: () -> Content
    @ViewBuilder let vb2: Content

    public var body: some View {
        VStack {
            Text("\(ole)")
            vb()
            vb2
        }
    }
}
