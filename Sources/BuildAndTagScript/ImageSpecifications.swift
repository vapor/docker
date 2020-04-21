import Foundation

// MARK: - Perfunctory data models

public struct ImageBuilderConfiguration: Hashable, Equatable { // container for global options and a list of repos
    public let repositories: [ImageRepository]
    public let replacements: [String: String]
    
    public init(globalReplacements: [String: String] = [:], _ repositories: ImageRepository...) {
        self.init(globalReplacements: globalReplacements, repositories)
    }

    public init(globalReplacements: [String: String] = [:], _ repositories: [ImageRepository]) {
        self.repositories = repositories
        self.replacements = globalReplacements
    }
}

public struct ImageRepository: Hashable, Equatable {
    public let name: String // org + repo as appears in a tag like $ORG/$REPO:$VERSION-$VARIANT
    
    public let defaultDockerfile: String // relative from root, overrides default in overall specs
    public var replacements: [String : String]
    public var template: ImageTemplate // a template used for auto-generating a set of variants
    public let generatingVariations: ImageAutoVariantGroup // a set of variations to be automatically permuted and built

    public init(name: String, defaultDockerfile: String, replacements: [String: String] = [:], template: ImageTemplate, _ generatingVariations: ImageAutoVariantKeyedSet...) { // do a bunch of silly rigamarole to make sure the org and repo names are saved off where they're wanted
        self.name = name
        self.defaultDockerfile = defaultDockerfile
        self.replacements = replacements
        self.template = template
        self.generatingVariations = ImageAutoVariantGroup(sets: generatingVariations)
    }
    
    func permutedVariants(withGlobalReplacements globalReplacements: [String: String]) -> [[String: String]] {
        return self.generatingVariations.permute(withBaseReplacements: globalReplacements.updating(with: self.replacements))
    }
    
    func makeImageSpecs(withGlobalReplacements globalReplacements: [String: String]) -> [ImageSpecification] {
        func doReplacements(in template: String, using replacements: [String: String]) -> String {
            var result = template
            while let match = result.range(of: "\\$\\{[A-Za-z_:]+?\\}", options: .regularExpression) {
                if result[match] == "${:trimStems}" {
                    result = result.replacingCharacters(in: match, with: "").replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression).replacingOccurrences(of: "-$", with: "", options: .regularExpression)
                } else if result[match] == "${:trim}" {
                    result = result.replacingCharacters(in: match, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if result[match] == "${:chopVersion}" {
                    result = result.replacingCharacters(in: result.index(match.lowerBound, offsetBy: -2)..<match.upperBound, with: "")
                    // This will break if there are ten patches in one minor Swift release
                } else {
                    result = result.replacingCharacters(in: match, with: replacements[String(result[match].dropFirst(2).dropLast())] ?? "")
                }
            }
            return result
        }
        
        return self.permutedVariants(withGlobalReplacements: globalReplacements).enumerated().map { i, replacements in
            ImageSpecification(
                tag: doReplacements(in: self.template.nameTemplate, using: replacements),
                dockerfile: self.defaultDockerfile,
                buildArguments: self.template.buildArguments.mapValues { doReplacements(in: $0, using: replacements) },
                extraBuildOptions: self.template.extraBuildOptions,
                buildOrder: i,
                autoGenerationContext: replacements
            )
        }
    }
}

/// Notes:
/// - Template names and build arguments are subject to replacements based on the variants specified alongside the template.
/// - Neither names nor build arguments are expanded recursively - use recusion at an upper layer instead.
public struct ImageTemplate: Codable, Hashable, Equatable {
    public let nameTemplate: String // the template string used to generate image names from an auto variant set
    public let buildArguments: [String: String] // passed as `--build-arg` options; subject to template replacements from an auto variant set
    public var extraBuildOptions: [String] = [] // passed directly as command arguments to `docker build`, use with care
}

public struct ImageAutoVariantGroup: Hashable, Equatable {
    let sets: [ImageAutoVariantKeyedSet] // all sets in one group, keep as array instead of set so 1st-level set permute order is deterministic
    
