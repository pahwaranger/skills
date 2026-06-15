import Testing
import Foundation
import StateEngine
@testable import AppCore

// MARK: — ReviewSidebarModel: 3-state selection tests

/// Tests for the tri-state selection model in the Review window sidebar (Variant D).
/// The selection cycles: none → all actionable → new only (Update + Removed) → none.
struct ReviewSidebarSelectionModeTests {

    // MARK: — selectMode

    @Test func noSelectionsIsNoneMode() {
        let model = ReviewSidebarModel(skills: sampleSkills)
        // Default: nothing selected
        #expect(model.selectionMode == .none)
    }

    @Test func allActionableSelectedIsAllMode() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Select all actionable (removedOnOrigin + updateAvailable + skipped)
        model.selectedSkillNames = Set(sampleSkills
            .filter { $0.state != .upToDate }
            .map(\.name))
        #expect(model.selectionMode == .all)
    }

    @Test func onlyNewSelectedIsNewMode() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Select only update + removed (the "new" set)
        model.selectedSkillNames = Set(sampleSkills
            .filter { $0.state == .updateAvailable || $0.state == .removedOnOrigin }
            .map(\.name))
        #expect(model.selectionMode == .new)
    }

    @Test func partialSelectionIsPartialMode() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Select just one update-available skill (not all actionable)
        model.selectedSkillNames = ["bravo"]  // bravo is updateAvailable
        #expect(model.selectionMode == .partial)
    }

    @Test func upToDateOnlyYieldsNoneModeRegardlessOfSelection() {
        // When no skills are actionable, selecting nothing still yields .none
        let upToDateSkills = [
            ReviewSidebarModel.SkillEntry(name: "alpha", state: .upToDate),
        ]
        let model = ReviewSidebarModel(skills: upToDateSkills)
        #expect(model.selectionMode == .none)
    }

    @Test func emptySkillsYieldsNoneMode() {
        let model = ReviewSidebarModel(skills: [])
        #expect(model.selectionMode == .none)
    }

    // MARK: — cycleSelection

    @Test func cycleFromNoneSelectsAllActionable() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Start at none
        #expect(model.selectionMode == .none)
        model.cycleSelection()
        // Should now be .all (all actionable selected)
        #expect(model.selectionMode == .all)
        let actionableNames = Set(sampleSkills
            .filter { $0.state != .upToDate }
            .map(\.name))
        #expect(model.selectedSkillNames == actionableNames)
    }

    @Test func cycleFromAllSelectsNewOnly() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Move to .all first
        model.cycleSelection()
        #expect(model.selectionMode == .all)
        // Cycle again → new only
        model.cycleSelection()
        #expect(model.selectionMode == .new)
        let newOnlyNames = Set(sampleSkills
            .filter { $0.state == .updateAvailable || $0.state == .removedOnOrigin }
            .map(\.name))
        #expect(model.selectedSkillNames == newOnlyNames)
    }

    @Test func cycleFromNewDeselectsAll() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        model.cycleSelection() // → all
        model.cycleSelection() // → new
        #expect(model.selectionMode == .new)
        model.cycleSelection() // → none
        #expect(model.selectionMode == .none)
        #expect(model.selectedSkillNames.isEmpty)
    }

    @Test func cycleFromPartialSelectsAllActionable() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        // Partial: one selected
        model.selectedSkillNames = ["bravo"]
        #expect(model.selectionMode == .partial)
        model.cycleSelection()
        #expect(model.selectionMode == .all)
    }

    // MARK: — toggleSkill

    @Test func toggleUncheckedSkillChecksIt() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        #expect(!model.selectedSkillNames.contains("bravo"))
        model.toggleSkill("bravo")
        #expect(model.selectedSkillNames.contains("bravo"))
    }

    @Test func toggleCheckedSkillUnchecksIt() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        model.selectedSkillNames = ["bravo"]
        model.toggleSkill("bravo")
        #expect(!model.selectedSkillNames.contains("bravo"))
    }

    // MARK: — selectedCount

    @Test func selectedCountMatchesCheckedActionableSkills() {
        var model = ReviewSidebarModel(skills: sampleSkills)
        model.selectedSkillNames = ["bravo", "charlie"]
        // Both are actionable; upToDate would not count but isn't included here
        #expect(model.selectedCount == 2)
    }

    @Test func selectedCountIsZeroByDefault() {
        let model = ReviewSidebarModel(skills: sampleSkills)
        #expect(model.selectedCount == 0)
    }
}

