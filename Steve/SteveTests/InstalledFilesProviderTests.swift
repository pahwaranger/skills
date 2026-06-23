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
//
// The injection seam (DiffPane.installedFilesProvider parameter) is verified
// by the build gate and the F4 XCUITest, not by a unit test — a pure Swift
// closure used at a call site cannot be meaningfully tested in isolation.

@Suite("InstalledFilesProvider — defaulting and injection")
struct InstalledFilesProviderTests {

    // MARK: — Shared provider reads from the sandbox dir

    /// `AppModel.fixtureMode()` returns a `sandboxSkillsDir` that contains the seeded
    /// installed files. A provider built from that dir using the real
    /// `makeInstalledFilesProvider` (from `FixtureEngine`) must return those files.
    /// This test would FAIL if `makeInstalledFilesProvider` had the wrong path logic.
    @Test @MainActor func sandboxProviderReadsFromSandboxDir() async throws {
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: .default)

        // Call the REAL shared function from FixtureEngine (same one SteveApp calls).
        let provider = makeInstalledFilesProvider(skillsDir: sandboxSkillsDir)

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

    // MARK: — Sandbox provider returns empty for unknown skills

    /// The sandbox provider returns an empty dictionary for a skill name that doesn't
    /// exist in the sandbox (e.g. a typo or a skill that was never seeded).
    @Test @MainActor func sandboxProviderReturnsEmptyForUnknownSkill() async throws {
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: .default)
        let provider = makeInstalledFilesProvider(skillsDir: sandboxSkillsDir)
        let files = provider("nonexistent-skill-xyz")
        #expect(files.isEmpty,
                "sandbox provider must return empty dict for skills not in the sandbox")
    }

    // MARK: — Fixture composition: same dir for hash and diff providers

    /// `AppModel.fixtureMode()` seeds the sandbox skills dir with the scenario's
    /// `installedFiles`. A provider built from that dir using `makeInstalledFilesProvider`
    /// returns the same file content as the seeded `installedFiles`, confirming state
    /// (hash) and diff (files) agree. This test would FAIL if the provider read from the
    /// wrong directory or used the wrong file-enumeration logic.
    @Test @MainActor func sandboxProviderContentMatchesSeededInstalledFiles() async throws {
        let scenario = FixtureScenario.default
        let (_, sandboxSkillsDir, _) = AppModel.fixtureMode(scenario: scenario)
        let provider = makeInstalledFilesProvider(skillsDir: sandboxSkillsDir)

        for entry in scenario.skills {
            let files = provider(entry.name)
            for (filename, expectedData) in entry.installedFiles {
                #expect(files[filename] == expectedData,
                        "\(entry.name)/\(filename): sandbox provider data must match seeded installedFiles")
            }
        }
    }
}
