import Testing
import Foundation
import StateEngine
@testable import AppCore

// MARK: — StatusLine wording tests

/// Each test exercises one of the 8 documented status-line wordings from #15.
/// Inputs are the same observable properties AppModel exposes; the logic is pure.
struct StatusLineWordingTests {

    // 1. Checking
    @Test func checkingInFlightShowsCheckingOrigin() {
        let wording = StatusLine.wording(
            isChecking: true,
            derivedState: nil,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "Checking origin…")
    }

    // 2. Pending changes (updates + removed + skipped — omit zero segments)
    @Test func pendingChangesShowsCountsOmittingZeroSegments() {
        let state = DerivedState(
            states: [
                "alpha": .updateAvailable,
                "beta":  .updateAvailable,
                "gamma": .removedOnOrigin,
                "delta": .skipped,
            ],
            attention: true,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "2 updates available · 1 removed · 1 skipped")
    }

    @Test func pendingChangesOmitsZeroUpdateSegment() {
        // Only removed — no updates, no skipped
        let state = DerivedState(
            states: ["alpha": .removedOnOrigin],
            attention: true,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "1 removed")
    }

    @Test func pendingChangesOmitsZeroSkippedSegment() {
        // 3 updates, 0 removed, 0 skipped
        let state = DerivedState(
            states: [
                "a": .updateAvailable,
                "b": .updateAvailable,
                "c": .updateAvailable,
            ],
            attention: true,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "3 updates available")
    }

    // 3. Up to date with some skipped
    @Test func upToDateWithSkippedShowsSkippedCount() {
        let state = DerivedState(
            states: [
                "alpha": .upToDate,
                "beta":  .upToDate,
                "gamma": .skipped,
            ],
            attention: false,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "Up to date · 1 skipped")
    }

    // 4. Fully clean — up to date, no skipped
    @Test func fullyCleanShowsCheckedTime() {
        let date = Date(timeIntervalSinceNow: -90) // 1.5 minutes ago
        let state = DerivedState(
            states: ["alpha": .upToDate],
            attention: false,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: date
        )
        // Should contain "Up to date · checked" and a relative time
        #expect(wording.hasPrefix("Up to date · checked"))
    }

    @Test func fullyCleanWithNoLastCheckDateShowsJustUpToDate() {
        let state = DerivedState(
            states: ["alpha": .upToDate],
            attention: false,
            selfHealed: []
        )
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: state,
            lastError: nil,
            lastCheckDate: nil
        )
        #expect(wording == "Up to date")
    }

    // 5. Network/timeout/5xx error
    @Test func networkErrorShowsCantReachOrigin() {
        let date = Date(timeIntervalSinceNow: -7200) // 2h ago
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: nil,
            lastError: .networkError,
            lastCheckDate: date
        )
        #expect(wording.hasPrefix("Couldn't reach origin · checked"))
    }

    // 6. GitHub rate limit — shows retry countdown
    @Test func rateLimitedShowsRetryTime() {
        let resetDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: nil,
            lastError: .rateLimited(resetAt: resetDate),
            lastCheckDate: nil
        )
        #expect(wording.hasPrefix("GitHub rate limit reached · retries"))
    }

    // 7. Origin not found (404/private)
    @Test func originNotFoundShowsCheckRepo() {
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: nil,
            lastError: .originNotFound,
            lastCheckDate: nil
        )
        #expect(wording == "Origin not found — check repo")
    }

    // 8. Tarball corrupt / fetch failed
    @Test func fetchFailedShowsOriginFetchFailed() {
        let date = Date(timeIntervalSinceNow: -3600) // 1h ago
        let wording = StatusLine.wording(
            isChecking: false,
            derivedState: nil,
            lastError: .fetchFailed,
            lastCheckDate: date
        )
        #expect(wording.hasPrefix("Origin fetch failed · checked"))
    }
}

// MARK: — StatusLine banner-type tests

