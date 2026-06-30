import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PublicMirrorPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PublicMirrorMacro.self,
    ]
}
