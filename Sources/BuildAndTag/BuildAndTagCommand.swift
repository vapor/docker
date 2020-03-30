import ConsoleKit
import Foundation

public enum ColorOutputSetting: RawRepresentable, Equatable, Hashable, LosslessStringConvertible, CaseIterable, ExpressibleByNilLiteral, ExpressibleByBooleanLiteral {
    case automatic // use the default
    case forcedOn // force color output on
    case forcedOff // force color output off
    
    public init?(rawValue: String?) { switch rawValue?.lowercased() {
        case "yes", "on", "true":
            self = .forcedOn
        case "no", "off", "false":
            self = .forcedOff
        case "auto", .none:
            self = .automatic
        default:
            return nil
    } }
    
    public init?(_ description: String) { self.init(rawValue: description) }
    
    public init(nilLiteral: ()) { self = .automatic }
    
    public init(booleanLiteral value: BooleanLiteralType) { self = value ? .forcedOn : .forcedOff }
    
    public var rawValue: String? { switch self {
        case .automatic: return "auto"
        case .forcedOff: return "off"
        case .forcedOn: return "on"
    } }
    
    public var description: String { self.rawValue! }
    
    public var sytlizedOutputOverrideValue: Bool? { switch self {
        case .automatic: return nil
        case .forcedOff: return false
        case .forcedOn: return true
    } }
}

extension Console {
    func dockerBuildCustomActivity() -> ActivityIndicator<CustomActivity> {
        return self.customActivity(
            frames: [
                "[💨                                   📦  ]",
                "[💨🏷                                  📦  ]",
                "[💨  🏷                                📦  ]",
                "[💨    🏷                              📦  ]",
                "[💨      🏷                            📦  ]",
                "[💨        🏷                          📦  ]",
                "[💨          🏷                        📦  ]",
                "[💨            🏷                      📦  ]",
                "[💨              🏷                    📦  ]",
                "[💨                🏷                  📦  ]",
                "[💨                  🏷                📦  ]",
                "[💨                    🏷              📦  ]",
                "[💨                      🏷            📦  ]",
                "[💨                        🏷          📦  ]",
                "[💨                          🏷        📦  ]",
                "[💨                            🏷      📦  ]",
                "[💨                              🏷    📦  ]",
                "[💨                                🏷  📦  ]",
                "[💨                                  🏷📦  ]",
                "[💨                                   🎁  ]",
                "[💨                                   🎁  ]",
                "[💨                                   🎁  ]",
                "[💨                                   🎁  ]",
            ],
            success: "[                                     🎁✅]",
            failure: "[                                     🎁❌]"
        )
    }
}

public final class BuildAndTagCommand: Command {
    public struct Signature: CommandSignature {
        @Option(name: "color", help: "Enables colorized output (yes|no|auto)")
        var color: ColorOutputSetting?
        
        @Flag(name: "stop-after-build", short: "d" /* as in dry run */, help: "Don't push images, just build them")
        var stopAfterBuild: Bool
        
        @Flag(name: "dry-run-for-push", short: "N", help: "Generate and show the commands to push images without actually pushing them")
        var dontReallyPushImages: Bool

        @Option(name: "skip-repos", help: "Comma-separated list of image respositories to skip.")
        var excludedRepos: String?

        @Option(name: "skip-versions", help: "Comma-separated list of Swift versions to skip.")
        var excludedSwiftVersions: String?

        @Option(name: "skip-images", help: "Comma-separated list of fully-qualified image tags to skip.")
        var excludedImageTags: String?
        
        @Flag(name: "headless", short: "y", help: "Don't prompt for confirmation of actions")
        var headlessMode: Bool
        
        @Flag(name: "verbose", short: "v", help: "Run `docker build` and `docker push` in verbose mode")
        var verbose: Bool

        public init() {}
    }

    public init() {
        interruptSource.setEventHandler { [weak self] in
            if self?.currentTask?.isRunning ?? false {
                self?.currentTask?.interrupt()
            }
            signal(SIGINT, SIG_DFL)
            raise(SIGINT)
        }
        interruptSource.resume()
        signal(SIGINT, SIG_IGN)
    }
    
    deinit {
        interruptSource.cancel()
    }
    
    public var help: String { "Builds, tags, and pushes prebuilt Docker images" }
    
