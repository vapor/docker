import Foundation
import ConsoleKit
import BuildAndTag

let console: Console = Terminal()
var input = CommandInput(arguments: CommandLine.arguments)
var context = CommandContext(console: console, input: input)

var commands = Commands(enableAutocomplete: true)
commands.use(BuildAndTagCommand(), as: "build", isDefault: true)

do {
    let group = commands
        .group(help: "Build and tag script")
    try console.run(group, input: input)
} catch let error {
    console.error("\(error)")
    exit(1)
}
