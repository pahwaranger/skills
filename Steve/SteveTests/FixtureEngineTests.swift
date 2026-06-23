import Testing
import Foundation
@testable import AppCore
import FixtureEngine
import StateEngine
import OriginClient

// MARK: — Tracer bullet: fixtureMode derives correct states for all 6 skills

@Suite("FixtureEngine — scenario derivation")
struct FixtureScenarioDerivationTests {

    /// Tracer bullet: `AppModel.fixtureMode(scenario: .default)` after a launch check
    /// derives exactly the intended state for each of the six skills, proving S/C/O seeding
    /// through the real StateEngine pipeline.
    @Test @MainActor func fixtureModeDerivesCorrectStatesForAllSixSkills() async throws {
        let (model, _) = AppModel.fixtureMode()
        await model.start()

        guard let state = model.lastDerivedState else {
            Issue.record("lastDerivedState must be non-nil after fixtureMode start()")
            return
        }

        // to-prd → Removed on origin (absent from fixture origin; present in sandbox cache/skills)
        #expect(state.states["to-prd"] == .removedOnOrigin,
                "to-prd: absent from origin, present in cache → removedOnOrigin")

        // diagnose → Update available (rich multi-file diff: SKILL.md modified, reference.md added, legacy.md deleted)
        #expect(state.states["diagnose"] == .updateAvailable,
                "diagnose: O ≠ C and S ≠ O → updateAvailable")

        // tdd → Update available (single modified file)
        #expect(state.states["tdd"] == .updateAvailable,
                "tdd: O ≠ C and S ≠ O → updateAvailable")

        // verify → Skipped (C == O, S ≠ O)
        #expect(state.states["verify"] == .skipped,
                "verify: C == O, S ≠ O → skipped")

        // handoff → Up-to-date (S == O)
        #expect(state.states["handoff"] == .upToDate,
                "handoff: S == O → upToDate")

        // triage → Up-to-date (S == O)
        #expect(state.states["triage"] == .upToDate,
                "triage: S == O → upToDate")
    }

    // MARK: — Fixture transport serves a multi-skill tarball

    /// The fixture transport serves a multi-skill tarball that OriginClient extracts
    /// into an OriginSnapshot containing all non-removed skills with their files.
    @Test @MainActor func fixtureModeServesMultiSkillTarball() async throws {
        let (model, _) = AppModel.fixtureMode()
        await model.start()

        // All non-removed skills must appear in lastOriginSkillFiles
        let originFiles = model.lastOriginSkillFiles
        #expect(originFiles["diagnose"] != nil, "diagnose should be in origin snapshot")
        #expect(originFiles["tdd"] != nil, "tdd should be in origin snapshot")
        #expect(originFiles["verify"] != nil, "verify should be in origin snapshot")
        #expect(originFiles["handoff"] != nil, "handoff should be in origin snapshot")
        #expect(originFiles["triage"] != nil, "triage should be in origin snapshot")
        // to-prd is removed → not in origin
        #expect(originFiles["to-prd"] == nil, "to-prd should be absent from origin snapshot (removed)")
    }

    // MARK: — attention is true for the scenario

    /// attention is true for the scenario (≥1 Update available / Removed on origin).
    @Test @MainActor func fixtureModeAttentionIsTrue() async throws {
        let (model, _) = AppModel.fixtureMode()
        await model.start()

        guard let state = model.lastDerivedState else {
            Issue.record("lastDerivedState must be non-nil")
            return
        }
        #expect(state.attention == true,
                "scenario has Update available and Removed — attention must be true")
    }

    // MARK: — Path isolation

    /// Every directory the factory composes resolves under the ephemeral sandbox root and
    /// is not equal to the real ~/.claude/skills, real backups dir, or default cache root.
    @Test @MainActor func fixtureModePathIsolation() async throws {
        let (_, sandboxSkillsDir) = AppModel.fixtureMode()

        let realSkillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/skills", directoryHint: .isDirectory)
        let realCacheRoot = AppModel.makeDefaultCacheRoot()

        // The skills dir injected into the model must differ from the real one
        #expect(sandboxSkillsDir.path(percentEncoded: false) != realSkillsDir.path(percentEncoded: false),
                "sandbox skills dir must not equal real ~/.claude/skills")

        // The skills dir must be under a temp directory (ephemeral)
        let tmpDir = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        #expect(sandboxSkillsDir.path(percentEncoded: false).hasPrefix(tmpDir),
                "sandbox skills dir must be under NSTemporaryDirectory()")

        // The sandbox cache must not overlap with the real cache root
        let sandboxRoot = sandboxSkillsDir.deletingLastPathComponent()
        #expect(!sandboxRoot.path(percentEncoded: false).hasPrefix(realCacheRoot.path(percentEncoded: false)),
                "sandbox root must not overlap with real cache root")
    }

    // MARK: — FixtureMode.isActive detection

    /// FixtureMode.isActive computation matches the expected logic.
    @Test func fixtureModeIsActiveDetectionLogic() {
        // isActive is true iff "--fixtures" in ProcessInfo.arguments OR STEVE_FIXTURES=1 in env.
        let active = FixtureMode.isActive
        let argPresent = ProcessInfo.processInfo.arguments.contains("--fixtures")
        let envPresent = ProcessInfo.processInfo.environment["STEVE_FIXTURES"] == "1"
        #expect(active == (argPresent || envPresent),
                "FixtureMode.isActive must equal (--fixtures in args) || (STEVE_FIXTURES=1 in env)")
    }

    /// FixtureMode.isActive is false in normal test execution (no --fixtures arg or env var).
    @Test func fixtureModeIsActiveIsFalseByDefault() {
        let hasFixturesArg = ProcessInfo.processInfo.arguments.contains("--fixtures")
        let hasFixturesEnv = ProcessInfo.processInfo.environment["STEVE_FIXTURES"] == "1"
        if !hasFixturesArg && !hasFixturesEnv {
            #expect(FixtureMode.isActive == false,
                    "FixtureMode.isActive must be false when --fixtures arg and STEVE_FIXTURES=1 env are absent")
        }
    }

    // MARK: — Sandbox uses throwaway UserDefaults suite

    /// The sandbox uses a throwaway UserDefaults suite, never .standard.
    @Test @MainActor func fixtureModeUsesThrowawayUserDefaults() async throws {
        // Write a sentinel to .standard before creating the fixture model
        let key = "fixture-test-key-\(UUID().uuidString)"
        let sentinel = "fixture-test-sentinel-\(UUID().uuidString)"
        UserDefaults.standard.set(sentinel, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let (model, _) = AppModel.fixtureMode()
        await model.start()

        // The sentinel on .standard must still be present (fixture mode didn't clear it)
        #expect(UserDefaults.standard.string(forKey: key) == sentinel,
                "fixture mode must not write to or clear UserDefaults.standard")

        // The model must be functional (proves the pipeline ran)
        #expect(model.lastDerivedState != nil,
                "model must derive state through the fixture pipeline")
    }
}

