import Foundation

/// Builds an installed-files provider that reads from the given skills directory.
///
/// Returns a closure `(skillName: String) -> [String: Data]` that lists the files
/// in `skillsDir/<skillName>/` and returns their contents keyed by filename.
/// Returns an empty dictionary if the directory does not exist or cannot be read.
///
/// This is the single source of truth used by both `SteveApp` (fixture mode composition)
/// and `InstalledFilesProviderTests` (unit tests). Having it in `FixtureEngine` means
/// the test exercises the real shared function — a bug in this logic would cause tests to fail.
public func makeInstalledFilesProvider(
    skillsDir: URL
) -> (String) -> [String: Data] {
    return { skillName in
        let skillDir = skillsDir.appending(path: skillName, directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillDir, includingPropertiesForKeys: nil
        ) else { return [:] }
        var result: [String: Data] = [:]
        for url in entries {
            if let data = try? Data(contentsOf: url) {
                result[url.lastPathComponent] = data
            }
        }
        return result
    }
}
