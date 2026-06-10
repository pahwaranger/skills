import Testing
import StateEngine

struct StateEngineTests {
    // MARK: — Up-to-date

    @Test func installedMatchingOriginIsUpToDate() {
        let result = StateEngine.derive(
            skills: ["alpha": "v1"],
            cache: ["alpha": "v1"],
            origin: ["alpha": "v1"]
        )
        #expect(result.states["alpha"] == .upToDate)
        #expect(result.attention == false)
    }

    // MARK: — Update available

    @Test func originMovedAndNotInstalledIsUpdateAvailable() {
        let result = StateEngine.derive(
            skills: ["alpha": "v1"],
            cache: ["alpha": "v1"],
            origin: ["alpha": "v2"]
        )
        #expect(result.states["alpha"] == .updateAvailable)
        #expect(result.attention == true)
    }

    // MARK: — Skipped

    @Test func acknowledgedOriginNotInstalledIsSkipped() {
        let result = StateEngine.derive(
            skills: ["alpha": "v1"],
            cache: ["alpha": "v2"],
            origin: ["alpha": "v2"]
        )
        #expect(result.states["alpha"] == .skipped)
        #expect(result.attention == false)
    }

    // MARK: — Removed on origin

    @Test func cachedSkillAbsentFromOriginIsRemoved() {
        let result = StateEngine.derive(
            skills: ["alpha": "v1"],
            cache: ["alpha": "v1"],
            origin: [:]
        )
        #expect(result.states["alpha"] == .removedOnOrigin)
        #expect(result.attention == true)
    }

    // MARK: — Self-heal

    @Test func installedMatchingOriginWithStaleCacheSelfHeals() {
        // Hand-synced before Steve existed: S == O, but C is stale (or absent).
        let result = StateEngine.derive(
            skills: ["alpha": "v2"],
            cache: ["alpha": "v1"],
            origin: ["alpha": "v2"]
        )
        #expect(result.states["alpha"] == .upToDate)
        #expect(result.selfHealed.contains("alpha"))
        #expect(result.attention == false)
    }

    // MARK: — Foreign skill pass-through

    @Test func foreignSkillNeverCachedNorOnOriginIsIgnored() {
        let result = StateEngine.derive(
            skills: ["foreign": "x", "alpha": "v1"],
            cache: ["alpha": "v1"],
            origin: ["alpha": "v1"]
        )
        #expect(result.states["foreign"] == nil)
        #expect(result.states.keys.contains("foreign") == false)
        #expect(result.attention == false)
    }

    // MARK: — Fresh device (empty cache)

    @Test func freshDeviceDerivesWithoutBaselineStep() {
        let result = StateEngine.derive(
            skills: ["matching": "v1", "divergent": "old"],
            cache: [:],
            origin: ["matching": "v1", "divergent": "v2"]
        )
        // Already-matching skill goes green via self-heal — no onboarding step.
        #expect(result.states["matching"] == .upToDate)
        #expect(result.selfHealed.contains("matching"))
        // Everything else surfaces as Update available.
        #expect(result.states["divergent"] == .updateAvailable)
        #expect(result.attention == true)
    }

    // MARK: — Not-yet-installed skill

    @Test func originSkillNotYetInstalledIsUpdateAvailable() {
        let result = StateEngine.derive(
            skills: [:],
            cache: [:],
            origin: ["alpha": "v1"]
        )
        #expect(result.states["alpha"] == .updateAvailable)
        #expect(result.attention == true)
    }
}
