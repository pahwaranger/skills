import Testing
import Foundation
import Cache
import Installer

// MARK: — Test helpers

/// A clock whose "now" is fully injectable so retention math is deterministic.
struct FixedClock: InstallerClock {
    var now: Date
    init(now: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.now = now
    }
}

/// Build a tiny skill directory (one file) at `root/<name>/`.
private func makeSkillDir(at root: URL, name: String, content: String = "v1") throws {
    let dir = root.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(content.utf8).write(to: dir.appending(path: "SKILL.md"))
}

/// Read the sole SKILL.md from `root/<name>/SKILL.md`.
private func readSkill(at root: URL, name: String) throws -> String {
    let file = root.appending(path: "\(name)/SKILL.md")
    return try String(decoding: Data(contentsOf: file), as: UTF8.self)
}

// MARK: — AC: atomic swap leaves original intact on write failure

@Test func atomicSwapLeavesOriginalIntactOnFailure() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)

    // Seed the existing skill
    try makeSkillDir(at: skillsDir, name: "my-skill", content: "original")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))

    // The new files that should NOT land on disk
    let newFiles: [String: Data] = ["SKILL.md": Data("new-version".utf8)]

    // Simulate a failure during the rename by providing a write-error injector
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    // Inject a failure: the temp-write succeeds but rename throws
    let result = engine.install(
        skillName: "my-skill",
        files: newFiles,
        simulateSwapFailure: true
    )

    // The original content must still be present
    let content = try readSkill(at: skillsDir, name: "my-skill")
    #expect(content == "original")

    // The result must be a failure
    if case .success = result {
        Issue.record("Expected failure but got success")
    }
}

// MARK: — AC: Cache is NOT updated until atomic rename succeeds

@Test func cacheNotUpdatedWhenSwapFails() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try makeSkillDir(at: skillsDir, name: "my-skill", content: "original")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let newFiles: [String: Data] = ["SKILL.md": Data("new-version".utf8)]
    _ = engine.install(skillName: "my-skill", files: newFiles, simulateSwapFailure: true)

    // Cache mirror for "my-skill" must not exist
    let cachedNames = cache.cachedSkillNames()
    #expect(!cachedNames.contains("my-skill"))
}

// MARK: — AC: Cache IS updated after a successful swap

@Test func cacheUpdatedAfterSuccessfulSwap() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try makeSkillDir(at: skillsDir, name: "my-skill", content: "original")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let newFiles: [String: Data] = ["SKILL.md": Data("new-version".utf8)]
    let result = engine.install(skillName: "my-skill", files: newFiles, simulateSwapFailure: false)

    guard case .success = result else {
        Issue.record("Expected success")
        return
    }

    // Skills directory now holds the new version
    let content = try readSkill(at: skillsDir, name: "my-skill")
    #expect(content == "new-version")

    // Cache mirror for "my-skill" must exist and reflect new content
    let cachedNames = cache.cachedSkillNames()
    #expect(cachedNames.contains("my-skill"))
    let cachedFiles = try cache.skillFiles(named: "my-skill")
    #expect(cachedFiles["SKILL.md"] == Data("new-version".utf8))
}

// MARK: — AC: Backup is created in a timestamped subdirectory

@Test func backupCreatedInTimestampedSubdirectory() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try makeSkillDir(at: skillsDir, name: "alpha", content: "prior")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    // Use a fixed timestamp so backup dir name is deterministic
    let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let clock = FixedClock(now: fixedDate)
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let newFiles: [String: Data] = ["SKILL.md": Data("updated".utf8)]
    _ = engine.install(skillName: "alpha", files: newFiles, simulateSwapFailure: false)

    // backupsDir must have exactly one timestamp subdirectory
    let backupEntries = try FileManager.default.contentsOfDirectory(
        at: backupsDir, includingPropertiesForKeys: [.isDirectoryKey]
    )
    #expect(backupEntries.count == 1)

    // That timestamp dir must contain "alpha/"
    let timestampDir = backupEntries[0]
    let alphaBackup = timestampDir.appending(path: "alpha", directoryHint: .isDirectory)
    #expect(FileManager.default.fileExists(atPath: alphaBackup.path(percentEncoded: false)))

    // The backed-up SKILL.md must have the PRIOR content
    let backedUpContent = try String(decoding: Data(contentsOf: alphaBackup.appending(path: "SKILL.md")), as: UTF8.self)
    #expect(backedUpContent == "prior")
}

