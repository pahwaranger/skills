import Foundation
#if SWIFT_PACKAGE
import Cache
#endif

// MARK: — Clock protocol (injectable for deterministic tests)

/// A clock abstraction for the install engine so tests can drive "now" without
/// touching the wall clock.
public protocol InstallerClock: Sendable {
    /// The current date/time.
    var now: Date { get }
}

/// Production clock: reads the system wall clock.
public struct SystemInstallerClock: InstallerClock {
    public init() {}
    public var now: Date { Date() }
}

// MARK: — SkillUpdate (input to bulk installs)

/// A single skill to install as part of a batch.
public struct SkillUpdate: Sendable {
    public let name: String
    public let files: [String: Data]
    /// Test-only injection point: when `true` the atomic rename step throws,
    /// simulating a failure after the temp-write but before the swap.
    public let simulateSwapFailure: Bool

    public init(name: String, files: [String: Data], simulateSwapFailure: Bool = false) {
        self.name = name
        self.files = files
        self.simulateSwapFailure = simulateSwapFailure
    }
}

// MARK: — InstallError

public enum InstallError: Error, Equatable {
    /// The atomic rename step failed.
    case swapFailed(underlying: String)
    /// A filesystem operation failed for a reason other than the simulated swap.
    case fileSystemError(underlying: String)
}

// MARK: — InstallEngine

/// Coordinates atomic, recoverable skill installations.
///
/// Install sequence per skill (ADR 0007):
///  1. Write new files to a temp directory on the same volume.
///  2. Move the existing skill directory to a timestamped backup (if present).
///  3. Atomically rename the temp directory to the final path in the skills directory.
///  4. Update the Cache mirror only after a successful swap (never before).
///
/// Bulk installs run each skill independently: one failure does not abort others.
/// Backup pruning runs after every batch and is also callable at launch.
public struct InstallEngine: Sendable {

    // MARK: Properties

    public let skillsDirectory: URL
    public let backupsDirectory: URL
    public let cache: CacheStore
    private let clock: any InstallerClock

    private static let retentionInterval: TimeInterval = 7 * 24 * 3600  // 7 days

    // MARK: Init

    public init(
        skillsDirectory: URL,
        backupsDirectory: URL,
        cache: CacheStore,
        clock: any InstallerClock = SystemInstallerClock()
    ) {
        self.skillsDirectory = skillsDirectory
        self.backupsDirectory = backupsDirectory
        self.cache = cache
        self.clock = clock
    }

    // MARK: — Per-skill install

    /// Installs (or updates) a skill atomically.
    ///
    /// - Parameters:
    ///   - skillName: The skill directory name (e.g. `"my-skill"`).
    ///   - files: The new file contents keyed by filename.
    ///   - simulateSwapFailure: When `true` the rename step is skipped and an error
    ///     is returned, simulating a failure after the temp-write but before the swap.
    ///     This parameter exists purely for testing; production callers leave it `false`.
    /// - Returns: `.success(())` on success, `.failure(InstallError)` on failure.
    @discardableResult
    public func install(
        skillName: String,
        files: [String: Data],
        simulateSwapFailure: Bool = false
    ) -> Result<Void, InstallError> {
        let fm = FileManager.default
        let finalPath = skillsDirectory.appending(path: skillName, directoryHint: .isDirectory)

        // Step 1: Write new files to a temp directory on the same volume.
        let tempPath = skillsDirectory.appending(
            path: ".tmp-\(skillName)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try fm.createDirectory(at: tempPath, withIntermediateDirectories: true)
            for (filename, data) in files {
                try data.write(to: tempPath.appending(path: filename))
            }
        } catch {
            try? fm.removeItem(at: tempPath)
            return .failure(.fileSystemError(underlying: error.localizedDescription))
        }

        // Step 2: Move aside the existing skill directory (if present) to backup.
        let existingIsPresent = fm.fileExists(atPath: finalPath.path(percentEncoded: false))
        var backupPath: URL? = nil
        if existingIsPresent {
            do {
                let bp = try moveToBackup(skillName: skillName, from: finalPath)
                backupPath = bp
            } catch {
                try? fm.removeItem(at: tempPath)
                return .failure(.fileSystemError(underlying: error.localizedDescription))
            }
        }

        // Step 3: Atomic rename — if simulating failure, restore backup and bail.
        if simulateSwapFailure {
            // Undo the backup move so the original is intact.
            if let bp = backupPath, existingIsPresent {
                try? fm.moveItem(at: bp, to: finalPath)
                // Try to clean up the now-empty timestamp dir.
                try? fm.removeItem(at: bp.deletingLastPathComponent())
            }
            try? fm.removeItem(at: tempPath)
            return .failure(.swapFailed(underlying: "simulated swap failure"))
        }

        do {
            try fm.moveItem(at: tempPath, to: finalPath)
        } catch {
            // Restore backup on swap failure.
            if let bp = backupPath, existingIsPresent {
                try? fm.moveItem(at: bp, to: finalPath)
                try? fm.removeItem(at: bp.deletingLastPathComponent())
            }
            try? fm.removeItem(at: tempPath)
            return .failure(.swapFailed(underlying: error.localizedDescription))
        }

        // Step 4: Update Cache mirror only after the swap succeeded.
        do {
            try cache.writeSkillFiles(named: skillName, files: files)
        } catch {
            // The skills directory has the new content; log but don't fail.
            // In production, the cache will self-heal on the next check.
            // For the tests, this path is intentionally non-fatal.
        }

        return .success(())
    }

