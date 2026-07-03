import Foundation
import MemberwiseInit
import SwiftUI

// @MemberwiseInit writes the memberwise initializer at the struct's own access
// level — the `public init` Swift refuses to synthesize for a public type.

@MemberwiseInit
public struct User {
    static let x: Int = 0
    static var y: Int {
        0
    }

    var x: Int {
        0
    }

    public let id: UUID
    public let name: String
    var isActive: Bool = false  // inline default → defaulted parameter
    public let onmain: @MainActor () -> Void
    public let onChange: () async -> Void  // function type → @escaping param
    public let onRename: @Sendable (String, Int) async -> Void  // attributed function type → @escaping param
    public var onDone: (() -> Void)?  // optional var → `= nil` param, no @escaping
}

@MemberwiseInit
@Observable public final class Settings {
    var count: Int = 0
}

// On a View: @State/@Environment are private, so they're excluded; @Binding is
// threaded as Binding<Bool>; @ViewBuilder carries onto the parameters. Generated init:
// `init(isOn: Binding<Bool>, title: String, subtitle: String? = nil, model: Settings,
//       @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content)`.
@MemberwiseInit
public struct ProfileCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @Binding var isOn: Bool
    let title: String
    var subtitle: String?

    @Bindable var model: Settings

    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: Content

    public var body: some View {
        VStack {
            Text(isExpanded ? "Expanded" : "Collapsed")
            content()
            footer
        }
    }
}
