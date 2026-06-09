import Foundation

public struct CacheMetadata: Codable, Equatable, Sendable {
    public var commitSHA: String
    public var etag: String
    public var lastChecked: Date
    public var skipState: [String: String]  // skill name → Origin SHA when user skipped

    public init(commitSHA: String, etag: String, lastChecked: Date, skipState: [String: String]) {
        self.commitSHA = commitSHA
        self.etag = etag
        self.lastChecked = lastChecked
        self.skipState = skipState
    }
}

public enum CacheError: Error, Equatable {
    case missing   // dir or required file not found
    case corrupt   // metadata.json exists but is malformed
}

public struct OriginSnapshot: Sendable {
    public struct Skill: Sendable {
        public let name: String
        public let files: [String: Data]

        public init(name: String, files: [String: Data]) {
            self.name = name
            self.files = files
        }
    }
    public let commitSHA: String
    public let etag: String
    public let lastChecked: Date
    public let skills: [Skill]

    public init(commitSHA: String, etag: String, lastChecked: Date, skills: [Skill]) {
        self.commitSHA = commitSHA
        self.etag = etag
        self.lastChecked = lastChecked
        self.skills = skills
    }
}

public struct CacheStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func readMetadata() throws -> CacheMetadata {
        let file = root.appending(path: "metadata.json")
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            throw CacheError.missing
        }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(CacheMetadata.self, from: data)
        } catch {
            throw CacheError.corrupt
        }
    }

    public func writeMetadata(_ metadata: CacheMetadata) throws {
        let file = root.appending(path: "metadata.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(metadata)
        try data.write(to: file, options: .atomic)
    }

    public func skillFiles(named name: String) throws -> [String: Data] {
        let skillDir = root.appending(path: "skills/\(name)", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: skillDir.path(percentEncoded: false)) else {
            throw CacheError.missing
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: skillDir, includingPropertiesForKeys: nil
        )
        var result: [String: Data] = [:]
        for url in urls {
            result[url.lastPathComponent] = try Data(contentsOf: url)
        }
        return result
    }

    public func writeSkillFiles(named name: String, files: [String: Data]) throws {
        let skillDir = root.appending(path: "skills/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        for (filename, data) in files {
            let dest = skillDir.appending(path: filename)
            try data.write(to: dest, options: .atomic)
        }
    }

    public func rebuild(from snapshot: OriginSnapshot) throws {
        let skillsDir = root.appending(path: "skills", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: skillsDir.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: skillsDir)
        }
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for skill in snapshot.skills {
            try writeSkillFiles(named: skill.name, files: skill.files)
        }
        let metadata = CacheMetadata(
            commitSHA: snapshot.commitSHA,
            etag: snapshot.etag,
            lastChecked: snapshot.lastChecked,
            skipState: [:]
        )
        try writeMetadata(metadata)
    }
}
