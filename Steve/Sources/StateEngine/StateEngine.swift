import Foundation

public typealias SkillName = String
public typealias ContentHash = String

/// The sync state of a managed skill, derived from the three content inputs
/// S (skills directory), C (cache), O (origin).
public enum SkillState: Equatable, Sendable {
    case upToDate
    case updateAvailable
    case skipped
    case removedOnOrigin
}

/// The result of a derivation pass over all managed skills.
public struct DerivedState: Equatable, Sendable {
    /// State of every managed skill, keyed by name. Foreign skills are excluded.
    public let states: [SkillName: SkillState]
    /// True iff at least one managed skill has effective-C ≠ O (drives the red icon).
    public let attention: Bool
    /// Skills where S == O but C was stale: the caller should set C ← O.
    public let selfHealed: Set<SkillName>

    public init(states: [SkillName: SkillState], attention: Bool, selfHealed: Set<SkillName>) {
        self.states = states
        self.attention = attention
        self.selfHealed = selfHealed
    }
}

public enum StateEngine {
    /// Derives the sync state of every managed skill from pre-computed content
    /// hashes. Pure: no filesystem, no network. Presence of a name in a map means
    /// the content exists in that location; absence means it does not.
    public static func derive(
        skills: [SkillName: ContentHash],
        cache: [SkillName: ContentHash],
        origin: [SkillName: ContentHash]
    ) -> DerivedState {
        var states: [SkillName: SkillState] = [:]
        var attention = false
        var selfHealed: Set<SkillName> = []
        let names = Set(origin.keys).union(cache.keys).union(skills.keys)
        for name in names {
            let o = origin[name]
            let c = cache[name]
            let s = skills[name]

            // Foreign skill: present only in the skills directory, never on
            // origin or cached. The app's universe is Origin ∪ Cached — ignore it.
            if o == nil, c == nil { continue }

            if o != nil, s == o {
                // Up-to-date. Self-heal a stale cache (C ← O) so a hand-synced
                // skill lands green with no baseline/onboarding step.
                states[name] = .upToDate
                if c != o { selfHealed.insert(name) }
            } else if o == nil {
                // Cached/installed but gone from origin.
                states[name] = .removedOnOrigin
                attention = true
            } else if c == o {
                // Origin change was acknowledged (C == O) but not installed.
                states[name] = .skipped
            } else {
                // Origin moved since last seen (O ≠ C) and is not installed.
                states[name] = .updateAvailable
                attention = true
            }
        }
        return DerivedState(states: states, attention: attention, selfHealed: selfHealed)
    }
}
