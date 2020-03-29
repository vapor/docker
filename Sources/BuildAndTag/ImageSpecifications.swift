import Foundation

// MARK: - Perfunctory data models

public struct ImageBuilderConfiguration: Hashable, Equatable { // container for global options and a list of repos
    public let repositories: Set<ImageRepository>
    public let replacements: [String: String]
    
    public init(globalReplacements: [String: String] = [:], _ repositories: ImageRepository...) {
        self.init(globalReplacements: globalReplacements, repositories)
    }

    public init(globalReplacements: [String: String] = [:], _ repositories: [ImageRepository]) {
        self.repositories = Set(repositories)
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
        self.generatingVariations = ImageAutoVariantGroup(sets: Set(generatingVariations))
    }
    
    func permutedVariants(withGlobalReplacements globalReplacements: [String: String]) -> Set<[String: String]> {
        return self.generatingVariations.permute(withBaseReplacements: globalReplacements.merging(self.replacements, uniquingKeysWith: { $1 }))
    }
    
    func makeImageSpecs(withGlobalReplacements globalReplacements: [String: String]) -> Set<ImageSpecification> {
        func doReplacements(in template: String, using replacements: [String: String]) -> String {
            var result = template
            while let match = result.range(of: "\\$\\{[A-Za-z_:]+?\\}", options: .regularExpression) {
                if result[match] == "${:trimStems}" {
                    result = result.replacingCharacters(in: match, with: "").replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression).replacingOccurrences(of: "-$", with: "", options: .regularExpression)
                } else if result[match] == "${:trim}" {
                    result = result.replacingCharacters(in: match, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    result = result.replacingCharacters(in: match, with: replacements[String(result[match].dropFirst(2).dropLast())] ?? "")
                }
            }
            return result
        }
        
        return Set(self.permutedVariants(withGlobalReplacements: globalReplacements).map { replacements in
            ImageSpecification(
                tag: doReplacements(in: self.template.nameTemplate, using: replacements),
                dockerfile: self.defaultDockerfile,
                buildArguments: self.template.buildArguments.mapValues { doReplacements(in: $0, using: replacements) },
                extraBuildOptions: self.template.extraBuildOptions,
                buildOrder: 0,
                autoGenerationContext: [replacements.map { k,v in "\(k): \(v)" }.joined(separator: ", ")]
            )
        })
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
    let sets: Set<ImageAutoVariantKeyedSet> // all sets in one group
    
    func permute(withBaseReplacements replacements: [String: String]) -> Set<[String: String]> {
        Set(self.sets.reduce(["": replacements]) { currentPermutes, set in
            return .init(uniqueKeysWithValues: set.valuesWithKeyApplied.flatMap { keyedValue in
                return currentPermutes.map { permuteKey, replacements in
                    ("\(permuteKey)++\(keyedValue[set.key]!)", replacements.merging(keyedValue, uniquingKeysWith: { $1 }))
                }
            })
        }.values)
    }
}

public struct ImageAutoVariantKeyedSet: Hashable, Equatable {
    let key: String
    let values: Set<ImageAutoVariantSetValue>
    
    var valuesWithKeyApplied: Set<[String: String]> {
        Set(self.values.map { value in
            var raw = value.asRawValue
            raw.replacements[self.key] = raw.name
            return raw.replacements
        })
    }
    
    init(_ key: String, _ values: ImageAutoVariantSetValue...) {
        self.key = key
        self.values = Set(values)
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
    public let buildOrder: Int // a key made available in case the order images are built and pushed in ever matters. what goes here isn't well-defined yet and it's pretty much ignored for now
    public let autoGenerationContext: [String]? // describes the nesting and permutation values used for generating this structure; nil if it was created directly
}
