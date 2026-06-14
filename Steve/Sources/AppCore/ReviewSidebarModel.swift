import Foundation
#if SWIFT_PACKAGE
import StateEngine
#endif

/// Pure, testable model for the Review window sidebar (Slice 8, Variant D).
///
/// Owns:
/// - The grouped+sorted skill sections shown in the scrollable list.
/// - The tri-state selection model (none / all / new / partial) and its cycle
///   behaviour as documented in `prototypes/review-diff/NOTES.md`.
/// - Per-skill toggle and selected-count helpers.
///
/// The SwiftUI sidebar view binds to `selectedSkillNames` (and calls the
/// mutation helpers) but holds no selection logic itself.
public struct ReviewSidebarModel: Equatable, Sendable {

    // MARK: — Types

    /// A single skill entry, carrying only what the sidebar needs.
    public struct SkillEntry: Equatable, Sendable {
        public let name: SkillName
        public let state: SkillState

        public init(name: SkillName, state: SkillState) {
            self.name = name
            self.state = state
        }
    }

    /// One ordered section in the sidebar skill list.
    public struct Section: Equatable, Sendable {
        public let state: SkillState
        /// Skill names in this section, alpha-sorted.
        public let skills: [SkillName]

        public init(state: SkillState, skills: [SkillName]) {
            self.state = state
            self.skills = skills
        }
    }

    /// The tri-state of the header select-toggle:
    /// - `.none`    — nothing selected (☐)
    /// - `.all`     — all actionable selected (☑)
    /// - `.new`     — update + removed selected, skipped excluded (⊟)
    /// - `.partial` — some but not a recognised set: cycling from here treats as `.none → .all`
    public enum SelectionMode: Equatable, Sendable {
        case none
        case all
        case new
        case partial
    }

    // MARK: — State

    /// All skills managed by this sidebar instance.
    private let skills: [SkillEntry]

    /// The set of currently selected skill names.
    /// Only actionable (non–up-to-date) skills are meaningful here; up-to-date
    /// skills may not appear in the set from the view, but this model does not
    /// enforce that — it simply does not count them toward `selectedCount`.
    public var selectedSkillNames: Set<SkillName> = []

    // MARK: — Init

    public init(skills: [SkillEntry]) {
        self.skills = skills
    }

    /// Convenience initialiser: builds entries from a `DerivedState`.
    public init(from derivedState: DerivedState) {
        self.skills = derivedState.states.map { name, state in
            SkillEntry(name: name, state: state)
        }
    }

    // MARK: — Computed: grouping

    /// Section order matches the prototype: REMOVED → UPDATE → SKIPPED → UP TO DATE.
    private static let sectionOrder: [SkillState] = [
        .removedOnOrigin,
        .updateAvailable,
        .skipped,
        .upToDate,
    ]

    /// Ordered, non-empty sections for the sidebar skill list. Skills within each
    /// section are alpha-sorted by name.
    public var sections: [Section] {
        var buckets: [SkillState: [SkillName]] = [:]
        for entry in skills {
            buckets[entry.state, default: []].append(entry.name)
        }
        return Self.sectionOrder.compactMap { state -> Section? in
            guard let names = buckets[state], !names.isEmpty else { return nil }
            return Section(state: state, skills: names.sorted())
        }
    }

    /// Title-cased section label for Variant D sidebar (distinct from the ALL-CAPS
    /// labels used in the Variant B dropdown).
    public static func label(for state: SkillState) -> String {
        switch state {
        case .removedOnOrigin: return "Removed on Origin"
        case .updateAvailable: return "Update Available"
        case .skipped:         return "Skipped"
        case .upToDate:        return "Up to Date"
        }
    }

    // MARK: — Computed: selection

    /// All skills that can be selected (i.e. non–up-to-date).
    private var actionableSkills: [SkillEntry] {
        skills.filter { $0.state != .upToDate }
    }

    /// Skills in the "new" subset: Update available + Removed on origin.
    /// Excludes Skipped (which is already acknowledged by the user).
    private var newSkills: [SkillEntry] {
        skills.filter { $0.state == .updateAvailable || $0.state == .removedOnOrigin }
    }

    /// The current tri-state of the header select-toggle, derived from `selectedSkillNames`.
    ///
    /// Cycle doc (from NOTES.md):
    ///   ☐ none → ☑ all → ⊟ new-only → ☐ none → …
    public var selectionMode: SelectionMode {
        let actionable = actionableSkills
        guard !actionable.isEmpty else { return .none }

        let checkedActionableCount = actionable.filter { selectedSkillNames.contains($0.name) }.count
        guard checkedActionableCount > 0 else { return .none }

        if checkedActionableCount == actionable.count { return .all }

        // .new: exactly the new-only set is selected (Update + Removed, no Skipped)
        let newSet = Set(newSkills.map(\.name))
        if selectedSkillNames == newSet { return .new }

        return .partial
    }

    /// Number of currently selected actionable skills. Drives "Update N" / "Skip N".
    public var selectedCount: Int {
        actionableSkills.filter { selectedSkillNames.contains($0.name) }.count
    }

    // MARK: — Mutations

    /// Cycles the selection through the tri-state sequence:
    ///   none / partial → all actionable
    ///   all            → new only (Update + Removed, excludes Skipped)
    ///   new            → none (deselect all)
    public mutating func cycleSelection() {
        switch selectionMode {
        case .none, .partial:
            selectedSkillNames = Set(actionableSkills.map(\.name))
        case .all:
            selectedSkillNames = Set(newSkills.map(\.name))
        case .new:
            selectedSkillNames = []
        }
    }

    /// Toggles the checked state of a single skill by name.
    public mutating func toggleSkill(_ name: SkillName) {
        if selectedSkillNames.contains(name) {
            selectedSkillNames.remove(name)
        } else {
            selectedSkillNames.insert(name)
        }
    }
}
