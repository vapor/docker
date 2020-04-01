import ConsoleKit
import LeafKit
import Foundation

struct LeafEmbeddedFiles: LeafFiles { // think "EmbbeddedRunLoop"
    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path, isDirectory: false), options: .mappedIfSafe)
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            return eventLoop.makeSucceededFuture(buffer)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
}

public final class GenerateHubREADMECommand: Command {
    public var help = "Generate README files for each repository based on Leaf templates"
    
    public struct Signature: CommandSignature {
        @Flag(name: "verbose", short: "v", help: "Print additional information about progress to the console,")
        var verbose: Bool
        
        @Flag(name: "debug", short: "D", help: "Enable additional debugging information output. Implies -v.")
        var debug: Bool
        
        public init() {}
    }
    
    public init() {}
    
    public func run(using context: CommandContext, signature: Signature) throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? elg.syncShutdownGracefully() }
        
        let renderer = LeafRenderer(
            configuration: .init(rootDirectory: Array(URL(fileURLWithPath: #file, isDirectory: false).pathComponents.dropLast(3)).joined(separator: "/")),
            files: LeafEmbeddedFiles(),
            eventLoop: elg.next())
        
        let orgs = Dictionary(grouping: getAllPreconfiguredSpecs(), by: { $0.tag.prefix { $0 != "/" } })
        
        for (org, specs) in orgs {
            guard !specs.isEmpty else { continue }
            list(specs: specs, heading: "Found \(specs.count) specs in \(org) org:", in: context, verbose: signature.verbose, debug: signature.debug)
            
            var leafData: [String: LeafData] = [:]
            
            let splitSpecs: [[ImageSpecification]] = specs.reduce(into: [[specs[0]]]) { a, s in
                s.tag.hasPrefix(a.last![0].tag.prefix { $0 != "-" }) ? a[a.endIndex - 1].append(s) : a.append([s]) }
            
            leafData["org"] = .string(String(org))
            leafData["specsByVersion"] = .array(splitSpecs.map { .array($0.map { ["tag": .string($0.tag)] }) })
            
            let rendered = try renderer.render(path: "templates/\(org).leaf", context: leafData).wait()
            let renderedBlob = rendered.readableBytesView
            
            context.console.info("📄 Generated README for \(org) org!")
            if signature.debug {
                context.console.info("Dumping generated contents...")
                context.console.info()
                String(bytes: renderedBlob, encoding: .utf8)!.components(separatedBy: "\n").forEach {
                    context.console.print($0)
                }
            }
            context.console.info()
            
            context.console.info("📄 Saving to \(FileManager.default.currentDirectoryPath.appending("/\(org).md"))")
            try Data(renderedBlob).write(to: URL(fileURLWithPath: "", isDirectory: true).appendingPathComponent("\(org).md"))
            context.console.info("📄 Done!")
            context.console.info()
        }
        
        context.console.info("All READMEs generated!")
    }
}
