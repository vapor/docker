import Foundation
import ConsoleKit
import BuildAndTagScript

#if Xcode
do {
    if let srcdir = ((try? PropertyListSerialization.propertyList(from:
            Data(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath
                .appending("/../../../info.plist"))), options: [], format: nil)) as? [String: Any])?["WorkspacePath"] as? String,
       FileManager.default.fileExists(atPath: "\(srcdir)/Package.swift")
    {
        FileManager.default.changeCurrentDirectoryPath(srcdir)
    } else if let srcdir = URL?(URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()),
           let _ = try? srcdir.appendingPathComponent("Package.swift").checkResourceIsReachable() {
        FileManager.default.changeCurrentDirectoryPath(srcdir.path)
    }
}
#endif

let console: Console = Terminal()
var input = CommandInput(arguments: CommandLine.arguments)
var context = CommandContext(console: console, input: input)

var commands = Commands(enableAutocomplete: true)
commands.use(BuildAndTagCommand(), as: "build", isDefault: true)
commands.use(GenerateHubREADMECommand(), as: "readmes", isDefault: true)

do {
    let group = commands
        .group(help: "Build and tag script")
    try console.run(group, input: input)
} catch let error {
    console.error("\(error)")
    exit(1)
}
