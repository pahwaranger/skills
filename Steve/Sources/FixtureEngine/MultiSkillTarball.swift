import Foundation

/// Builds a real multi-skill tar.gz archive that `TarballExtractor` can parse.
///
/// The archive format matches what GitHub's codeload endpoint produces:
/// a single top-level prefix directory (`<prefix>/skills/<name>/<files>`).
/// Use this in fixture transports to serve a realistic origin snapshot.
///
/// Generalises the single-skill `makeFakeTarGz` helper in AppCoreTests.swift
/// to support multiple skills — and lives in non-test code so the production
/// app layer (F2 runnable mode) can reuse it without importing the test target.
public enum MultiSkillTarball {
    public enum BuildError: Error {
        case tarFailed(Int32)
    }

    /// Builds a tar.gz archive containing all given skills under a synthetic
    /// top-level prefix, in the format TarballExtractor expects.
    ///
    /// - Parameter skills: An array of (name, file-map) pairs. Each skill
    ///   directory will be populated with the given files.
    /// - Returns: The raw bytes of a valid `.tar.gz` archive.
    public static func build(skills: [(name: String, files: [String: Data])]) throws -> Data {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appending(path: "steve-fixture-tarball-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: tmpDir) }

        let prefix = "repo-fixture-abc"
        let skillsRoot = tmpDir.appending(path: "\(prefix)/skills", directoryHint: .isDirectory)
        try fm.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        for skill in skills {
            let skillDir = skillsRoot.appending(path: skill.name, directoryHint: .isDirectory)
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
            for (filename, data) in skill.files {
                let dest = skillDir.appending(path: filename)
                try data.write(to: dest, options: .atomic)
            }
        }

        let tarGzPath = tmpDir.appending(path: "archive.tar.gz").path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", tarGzPath,
            "-C", tmpDir.path(percentEncoded: false),
            prefix
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BuildError.tarFailed(process.terminationStatus)
        }

        return try Data(contentsOf: URL(fileURLWithPath: tarGzPath))
    }
}