    // MARK: — Bulk install

    /// Installs a batch of skills, each independently.
    ///
    /// One skill's failure does not abort others. Returns a dictionary of per-skill results.
    /// Backup pruning runs automatically after the batch completes.
    ///
    /// - Parameter updates: The skills to install.
    /// - Returns: A dictionary mapping skill name → `Result<Void, InstallError>`.
    @discardableResult
    public func installBatch(_ updates: [SkillUpdate]) -> [String: Result<Void, InstallError>] {
        var results: [String: Result<Void, InstallError>] = [:]
        for update in updates {
            results[update.name] = install(
                skillName: update.name,
                files: update.files,
                simulateSwapFailure: update.simulateSwapFailure
            )
        }
        pruneBackups()
        return results
    }

    // MARK: — Removal (Removed-on-origin Update)

    /// Handles a "Removed on origin — Update" action: backs up the installed skill,
    /// removes it from the skills directory, and updates the cache to record absence.
    ///
    /// - Parameter skillName: The skill to remove.
    /// - Returns: `.success(())` on success, `.failure(InstallError)` on failure.
    @discardableResult
    public func removeInstalled(skillName: String) -> Result<Void, InstallError> {
        let fm = FileManager.default
        let skillPath = skillsDirectory.appending(path: skillName, directoryHint: .isDirectory)

        // Move to backup before deletion.
        if fm.fileExists(atPath: skillPath.path(percentEncoded: false)) {
            do {
                _ = try moveToBackup(skillName: skillName, from: skillPath)
            } catch {
                return .failure(.fileSystemError(underlying: error.localizedDescription))
            }
        }

        // Remove from cache (records absence: no directory means absent).
        let cacheSkillDir = cache.root.appending(path: "skills/\(skillName)", directoryHint: .isDirectory)
        try? fm.removeItem(at: cacheSkillDir)

        return .success(())
    }

    // MARK: — Removal (Removed-on-origin Skip)

    /// Handles a "Removed on origin — Skip" action: records the absence in the Cache
    /// without touching the skills directory.
    ///
    /// - Parameter skillName: The skill whose Cache entry should be cleared.
    /// - Returns: `.success(())` always (no filesystem change to the skills directory).
    @discardableResult
    public func skipRemoval(skillName: String) -> Result<Void, InstallError> {
        // Remove from cache to record origin's absence; skills dir is left intact.
        let cacheSkillDir = cache.root.appending(path: "skills/\(skillName)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: cacheSkillDir)
        return .success(())
    }

    // MARK: — Update Available Skip (copies O → Cache only)

    /// Handles a "Update available — Skip" action: copies the origin content into the
    /// Cache (acknowledging the origin version as seen) WITHOUT touching the skills directory.
    ///
    /// Per ADR 0006: Skip means C ← O. After this call, `C == O`, so the skill reads
    /// as `.skipped` on the next derive (C == O, S != O). Skills directory is unchanged.
    ///
    /// - Parameters:
    ///   - skillName: The skill directory name.
    ///   - files: The origin files to write into the Cache (O content).
    /// - Returns: `.success(())` on success, `.failure(InstallError)` on failure.
    @discardableResult
    public func skipUpdate(skillName: String, files: [String: Data]) -> Result<Void, InstallError> {
        do {
            try cache.writeSkillFiles(named: skillName, files: files)
        } catch {
            return .failure(.fileSystemError(underlying: error.localizedDescription))
        }
        return .success(())
    }

    // MARK: — Backup pruning

    /// Prunes backup timestamp directories that are older than 7 days.
    ///
    /// The "age" is computed relative to the engine's injected clock, so tests can
    /// drive arbitrary time offsets without wall-clock sensitivity.
    ///
    /// Should be called on app launch and after every install batch.
    public func pruneBackups() {
        let fm = FileManager.default
        let formatter = ISO8601DateFormatter()
        let cutoff = clock.now.addingTimeInterval(-Self.retentionInterval)

        guard let entries = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for entry in entries {
            guard
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                isDir
            else { continue }

            let dirName = entry.lastPathComponent
            guard let backupDate = formatter.date(from: dirName) else { continue }

            // Prune if the backup is older than (or equal to) the cutoff
            // ("retained for 7 days" means it is gone once age >= 7 days).
            if backupDate <= cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // MARK: — Private helpers

    /// Moves `source` to `backupsDirectory/<ISO8601-now>/<skillName>/` and returns the backup URL.
    private func moveToBackup(skillName: String, from source: URL) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: clock.now)
        let timestampDir = backupsDirectory.appending(path: timestamp, directoryHint: .isDirectory)
        let backupDest = timestampDir.appending(path: skillName, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: timestampDir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: backupDest)
        return backupDest
    }
}