/// The banner type drives the tint colour in Variant B (red "!" for attention,
/// neutral for checking/clean).
struct StatusLineBannerTypeTests {

    @Test func pendingChangesYieldAttentionBanner() {
        let state = DerivedState(
            states: ["alpha": .updateAvailable],
            attention: true,
            selfHealed: []
        )
        let banner = StatusLine.bannerType(
            isChecking: false,
            derivedState: state,
            lastError: nil
        )
        #expect(banner == .attention)
    }

    @Test func checkingYieldsCheckingBanner() {
        let banner = StatusLine.bannerType(
            isChecking: true,
            derivedState: nil,
            lastError: nil
        )
        #expect(banner == .checking)
    }

    @Test func cleanYieldsNeutralBanner() {
        let state = DerivedState(
            states: ["alpha": .upToDate],
            attention: false,
            selfHealed: []
        )
        let banner = StatusLine.bannerType(
            isChecking: false,
            derivedState: state,
            lastError: nil
        )
        #expect(banner == .neutral)
    }

    @Test func errorYieldsErrorBanner() {
        let banner = StatusLine.bannerType(
            isChecking: false,
            derivedState: nil,
            lastError: .networkError
        )
        #expect(banner == .error)
    }
}

// MARK: — DropdownSection grouping/sorting tests

struct DropdownSectionTests {

    /// The full ordering is: removedOnOrigin → updateAvailable → skipped → upToDate
    /// Skills within each group are alpha-sorted.
    @Test func groupsAndSortsAllFourStates() {
        let state = DerivedState(
            states: [
                "zebra":  .upToDate,
                "alpha":  .upToDate,
                "bravo":  .skipped,
                "charlie": .updateAvailable,
                "delta":  .removedOnOrigin,
            ],
            attention: true,
            selfHealed: []
        )
        let sections = DropdownSections.build(from: state)
        #expect(sections.count == 4)
        #expect(sections[0].state == .removedOnOrigin)
        #expect(sections[0].skills == ["delta"])
        #expect(sections[1].state == .updateAvailable)
        #expect(sections[1].skills == ["charlie"])
        #expect(sections[2].state == .skipped)
        #expect(sections[2].skills == ["bravo"])
        #expect(sections[3].state == .upToDate)
        #expect(sections[3].skills == ["alpha", "zebra"])
    }

    @Test func emptyStatesProducesNoSections() {
        let state = DerivedState(states: [:], attention: false, selfHealed: [])
        let sections = DropdownSections.build(from: state)
        #expect(sections.isEmpty)
    }

    @Test func onlyUpToDateProducesOneSectionAlphaSorted() {
        let state = DerivedState(
            states: ["zebra": .upToDate, "alpha": .upToDate, "mango": .upToDate],
            attention: false,
            selfHealed: []
        )
        let sections = DropdownSections.build(from: state)
        #expect(sections.count == 1)
        #expect(sections[0].state == .upToDate)
        #expect(sections[0].skills == ["alpha", "mango", "zebra"])
    }

    @Test func sectionLabelMatchesVariantB() {
        // Variant B prototype uses: REMOVED ON ORIGIN / UPDATE AVAILABLE / SKIPPED / UP TO DATE
        #expect(DropdownSections.label(for: .removedOnOrigin) == "REMOVED ON ORIGIN")
        #expect(DropdownSections.label(for: .updateAvailable) == "UPDATE AVAILABLE")
        #expect(DropdownSections.label(for: .skipped)         == "SKIPPED")
        #expect(DropdownSections.label(for: .upToDate)        == "UP TO DATE")
    }

    @Test func omitsGroupsWithNoSkills() {
        // Only two states present — skipped and upToDate groups should be absent
        let state = DerivedState(
            states: ["alpha": .updateAvailable, "beta": .removedOnOrigin],
            attention: true,
            selfHealed: []
        )
        let sections = DropdownSections.build(from: state)
        #expect(sections.count == 2)
        #expect(sections.map(\.state) == [.removedOnOrigin, .updateAvailable])
    }
}
