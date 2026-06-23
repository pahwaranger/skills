import Foundation
#if SWIFT_PACKAGE
import StateEngine
#endif

/// A value describing the canonical six-skill fixture roster for Steve's fixture mode.
///
/// Each entry describes one managed skill:
/// - `name`: the skill directory name
/// - `targetState`: the `SkillState` the seeding recipe aims to produce
/// - `installedFiles`: the file tree written into the sandbox skills directory (S)
/// - `cacheFiles`: the file tree written into the sandbox cache (C)
/// - `originFiles`: the file tree served from the fixture origin tarball (O)
///   (`nil` = skill is absent from origin, producing `removedOnOrigin`)
///
/// ## Seeding recipes (per ADR 0006 derivation rules)
/// - **Up-to-date** (`S == O`): installedFiles == originFiles; cacheFiles can be anything
///   (self-heal sets C <- O). Use the same files for all three.
/// - **Update available** (`O != C and S != O`): installedFiles and cacheFiles hold an old
///   version; originFiles holds the new version.
/// - **Skipped** (`C == O and S != O`): cacheFiles == originFiles; installedFiles differ.
/// - **Removed on origin**: originFiles == nil; installedFiles and cacheFiles non-nil.
public struct FixtureSkillEntry: Sendable {
    public let name: String
    public let targetState: SkillState
    /// Files to write into the sandbox skills directory (S).
    public let installedFiles: [String: Data]
    /// Files to write into the sandbox cache (C).
    public let cacheFiles: [String: Data]
    /// Files to serve from the fixture origin tarball (O).
    /// `nil` means the skill is absent from origin -> `removedOnOrigin`.
    public let originFiles: [String: Data]?

    public init(
        name: String,
        targetState: SkillState,
        installedFiles: [String: Data],
        cacheFiles: [String: Data],
        originFiles: [String: Data]?
    ) {
        self.name = name
        self.targetState = targetState
        self.installedFiles = installedFiles
        self.cacheFiles = cacheFiles
        self.originFiles = originFiles
    }
}

/// The full fixture scenario: a named roster of `FixtureSkillEntry` values.
public struct FixtureScenario: Sendable {
    public let skills: [FixtureSkillEntry]

    public init(skills: [FixtureSkillEntry]) {
        self.skills = skills
    }

    /// The canonical six-skill default scenario (spec from issue #71):
    ///
    /// - `to-prd`    -> **Removed on origin**
    /// - `diagnose`  -> **Update available** (multi-file diff)
    /// - `tdd`       -> **Update available** (single file)
    /// - `verify`    -> **Skipped** (C == O, S != O)
    /// - `handoff`   -> **Up-to-date** (S == O)
    /// - `triage`    -> **Up-to-date** (S == O)
    public static let `default` = FixtureScenario(skills: [

        // --- to-prd: Removed on origin ---
        // O = nil (absent); C != nil, S != nil  ->  removedOnOrigin
        FixtureSkillEntry(
            name: "to-prd",
            targetState: .removedOnOrigin,
            installedFiles: ["SKILL.md": Data("# to-prd\nInstalled version.".utf8)],
            cacheFiles:     ["SKILL.md": Data("# to-prd\nInstalled version.".utf8)],
            originFiles:    nil
        ),

        // --- diagnose: Update available (multi-file diff) ---
        // O != C (origin has new SKILL.md + new reference.md, dropped legacy.md)
        // S holds the old installed version (differs from O)
        FixtureSkillEntry(
            name: "diagnose",
            targetState: .updateAvailable,
            installedFiles: [
                "SKILL.md":  Data("# diagnose\nOld installed SKILL.md.".utf8),
                "legacy.md": Data("# legacy content".utf8)
            ],
            cacheFiles: [
                "SKILL.md":  Data("# diagnose\nOld cached SKILL.md.".utf8),
                "legacy.md": Data("# legacy content".utf8)
            ],
            originFiles: [
                "SKILL.md":     Data("# diagnose\nNew SKILL.md on origin.".utf8),
                "reference.md": Data("# reference\nAdded on origin.".utf8)
                // legacy.md is absent -> deleted on origin
            ]
        ),

        // --- tdd: Update available (single modified file) ---
        // O != C != S (origin has newer SKILL.md than cache and installed)
        FixtureSkillEntry(
            name: "tdd",
            targetState: .updateAvailable,
            installedFiles: ["SKILL.md": Data("# tdd\nInstalled v1.".utf8)],
            cacheFiles:     ["SKILL.md": Data("# tdd\nCached v1.".utf8)],
            originFiles:    ["SKILL.md": Data("# tdd\nOrigin v2 - update available.".utf8)]
        ),

        // --- verify: Skipped (C == O, S != O) ---
        // The user previously acknowledged this origin version (C <- O via Skip),
        // but hasn't installed it (S holds the old version).
        FixtureSkillEntry(
            name: "verify",
            targetState: .skipped,
            installedFiles: ["SKILL.md": Data("# verify\nOld installed version.".utf8)],
            cacheFiles:     ["SKILL.md": Data("# verify\nAcknowledged origin version.".utf8)],
            originFiles:    ["SKILL.md": Data("# verify\nAcknowledged origin version.".utf8)]
            // cacheFiles == originFiles -> C == O -> skipped
        ),

        // --- handoff: Up-to-date (S == O) ---
        FixtureSkillEntry(
            name: "handoff",
            targetState: .upToDate,
            installedFiles: ["SKILL.md": Data("# handoff\nCurrent version.".utf8)],
            cacheFiles:     ["SKILL.md": Data("# handoff\nCurrent version.".utf8)],
            originFiles:    ["SKILL.md": Data("# handoff\nCurrent version.".utf8)]
            // S == O -> upToDate
        ),

        // --- triage: Up-to-date (S == O) ---
        FixtureSkillEntry(
            name: "triage",
            targetState: .upToDate,
            installedFiles: ["SKILL.md": Data("# triage\nCurrent version.".utf8)],
            cacheFiles:     ["SKILL.md": Data("# triage\nCurrent version.".utf8)],
            originFiles:    ["SKILL.md": Data("# triage\nCurrent version.".utf8)]
            // S == O -> upToDate
        ),
    ])
}