    private var interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.main)
    private var currentTask: Process? = nil
    func runCommand(_ command: [String], preservingStreams: Bool) throws -> Int32 {
        precondition(currentTask == nil)
        currentTask = Process()
        defer { currentTask = nil }
        currentTask?.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        currentTask?.arguments = command
        currentTask?.standardInput = preservingStreams ? FileHandle.standardInput : FileHandle.nullDevice
        currentTask?.standardOutput = preservingStreams ? FileHandle.standardOutput : FileHandle.nullDevice
        currentTask?.standardError = preservingStreams ? FileHandle.standardError : FileHandle.nullDevice
        try currentTask?.run()
        currentTask?.waitUntilExit()
        return currentTask!.terminationStatus
    }
    
    func getAndPrintSpecs(context: CommandContext, signature: Signature) -> [ImageSpecification] {
        let excludedRepos = signature.excludedRepos?.components(separatedBy: ",") ?? []
        let excludedSwiftVersions = signature.excludedSwiftVersions?.components(separatedBy: ",") ?? []
        let excludedTags = signature.excludedImageTags?.components(separatedBy: ",") ?? []
        var specs: [ImageSpecification] = []

        for repo in ImageBuilderConfiguration.preconfiguredImageSpecifications.repositories {
            guard !excludedRepos.contains(repo.name) else { continue }
            specs.append(contentsOf: repo.makeImageSpecs(withGlobalReplacements: ImageBuilderConfiguration.preconfiguredImageSpecifications.replacements))
        }
        specs.removeAll { spec in excludedTags.contains(spec.tag) || excludedSwiftVersions.contains { spec.tag.contains("swift:\($0)") } }
        specs.sort { $0.tag < $1.tag }
        
        context.console.info("Building \(specs.count) images:")
        for spec in specs {
            context.console.info("  - \(spec.tag)", newLine: !signature.verbose)
            if signature.verbose {
                context.console.info("  \(spec.buildArguments.map {"\($0.key)=\($0.value)"}.joined(separator: ", "))")
            }
        }
        context.console.info()
        return specs
    }
    
    public func run(using context: CommandContext, signature: Signature) throws {
        // Waiting on https://github.com/vapor/console-kit/pull/136/files for this
        //context.console.stylizedOutputOverride = (signature.color ?? .automatic).sytlizedOutputOverrideValue
        
        let specs = getAndPrintSpecs(context: context, signature: signature)
        
        if !signature.stopAfterBuild {
            context.console.warning("Built images will be pushed to Docker Hub.")
            context.console.warning()
        }
        
        if !signature.headlessMode {
            guard context.console.confirm("Proceed (y/n)?") else { return }
        }
        
        for spec in specs {
            context.console.output("📦 Building \(spec.tag)", style: .init(color: .brightCyan))
            
            var buildCommand = ["docker", "build", "--tag", spec.tag, "--label", "codes.vapor.images.prebuilt=1", "--file", spec.dockerfile]
            
            if !signature.verbose {
                buildCommand.append("--quiet")
            }
            buildCommand.append(contentsOf: spec.buildArguments.flatMap { ["--build-arg", "\($0.key)=\($0.value)"] })
            buildCommand.append(contentsOf: spec.extraBuildOptions)
            buildCommand.append(".")
            
            var indicator: ActivityIndicator<CustomActivity>? = nil

            if signature.verbose {
                context.console.output("Running build command: \(buildCommand.joined(separator: " "))", style: .init(color: .brightGreen))
            } else {
                indicator = context.console.dockerBuildCustomActivity()
            }
            indicator?.start(refreshRate: 50)
            if try runCommand(buildCommand, preservingStreams: signature.verbose) == 0 {
                if signature.verbose {
                    context.console.output("Finished building image \(spec.tag)", style: .init(color: .brightGreen))
                }
                indicator?.succeed()
                context.console.output("")
            } else {
                indicator?.fail()
                context.console.error("Build command failed! Stopping here.")
                return
            }
        }
        
        context.console.info("📦 All images built! 📦")
        guard !signature.stopAfterBuild else { return }
        
        for spec in specs {
            context.console.output("📦📤 Pushing \(spec.tag)...", style: .init(color: .brightCyan))
            
            let pushCommand = ["docker", "push", spec.tag]
            
            if signature.verbose || signature.dontReallyPushImages {
                context.console.output("📦📤 Running push command: \(pushCommand.joined(separator: " "))", style: .init(color: .brightGreen))
            }
            if signature.dontReallyPushImages {
                context.console.output("📦📤 As requested, not actually running push command...", style: .init(color: .blue))
            } else if try runCommand(pushCommand, preservingStreams: true) == 0 {
                context.console.output("📦📤 \(spec.tag) is pushed!", style: .init(color: .brightCyan))
            } else {
                context.console.error("Push command failed! Stopping here.")
                return
            }
        }
        
        if !signature.dontReallyPushImages {
            context.console.output("🎉📦💧 Successfully built and pushed \(specs.count) images! 💧📦🎉", style: .init(color: .brightWhite, isBold: true))
        }
    }
}
