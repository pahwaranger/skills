import Foundation
import Cache

/// Extracts the `skills/` subtree from a GitHub codeload `.tar.gz`. Uses the
/// system `tar`, whose nonzero exit on a torn/truncated archive becomes our
/// corrupt-tarball signal. A `.tar.gz` GitHub serves wraps everything in a
/// single top-level prefix dir (`<repo>-<sha>/`), with skills at
/// `<prefix>/skills/<name>/<files>`.
enum TarballExtractor {
    enum ExtractError: Error, Equatable {
        case tarFailed       // tar exited nonzero — corrupt/incomplete archive
        case noSkillsTree    // extraction succeeded but no skills/ subtree present
    }

    static func extractSkills(fromTarGz data: Data) throws -> [OriginSnapshot.Skill] {
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appending(path: "steve-extract-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let archive = work.appending(path: "origin.tar.gz")
        try data.write(to: archive)
        let outDir = work.appending(path: "out", directoryHint: .isDirectory)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = [
            "xzf", archive.path(percentEncoded: false),
            "-C", outDir.path(percentEncoded: false),
        ]
        tar.standardOutput = Pipe()
        tar.standardError = Pipe()
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw ExtractError.tarFailed }

        // The archive's single top-level entry is GitHub's <repo>-<sha> prefix dir.
        let top = try fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: [.isDirectoryKey])
        guard let prefix = top.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        else { throw ExtractError.noSkillsTree }

        let skillsDir = prefix.appending(path: "skills", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: skillsDir.path(percentEncoded: false)) else {
            throw ExtractError.noSkillsTree
        }

        return try readSkills(from: skillsDir)
    }

    private static func readSkills(from skillsDir: URL) throws -> [OriginSnapshot.Skill] {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]
        )
        var skills: [OriginSnapshot.Skill] = []
        for dir in entries {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let fileURLs = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            var files: [String: Data] = [:]
            for url in fileURLs {
                files[url.lastPathComponent] = try Data(contentsOf: url)
            }
            skills.append(OriginSnapshot.Skill(name: dir.lastPathComponent, files: files))
        }
        return skills
    }
}
