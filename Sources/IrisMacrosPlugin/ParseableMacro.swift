import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct IrisPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = []
}