// MARK: — AC: bulk install — one failure does not prevent others

@Test func bulkInstallIsolatesPerSkillFailures() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)

    // Seed two skills
    try makeSkillDir(at: skillsDir, name: "good-skill", content: "old")
    try makeSkillDir(at: skillsDir, name: "bad-skill", content: "old")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let updates: [SkillUpdate] = [
        SkillUpdate(name: "good-skill", files: ["SKILL.md": Data("new".utf8)], simulateSwapFailure: false),
        SkillUpdate(name: "bad-skill", files: ["SKILL.md": Data("new".utf8)], simulateSwapFailure: true),
    ]

    let results = engine.installBatch(updates)

    // good-skill must have succeeded and be updated
    guard case .success = results["good-skill"] else {
        Issue.record("good-skill should have succeeded")
        return
    }
    let goodContent = try readSkill(at: skillsDir, name: "good-skill")
    #expect(goodContent == "new")

    // bad-skill must have failed
    guard case .failure = results["bad-skill"] else {
        Issue.record("bad-skill should have failed")
        return
    }

    // Cache updated for good-skill, not for bad-skill
    #expect(cache.cachedSkillNames().contains("good-skill"))
    #expect(!cache.cachedSkillNames().contains("bad-skill"))
}

// MARK: — AC: Removed-on-origin Update — deleted from skills dir, backed up, Cache records absence

@Test func removedOnOriginUpdateDeletesAndBacksUpAndUpdatesCache() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try makeSkillDir(at: skillsDir, name: "removed-skill", content: "prior")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    // Seed cache to say the skill was known
    let cache = CacheStore(root: cacheRoot)
    try cache.writeSkillFiles(named: "removed-skill", files: ["SKILL.md": Data("prior".utf8)])

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let result = engine.removeInstalled(skillName: "removed-skill")

    guard case .success = result else {
        Issue.record("Expected success from removeInstalled")
        return
    }

    // Skills directory must no longer contain the skill
    let skillPath = skillsDir.appending(path: "removed-skill")
    #expect(!FileManager.default.fileExists(atPath: skillPath.path(percentEncoded: false)))

    // A backup must exist
    let backupEntries = try FileManager.default.contentsOfDirectory(
        at: backupsDir, includingPropertiesForKeys: [.isDirectoryKey]
    )
    #expect(backupEntries.count == 1)
    let backupSkillDir = backupEntries[0].appending(path: "removed-skill")
    #expect(FileManager.default.fileExists(atPath: backupSkillDir.path(percentEncoded: false)))

    // Cache must no longer list the skill (records absence = no directory)
    #expect(!cache.cachedSkillNames().contains("removed-skill"))
}

// MARK: — AC: Removed-on-origin Skip — Cache records absence; skills directory untouched

@Test func removedOnOriginSkipUpdatesOnlyCacheAndLeavesSkillsDirIntact() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    // Skill is installed but user chose Skip
    try makeSkillDir(at: skillsDir, name: "skipped-skill", content: "installed")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)
    // Cache currently knows about this skill
    try cache.writeSkillFiles(named: "skipped-skill", files: ["SKILL.md": Data("installed".utf8)])

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let result = engine.skipRemoval(skillName: "skipped-skill")

    guard case .success = result else {
        Issue.record("Expected success from skipRemoval")
        return
    }

    // Skills directory must still have the skill
    let content = try readSkill(at: skillsDir, name: "skipped-skill")
    #expect(content == "installed")

    // No backup was created
    let backupExists = FileManager.default.fileExists(atPath: backupsDir.path(percentEncoded: false))
    if backupExists {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: nil
        )) ?? []
        #expect(entries.isEmpty)
    }

    // Cache records absence of the skill
    #expect(!cache.cachedSkillNames().contains("skipped-skill"))
}

// MARK: — AC: pruning removes backups older than 7 days, keeps newer ones

