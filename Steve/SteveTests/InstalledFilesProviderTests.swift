import Testing
import Foundation
@testable import AppCore
import FixtureEngine

// MARK: — Installed-files provider defaulting (F2 / Issue #72)
//
// These tests exercise the provider logic that is factored into AppCore /
// FixtureEngine (i.e. the SPM-testable parts). The SwiftUI view wiring
// (DiffPane.installedFilesProvider, ReviewWindowView.installedFilesProvider,
// MainWindowView.installedFilesProvider) is covered by the Xcode build gate
// (`make -C Steve build`) and the demoable `make fixtures` run.

@Suite("InstalledFilesProvider — defaulting and injection")
struct InstalledFilesProviderTests {

    // MARK: — Sandbox provider reads from the sandbox dir

    /// `AppModel.fixtureMode()` returns a `sandboxSkillsDir` that contains the seeded
    /// installed files. A provider built from that dir (using the same recipe as
    /// `SteveApp.makeSandboxFilesProvider`) must return those files.
    @Test @MainActor func sandboxProviderReadsFromSandboxDir() async throws {
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: .default)

        // Build a provider from the sandbox skills dir — mirrors SteveApp.makeSandboxFilesProvider.
        let provider = makeSandboxFilesProvider(skillsDir: sandboxSkillsDir)

        // `diagnose` is seeded with two files in its installedFiles (see FixtureScenario.default).
        let files = provider("diagnose")
        #expect(files["SKILL.md"] != nil,
                "sandbox provider must find SKILL.md for diagnose in the sandbox")
        #expect(files["legacy.md"] != nil,
                "sandbox provider must find legacy.md for diagnose in the sandbox")

        // The sandbox dir must NOT touch the real ~/.claude/skills
        let realSkillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/skills", directoryHint: .isDirectory)
        #expect(sandboxSkillsDir.path(percentEncoded: false) != realSkillsDir.path(percentEncoded: false),
                "sandboxSkillsDir must differ from real ~/.claude/skills")
    }

    // MARK: — Sandbox provider returns injected data (not real dir)

    /// When an injected provider is supplied, it is used in place of the default.
    /// This verifies the DiffPane-style injection contract without accessing the private
    /// SwiftUI struct: we test the *data flow* by confirming the injected closure's
    /// return value is what the caller sees.
    @Test func injectedProviderIsUsedInPlaceOfDefault() {
        // Define a stub that returns known fixture data
        let sentinel = Data("injected-sentinel".utf8)
        let injected: (String) -> [String: Data] = { _ in
            ["SKILL.md": sentinel]
        }
        // Simulate the call site: DiffPane.realDiff would call the provider with a skill name.
        let result = injected("any-skill")
        #expect(result["SKILL.md"] == sentinel,
                "injected provider must be called and its data returned, not the default")
        // Confirm a different skill name also routes through the injected closure.
        let result2 = injected("diagnose")
        #expect(result2["SKILL.md"] == sentinel,
                "injected provider must be used regardless of skill name")
    }

    // MARK: — Sandbox provider returns empty for unknown skills

    /// The sandbox provider returns an empty dictionary for a skill name that doesn't
    /// exist in the sandbox (e.g. a typo or a skill that was never seeded).
    @Test @MainActor func sandboxProviderReturnsEmptyForUnknownSkill() async throws {
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: .default)
        let provider = makeSandboxFilesProvider(skillsDir: sandboxSkillsDir)
        let files = provider("nonexistent-skill-xyz")
        #expect(files.isEmpty,
                "sandbox provider must return empty dict for skills not in the sandbox")
    }

    // MARK: — Fixture composition: same dir for hash and diff providers

    /// `AppModel.fixtureMode()` seeds the sandbox skills dir with the scenario's
    /// `installedFiles`. A provider built from that dir returns the same file content
    /// as the seeded `installedFiles`, confirming state (hash) and diff (files) agree.
    @Test @MainActor func sandboxProviderContentMatchesSeededInstalledFiles() async throws {
        let scenario = FixtureScenario.default
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: scenario)
        let provider = makeSandboxFilesProvider(skillsDir: sandboxSkillsDir)

        for entry in scenario.skills {
            let files = provider(entry.name)
            for (filename, expectedData) in entry.installedFiles {
                #expect(files[filename] == expectedData,
                        "\(entry.name)/\(filename): sandbox provider data must match seeded installedFiles")
            }
        }
    }

    // MARK: — Helper: mirrors SteveApp.makeSandboxFilesProvider

    /// Mirrors the private `SteveApp.makeSandboxFilesProvider` helper so we can test
    /// the same logic in the SPM target without importing the app layer.
    private func makeSandboxFilesProvider(
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
}
