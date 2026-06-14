import Foundation
#if SWIFT_PACKAGE
import StateEngine
#endif

/// One ordered section in the Variant B dropdown skill list.
public struct DropdownSection: Equatable, Sendable {
    /// The skill state that all entries in this section share.
    public let state: SkillState
    /// Skill names in this section, sorted alphabetically.
    public let skills: [SkillName]

    public init(state: SkillState, skills: [SkillName]) {
        self.state = state
        self.skills = skills
    }
}

/// Builds and labels the ordered sections shown in the Variant B skill list.
///
/// Section order: removedOnOrigin → updateAvailable → skipped → upToDate
/// (same order as the prototype's `STATE_ORDER`).
/// Empty groups are omitted.
public enum DropdownSections {

    /// The display order of states (matches Variant B prototype's `STATE_ORDER`).
    static let stateOrder: [SkillState] = [
        .removedOnOrigin,
        .updateAvailable,
        .skipped,
        .upToDate,
    ]

    /// Builds an ordered array of non-empty `DropdownSection`s from a `DerivedState`.
    public static func build(from derivedState: DerivedState) -> [DropdownSection] {
        var buckets: [SkillState: [SkillName]] = [:]
        for (name, state) in derivedState.states {
            buckets[state, default: []].append(name)
        }
        return stateOrder.compactMap { state -> DropdownSection? in
            guard let names = buckets[state], !names.isEmpty else { return nil }
            return DropdownSection(state: state, skills: names.sorted())
        }
    }

    /// The uppercase section label shown in Variant B (e.g. "UPDATE AVAILABLE").
    public static func label(for state: SkillState) -> String {
        switch state {
        case .removedOnOrigin: return "REMOVED ON ORIGIN"
        case .updateAvailable: return "UPDATE AVAILABLE"
        case .skipped:         return "SKIPPED"
        case .upToDate:        return "UP TO DATE"
        }
    }
}