    func permute(withBaseReplacements replacements: [String: String]) -> [[String: String]] {
        self.sets.reduce([replacements]) { p, set in set.valuesMergingKey.flatMap { v in p.map { $0.updating(with: v) } } }
    }
}

public struct ImageAutoVariantKeyedSet: Hashable, Equatable {
    let key: String
    let values: [ImageAutoVariantSetValue]
    
    var valuesMergingKey: [[String: String]] {
        self.values.map { $0.asRawValue }.map { v in [self.key: v.name].updating(with: v.replacements) }
    }
    
    init(_ key: String, _ values: ImageAutoVariantSetValue...) {
        self.key = key
        self.values = values
    }
}

public enum ImageAutoVariantSetValue: Hashable, Equatable {
    case empty // the empty string value; a variant to represent "normal"
    case value(String) // simple value; a variant where the set key plus this name is enough to fully specify
    case valueAndKeys(String, [String: String]) // a variant giving its name plus additional replacements needed to specify it
    
    var asRawValue: (name: String, replacements: [String: String]) { switch self {
        case .empty: return (name: "", replacements: [:])
        case .value(let name): return (name: name, replacements: [:])
        case .valueAndKeys(let name, let replacements): return (name: name, replacements: replacements)
    } }
}

public struct ImageSpecification: Codable, Hashable, Equatable { // self-contained specification of everything required to build a single image
    public let tag: String // verbatim tag passed to `docker build -t`
    public let dockerfile: String // relative from root
    public let buildArguments: [String: String] // values for `--build-arg`, fully evaluated for any replacements
    public let extraBuildOptions: [String] // additional commands options for `docker build`. avoid if possible.
    public let buildOrder: Int // the original index this spec had in the permutation matrix for the repo that it belongs to
    public let autoGenerationContext: [String: String] // contains the final set of replacements that were applied to the template after permutation and cascading
}

// MARK: - Logic to get the set of desired specs in usable form

public func getAllPreconfiguredSpecs(
    excludingRepositories excludedRepos: [String] = [],
    swiftVersions excludedSwiftVersions: [String] = [],
    tags excludedTags: [String] = []
) -> [ImageSpecification] {
    var specs: [ImageSpecification] = []

    for repo in ImageBuilderConfiguration.preconfiguredImageSpecifications.repositories {
        guard !excludedRepos.contains(repo.name) else { continue }
        specs.append(contentsOf: repo.makeImageSpecs(withGlobalReplacements: ImageBuilderConfiguration.preconfiguredImageSpecifications.replacements))
    }
    specs.removeAll { spec in excludedTags.contains(spec.tag) || excludedSwiftVersions.contains { spec.tag.contains("swift:\($0)") } }
    return specs
}

// MARK: - Very helpful utility method

extension Dictionary {
    public func updating(with other: [Key : Value]) -> [Key : Value] { self.merging(other, uniquingKeysWith: { $1 }) }
}

// MARK: - Actual specs!

extension ImageBuilderConfiguration {

    private static var commonSwiftImageTemplate: ImageTemplate {
        .init(
            nameTemplate: "${REPOSITORY_NAME}:${SWIFT_VERSION}-${IMAGE_OS_VERSION}-${IMAGE_VAPOR_VARIANT}${:trimStems}",
            buildArguments: [
                "SWIFT_BASE_IMAGE": "${SWIFT_BASE_REPO_NAME}:${SWIFT_BASE_VERSION}-${IMAGE_OS_VERSION}${:trimStems}",
                "ADDITIONAL_APT_DEPENDENCIES": "${LIBSSL_DEPENDENCY} ${CURL_DEPENDENCY}${:trim}"
            ]
        )
    }
    
    private static var ubuntuXenialDeps: [String: String] { ["UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES": "libicu55 libcurl3"] }
    private static var ubuntuBionicDeps: [String: String] { ["UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES": "libicu60 libcurl4"] }
    