@Test func pruningRemovesOldBackupsAndKeepsRecent() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    // "now" is 2001-01-10
    let now = Date(timeIntervalSinceReferenceDate: 9 * 24 * 3600) // day 9
    let clock = FixedClock(now: now)
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    // Create backup dirs with timestamps: 1 day ago (keep), 8 days ago (prune)
    let formatter = ISO8601DateFormatter()
    let recentDate = Date(timeIntervalSinceReferenceDate: 8 * 24 * 3600)  // 1 day before now
    let oldDate = Date(timeIntervalSinceReferenceDate: 0)                  // 9 days before now

    let recentDirName = formatter.string(from: recentDate)
    let oldDirName = formatter.string(from: oldDate)

    let recentDir = backupsDir.appending(path: recentDirName, directoryHint: .isDirectory)
    let oldDir = backupsDir.appending(path: oldDirName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: recentDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)

    engine.pruneBackups()

    #expect(FileManager.default.fileExists(atPath: recentDir.path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(atPath: oldDir.path(percentEncoded: false)))
}

// MARK: — AC: pruning on exactly 7-day boundary (boundary condition)

@Test func pruningKeepsBackupAtExactlySevenDays() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let sevenDaysInSeconds: TimeInterval = 7 * 24 * 3600
    let now = Date(timeIntervalSinceReferenceDate: sevenDaysInSeconds)
    let clock = FixedClock(now: now)
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    // Backup that is exactly 7 days old must be kept (< strictly means older than)
    let formatter = ISO8601DateFormatter()
    let exactlySevenDays = Date(timeIntervalSinceReferenceDate: 0)
    let dirName = formatter.string(from: exactlySevenDays)
    let sevenDayDir = backupsDir.appending(path: dirName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sevenDayDir, withIntermediateDirectories: true)

    engine.pruneBackups()

    // 7 days exactly should be pruned (older than 7 days = age > 7 days; at 7 days exactly, prune)
    // The ADR says "retained for 7 days", meaning after 7 days they get pruned.
    // Age == 7 days → prune
    #expect(!FileManager.default.fileExists(atPath: sevenDayDir.path(percentEncoded: false)))
}

// MARK: — AC: pruneBackups runs after a successful batch install

@Test func pruneBackupsRunsAfterInstallBatch() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    try makeSkillDir(at: skillsDir, name: "skill-a", content: "old")

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let now = Date(timeIntervalSinceReferenceDate: 8 * 24 * 3600)
    let clock = FixedClock(now: now)
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    // Manually create a stale backup directory (9 days old relative to "now")
    let formatter = ISO8601DateFormatter()
    let staleDate = Date(timeIntervalSinceReferenceDate: 0)  // 8 days before now
    let staleDirName = formatter.string(from: staleDate)
    let staleDir = backupsDir.appending(path: staleDirName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: staleDir, withIntermediateDirectories: true)

    let updates: [SkillUpdate] = [
        SkillUpdate(name: "skill-a", files: ["SKILL.md": Data("new".utf8)], simulateSwapFailure: false),
    ]
    _ = engine.installBatch(updates)

    // stale backup must be pruned post-batch
    #expect(!FileManager.default.fileExists(atPath: staleDir.path(percentEncoded: false)))
}

// MARK: — Fresh install (no prior skill in skills dir)

@Test func installWithNoExistingSkillSucceeds() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appending(path: "installer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
    let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    // No pre-existing skill

    let cacheRoot = tmp.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cache = CacheStore(root: cacheRoot)

    let clock = FixedClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let engine = InstallEngine(
        skillsDirectory: skillsDir,
        backupsDirectory: backupsDir,
        cache: cache,
        clock: clock
    )

    let newFiles: [String: Data] = ["SKILL.md": Data("fresh".utf8)]
    let result = engine.install(skillName: "brand-new", files: newFiles, simulateSwapFailure: false)

    guard case .success = result else {
        Issue.record("Expected success for fresh install")
        return
    }

    let content = try readSkill(at: skillsDir, name: "brand-new")
    #expect(content == "fresh")

    // Cache updated
    #expect(cache.cachedSkillNames().contains("brand-new"))

    // No backup created (nothing to back up)
    let backupExists = FileManager.default.fileExists(atPath: backupsDir.path(percentEncoded: false))
    if backupExists {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: nil
        )) ?? []
        #expect(entries.isEmpty)
    }
}
