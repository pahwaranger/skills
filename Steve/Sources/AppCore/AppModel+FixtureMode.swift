import Foundation
#if SWIFT_PACKAGE
import Cache
import OriginClient
import FixtureEngine
#endif

// MARK: — AppModel fixture-mode factory (ADR 0009)

extension AppModel {

    /// Composes an `AppModel` wired to an ephemeral sandbox and a fixture origin transport,
    /// so the real `OriginClient -> Cache -> StateEngine -> ReviewSession` pipeline runs
    /// against canned data rather than the live GitHub repo.
    ///
    /// **Hard sandbox isolation (ADR 0009):**
    /// - Skills directory and cache resolve under
    ///   `NSTemporaryDirectory()/steve-fixtures-<UUID>/` — never touching
    ///   `~/.claude/skills/` or the real cache root.
    /// - A throwaway `UserDefaults` suite named `"steve-fixture-<UUID>"` is created and
    ///   a `SettingsStore(defaults:)` is built from it. The `interval` and
    ///   `automaticChecksEnabled` values passed to `AppModel.init` are derived from THAT
    ///   store — `UserDefaults.standard` is never read or written.
    ///   The suite is returned in the tuple so callers can inspect or pre-seed it and
    ///   verify that fixture settings are isolated from `.standard`.
    ///
    /// **Transport:**
    /// Only the HTTP transport is faked. A fixture `HTTPTransport` serves:
    /// - The commit-SHA probe endpoint (returning a deterministic fake SHA).
    /// - A real multi-skill `tar.gz` built from the scenario's origin files.
    /// Everything downstream (OriginClient, TarballExtractor, CacheStore, StateEngine)
    /// runs real code.
    ///
    /// **Return value:**
    /// Returns a tuple of `(AppModel, sandboxSkillsDir, fixtureDefaults)` so:
    /// - The app layer can build a matching `installedFilesProvider` (needed for F2).
    /// - Callers can verify that settings operations go through the throwaway suite,
    ///   not `.standard` (required by ADR 0009's isolation guarantee).
    ///
    /// - Parameter scenario: The fixture scenario to seed. Defaults to `.default`.
    /// - Returns: `(model, sandboxSkillsDir, fixtureDefaults)` — the model is ready to `start()`.
    @MainActor
    public static func fixtureMode(
        scenario: FixtureScenario = .default
    ) -> (AppModel, sandboxSkillsDir: URL, fixtureDefaults: UserDefaults) {
        // 1. Create a throwaway UserDefaults suite — never .standard.
        //    SettingsStore reads interval and automaticChecksEnabled from this suite.
        let suiteName = "steve-fixture-\(UUID().uuidString)"
        let fixtureDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        let settingsStore = SettingsStore(defaults: fixtureDefaults)

        // 2. Create ephemeral sandbox root.
        let sandboxRoot = FileManager.default.temporaryDirectory
            .appending(path: "steve-fixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sandboxSkillsDir = sandboxRoot.appending(path: "skills", directoryHint: .isDirectory)
        let sandboxCacheDir  = sandboxRoot.appending(path: "cache", directoryHint: .isDirectory)

        // Create sandbox directories up front so seeding and hashing work.
        try? FileManager.default.createDirectory(at: sandboxSkillsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sandboxCacheDir, withIntermediateDirectories: true)

        // 3. Seed the sandbox cache (C) and skills directory (S).
        let cacheStore = CacheStore(root: sandboxCacheDir)
        seedSandbox(scenario: scenario, skillsDir: sandboxSkillsDir, cacheStore: cacheStore)

        // 4. Build the fixture origin tarball (O) — only non-removed skills.
        let originSkills = scenario.skills.compactMap { entry -> (name: String, files: [String: Data])? in
            guard let files = entry.originFiles else { return nil }
            return (name: entry.name, files: files)
        }
        let fixtureSHA = "fixture-sha-\(UUID().uuidString.prefix(8))"
        // Force-unwrap: a tarball-build failure must surface loudly in fixture/dev code,
        // not silently produce empty tarball and wrong derived states.
        let tarData = try! MultiSkillTarball.build(skills: originSkills)

        // 5. Build the fixture HTTP transport.
        let transport = FixtureHTTPTransport(sha: fixtureSHA, tarData: tarData)

        // 6. Build the installed-skills provider from the sandbox skills directory.
        let installedSkillsProvider = makeInstalledSkillsProvider(skillsDir: sandboxSkillsDir)

        // 7. Derive interval and automaticChecksEnabled from the throwaway suite — not .standard.
        let interval = TimeInterval(settingsStore.minutesBetweenChecks) * 60
        let automaticChecksEnabled = settingsStore.automaticChecksEnabled

        // 8. Compose the AppModel with sandbox dirs + fixture transport + throwaway settings.
        let model = AppModel(
            owner: "fixture", repo: "fixture", branch: "main",
            transport: transport,
            cacheRoot: sandboxCacheDir,
            interval: interval,
            automaticChecksEnabled: automaticChecksEnabled,
            installedSkills: installedSkillsProvider
        )

        return (model, sandboxSkillsDir, fixtureDefaults)
    }

    // MARK: — Private helpers

    /// Seeds the sandbox skills directory (S) and cache (C) from the scenario entries.
    private static func seedSandbox(
        scenario: FixtureScenario,
        skillsDir: URL,
        cacheStore: CacheStore
    ) {
        let fm = FileManager.default

        // Write initial cache metadata so the CacheStore is in a valid state.
        try? cacheStore.writeMetadata(CacheMetadata(
            commitSHA: "fixture-pre-seed",
            etag: "",
            lastChecked: Date(timeIntervalSinceReferenceDate: 0),
            skipState: [:]
        ))

        for entry in scenario.skills {
            // Write S: sandbox skills directory.
            let skillDir = skillsDir.appending(path: entry.name, directoryHint: .isDirectory)
            try? fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
            for (filename, data) in entry.installedFiles {
                let dest = skillDir.appending(path: filename)
                try? data.write(to: dest, options: .atomic)
            }

            // Write C: sandbox cache.
            try? cacheStore.writeSkillFiles(named: entry.name, files: entry.cacheFiles)
        }
    }

    /// Builds a provider that scans the sandbox skills directory and computes content
    /// hashes using the same SHA256 scheme as the production provider. The sandbox
    /// skills directory stands in for `~/.claude/skills/`.
    private static func makeInstalledSkillsProvider(
        skillsDir: URL
    ) -> @Sendable () -> [String: String] {
        return {
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: skillsDir.path(percentEncoded: false))
            else { return [:] }

            // The CacheStore.contentHash(for:) method expects the store's root to have
            // a `skills/` subdirectory containing per-skill directories.
            // The sandboxSkillsDir IS the `skills/` dir, so we pass its parent as root.
            let storeRoot = skillsDir.deletingLastPathComponent()
            let store = CacheStore(root: storeRoot)

            var result: [String: String] = [:]
            for name in names {
                let skillPath = skillsDir.appending(path: name, directoryHint: .isDirectory)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: skillPath.path(percentEncoded: false), isDirectory: &isDir),
                      isDir.boolValue else { continue }
                if let hash = try? store.contentHash(for: name) {
                    result[name] = hash
                }
            }
            return result
        }
    }
}

// MARK: — Fixture HTTP transport

/// An `HTTPTransport` that serves a fixture commit-SHA probe and a pre-built tarball.
/// Only the network boundary is faked; everything downstream runs real code.
final class FixtureHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let sha: String
    private let tarData: Data

    init(sha: String, tarData: Data) {
        self.sha = sha
        self.tarData = tarData
    }

    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let urlString = url.absoluteString
        if urlString.contains("commits") {
            // Probe: return 200 with bare SHA body and ETag header.
            return HTTPResponse(
                status: 200,
                headers: ["ETag": "\"\(sha)\""],
                body: Data((sha + "\n").utf8)
            )
        } else if urlString.contains("tar.gz") || urlString.contains("codeload") {
            // Tarball: serve the pre-built multi-skill archive.
            return HTTPResponse(status: 200, headers: [:], body: tarData)
        }
        // Default: treat other URLs (repos endpoint for default-branch resolution) as 404.
        // The fixture model uses "main" as the branch and does not need branch resolution.
        return HTTPResponse(status: 404, headers: [:], body: Data())
    }
}
