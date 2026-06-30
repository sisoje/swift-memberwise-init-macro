import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import PublicMirrorMacros

final class PureDataTests: XCTestCase {
    let macros: [String: Macro.Type] = ["PublicMirror": PublicMirrorMacro.self]

    func testBasicMirror() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct _User {
                let id: UUID
                let name: String
                var isActive: Bool = false
            }
            """,
            expandedSource: """
            struct _User {
                let id: UUID
                let name: String
                var isActive: Bool = false
            }

            public struct User {
                public let id: UUID
                public let name: String
                public var isActive: Bool = false
                public init(id: UUID, name: String, isActive: Bool = false) {
                    self.id = id
                    self.name = name
                    self.isActive = isActive
                }
            }
            """,
            macros: macros
        )
    }

    func testConformancesAndGenerics() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct _Box<T>: Equatable, Sendable where T: Sendable {
                let value: T
            }
            """,
            expandedSource: """
            struct _Box<T>: Equatable, Sendable where T: Sendable {
                let value: T
            }

            public struct Box<T>: Equatable, Sendable where T: Sendable {
                public let value: T
                public init(value: T) {
                    self.value = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInitializedLetIsConstantNotParameter() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct _Config {
                let version: Int = 1
                var name: String
            }
            """,
            expandedSource: """
            struct _Config {
                let version: Int = 1
                var name: String
            }

            public struct Config {
                public let version: Int = 1
                public var name: String
                public init(name: String) {
                    self.name = name
                }
            }
            """,
            macros: macros
        )
    }

    func testComputedAndStaticAreSkipped() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct _Point {
                let x: Double
                let y: Double
                static let origin = _Point(x: 0, y: 0)
                var magnitude: Double { (x * x + y * y).squareRoot() }
            }
            """,
            expandedSource: """
            struct _Point {
                let x: Double
                let y: Double
                static let origin = _Point(x: 0, y: 0)
                var magnitude: Double { (x * x + y * y).squareRoot() }
            }

            public struct Point {
                public let x: Double
                public let y: Double
                public init(x: Double, y: Double) {
                    self.x = x
                    self.y = y
                }
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesMissingUnderscore() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct User {
                let id: UUID
            }
            """,
            expandedSource: """
            struct User {
                let id: UUID
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                    @PublicMirror requires the struct name to begin with an underscore (e.g. `_User`). \
                    It generates the public twin with the underscore removed (`User`) in the same scope, \
                    so the source-of-truth name must differ from the generated name.
                    """,
                    line: 2,
                    column: 8
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesMissingType() {
        assertMacroExpansion(
            """
            @PublicMirror
            struct _Thing {
                var count = 0
            }
            """,
            expandedSource: """
            struct _Thing {
                var count = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Stored property 'count' needs an explicit type annotation so @PublicMirror can generate the public initializer.",
                    line: 3,
                    column: 9
                )
            ],
            macros: macros
        )
    }
}