// MARK: — MultiSkillTarball builder (non-test code, available in FixtureEngine)

@Suite("MultiSkillTarball builder")
struct MultiSkillTarballTests {

    /// The multi-skill tarball builder produces a valid tar.gz that TarballExtractor
    /// can parse into an OriginSnapshot with all skills and their files.
    @Test func multiSkillTarballBuilderProducesValidTarball() throws {
        let skills: [(name: String, files: [String: Data])] = [
            (name: "alpha", files: [
                "SKILL.md": Data("alpha skill content".utf8),
                "helper.md": Data("alpha helper".utf8)
            ]),
            (name: "beta", files: [
                "SKILL.md": Data("beta skill content".utf8)
            ])
        ]
        let tarData = try MultiSkillTarball.build(skills: skills)
        #expect(!tarData.isEmpty, "tarball must be non-empty")

        // Round-trip: TarballExtractor must recover the skills
        let extracted = try TarballExtractor.extractSkills(fromTarGz: tarData)
        let byName = Dictionary(uniqueKeysWithValues: extracted.map { ($0.name, $0) })

        #expect(byName["alpha"] != nil, "alpha must be in extracted skills")
        #expect(byName["beta"] != nil, "beta must be in extracted skills")
        #expect(byName["alpha"]?.files["SKILL.md"] == Data("alpha skill content".utf8))
        #expect(byName["alpha"]?.files["helper.md"] == Data("alpha helper".utf8))
        #expect(byName["beta"]?.files["SKILL.md"] == Data("beta skill content".utf8))
    }
}