    public static var preconfiguredImageSpecifications: Self { return .init(
    
        globalReplacements: [
            "SWIFT_LATEST_RELEASE_VERSION": "5.2.2", // last updated 04/21/2020
            "SWIFT_BASE_REPO_NAME": "swift",
            "SWIFT_BASE_VERSION": "${SWIFT_VERSION}",
        ],
    
// MARK: - Vapor Swift repo, `vapor/swift` prefix, duplicate declaration to make the "latest" tag without permutation.
        .init(name: "vapor/swift", defaultDockerfile: "swift.Dockerfile",
              replacements: ["REPOSITORY_NAME": "vapor/swift", "IMAGE_OS_VERSION": ""],
              template: commonSwiftImageTemplate,
              .init("SWIFT_VERSION", .value("latest")),
              .init("IMAGE_VAPOR_VARIANT", .empty, .valueAndKeys("ci", ["CURL_DEPENDENCY": "curl"]))
        ),
// MARK: - Vapor Swift repo, `vapor/swift` prefix
        .init(
            name: "vapor/swift",
            defaultDockerfile: "swift.Dockerfile",
            replacements: ["REPOSITORY_NAME": "vapor/swift"],
            template: commonSwiftImageTemplate,
            
            // Vapor 4-compatible Swift versions we build.
            .init("SWIFT_VERSION",
                // Build latest release version and aliases for it, including "latest".
                // Master is not latest; it's a nightly.
                .value("${SWIFT_LATEST_RELEASE_VERSION}${:chopVersion}"),
                .value("${SWIFT_LATEST_RELEASE_VERSION}"),
                
                // Build swiftlang/nightly-master as master.
                .valueAndKeys("master", ["SWIFT_BASE_REPO_NAME": "swiftlang/swift", "SWIFT_BASE_VERSION": "nightly-master"])
            ),
            // Swift Ubuntu OS version variant set - none (bionic by default), bionic, and xenial.
            .init("IMAGE_OS_VERSION", .empty, .value("bionic"), .value("xenial")),
            // Image build purpose variant set - standard (no extra tag) and CI (requiring curl installed)
            .init("IMAGE_VAPOR_VARIANT", .empty, .valueAndKeys("ci", ["CURL_DEPENDENCY": "curl"]))
        ),
        
// MARK: - Vapor3 legacy org and swift repo, vapor3/swift* images
        .init(
            name: "vapor3/swift",
            defaultDockerfile: "swift.Dockerfile",
            replacements: ["REPOSITORY_NAME": "vapor3/swift", "LIBSSL_DEPENDENCY": "libssl-dev"],
            template: commonSwiftImageTemplate,
            // Build a couple of older ones and their aliases.
            .init("SWIFT_VERSION",
                .value("${SWIFT_LATEST_RELEASE_VERSION}${:chopVersion}"), .value("${SWIFT_LATEST_RELEASE_VERSION}"),
                .value("5.1.5"), .value("5.1"),
                .value("5.0.3"), .value("5.0")
            ),
            .init("IMAGE_OS_VERSION", .empty, .value("xenial"), .value("bionic")),
            .init("IMAGE_VAPOR_VARIANT", .empty, .valueAndKeys("ci", ["CURL_DEPENDENCY": "curl"]))
        ),

// MARK: - Ubuntu repo, `vapor/ubuntu` prefix
        .init(
            name: "vapor/ubuntu",
            defaultDockerfile: "ubuntu.Dockerfile",
            template: .init(
                nameTemplate: "vapor/ubuntu:${UBUNTU_OS_IMAGE_VERSION}",
                buildArguments: [
                    "UBUNTU_OS_IMAGE_VERSION": "${UBUNTU_OS_IMAGE_VERSION}",
                    "UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES": "${UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES}"
                ]
            ),
            
            // Build images for xenial and bionic, and provide version number aliases.
            .init("UBUNTU_OS_IMAGE_VERSION",
                .valueAndKeys("16.04", ubuntuXenialDeps), .valueAndKeys("xenial", ubuntuXenialDeps),
                .valueAndKeys("18.04", ubuntuBionicDeps), .valueAndKeys("bionic", ubuntuBionicDeps)
            )
        )

    ) }
}
