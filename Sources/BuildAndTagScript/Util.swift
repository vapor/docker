import ConsoleKit

func list(specs: [ImageSpecification], heading: String, in context: CommandContext, verbose: Bool, debug: Bool) {
    context.console.info(heading)
    for spec in specs {
        context.console.info("  - \(spec.tag)", newLine: !(verbose || debug))
        if verbose || debug {
            context.console.info(" [\(spec.buildOrder)] \(spec.buildArguments.map { "\($0)=\($1)" }.joined(separator: ", "))")
            if debug {
                context.console.info("\tCTX:[\(spec.autoGenerationContext.map { "\($0)=\($1)" })]")
            }
        }
    }
    context.console.info()
}