// MARK: — ReviewSidebarModel: grouping / ordering tests

struct ReviewSidebarGroupingTests {

    /// Variant D section order: REMOVED ON ORIGIN → UPDATE AVAILABLE → SKIPPED → UP TO DATE
    /// Skills within each group are alpha-sorted.
    @Test func groupsSkillsInCorrectOrderWithAlphaSort() {
        let skills: [ReviewSidebarModel.SkillEntry] = [
            .init(name: "zebra",   state: .upToDate),
            .init(name: "alpha",   state: .upToDate),
            .init(name: "bravo",   state: .skipped),
            .init(name: "charlie", state: .updateAvailable),
            .init(name: "delta",   state: .removedOnOrigin),
        ]
        let model = ReviewSidebarModel(skills: skills)
        let sections = model.sections

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

    @Test func emptyGroupsAreOmitted() {
        let skills: [ReviewSidebarModel.SkillEntry] = [
            .init(name: "alpha", state: .updateAvailable),
            .init(name: "beta",  state: .removedOnOrigin),
        ]
        let model = ReviewSidebarModel(skills: skills)
        let sections = model.sections
        #expect(sections.count == 2)
        #expect(sections.map(\.state) == [.removedOnOrigin, .updateAvailable])
    }

    @Test func buildFromDerivedState() {
        let derived = DerivedState(
            states: [
                "zebra":   .upToDate,
                "charlie": .updateAvailable,
                "delta":   .removedOnOrigin,
                "bravo":   .skipped,
            ],
            attention: true,
            selfHealed: []
        )
        let model = ReviewSidebarModel(from: derived)
        let sections = model.sections
        #expect(sections.count == 4)
        #expect(sections[0].state == .removedOnOrigin)
        #expect(sections[0].skills == ["delta"])
        #expect(sections[1].state == .updateAvailable)
        #expect(sections[1].skills == ["charlie"])
        #expect(sections[2].state == .skipped)
        #expect(sections[2].skills == ["bravo"])
        #expect(sections[3].state == .upToDate)
        #expect(sections[3].skills == ["zebra"])
    }

    @Test func sectionLabelMatchesVariantD() {
        // Variant D sidebar labels are short strings (Removed / Updates / Skipped / Up to date)
        #expect(ReviewSidebarModel.label(for: .removedOnOrigin) == "Removed")
        #expect(ReviewSidebarModel.label(for: .updateAvailable) == "Updates")
        #expect(ReviewSidebarModel.label(for: .skipped)         == "Skipped")
        #expect(ReviewSidebarModel.label(for: .upToDate)        == "Up to date")
    }

    @Test func allUpToDateProducesOneSectionAlphaSorted() {
        let skills: [ReviewSidebarModel.SkillEntry] = [
            .init(name: "zebra", state: .upToDate),
            .init(name: "alpha", state: .upToDate),
            .init(name: "mango", state: .upToDate),
        ]
        let model = ReviewSidebarModel(skills: skills)
        let sections = model.sections
        #expect(sections.count == 1)
        #expect(sections[0].state == .upToDate)
        #expect(sections[0].skills == ["alpha", "mango", "zebra"])
    }

    @Test func emptySkillsProducesNoSections() {
        let model = ReviewSidebarModel(skills: [])
        #expect(model.sections.isEmpty)
    }
}

// MARK: — Helpers

/// Shared sample skills for selection tests:
/// - "alpha": removedOnOrigin   (actionable)
/// - "bravo": updateAvailable   (actionable, "new")
/// - "charlie": skipped         (actionable, NOT "new")
/// - "delta": upToDate          (non-actionable)
private let sampleSkills: [ReviewSidebarModel.SkillEntry] = [
    .init(name: "alpha",   state: .removedOnOrigin),
    .init(name: "bravo",   state: .updateAvailable),
    .init(name: "charlie", state: .skipped),
    .init(name: "delta",   state: .upToDate),
]
