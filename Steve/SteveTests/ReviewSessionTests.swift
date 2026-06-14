import Testing
import Foundation
import Cache
import OriginClient
import StateEngine
import Installer
@testable import AppCore

// MARK: — Helpers

/// Minimal stub transport for ReviewSession tests.
private final class ReviewSessionStubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sha: String
    var sha: String {
        get { lock.withLock { _sha } }
        set { lock.withLock { _sha = newValue } }
    }

    init(sha: String) { _sha = sha }

    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let currentSHA = lock.withLock { _sha }
        let urlString = url.absoluteString
        if urlString.contains("commits") {
            return HTTPResponse(
                status: 200,
                headers: ["ETag": "\"etag-\(currentSHA)\""],
                body: Data((currentSHA + "\n").utf8)
            )
        } else if urlString.contains("tar.gz") {
            let tarData = try ReviewSessionTestHelpers.makeFakeTarGz(
                skillName: "test-skill", fileContents: "v1 content"
            )
            return HTTPResponse(status: 200, headers: [:], body: tarData)
        }
        return HTTPResponse(status: 404, headers: [:], body: Data())
    }
}

/// Builds a minimal fake tarball for tests (matches AppCoreTests helper).
enum ReviewSessionTestHelpers {
    static func makeFakeTarGz(skillName: String, fileContents: String) throws -> Data {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "rstest-tarball-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let prefix = "repo-sha123"
        let skillDir = tmpDir.appending(path: "\(prefix)/skills/\(skillName)")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillFile = skillDir.appending(path: "SKILL.md")
        try Data(fileContents.utf8).write(to: skillFile)
        let tarGzPath = tmpDir.appending(path: "archive.tar.gz").path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", tarGzPath, "-C", tmpDir.path(percentEncoded: false), prefix]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: URL(fileURLWithPath: tarGzPath))
    }

    /// Builds a temp dir tree for install tests: returns (skillsDir, backupsDir, cacheDir).
    static func makeTempInstallDirs(label: String) throws -> (URL, URL, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "rs-install-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let skillsDir = tmp.appending(path: "skills", directoryHint: .isDirectory)
        let backupsDir = tmp.appending(path: "backups", directoryHint: .isDirectory)
        let cacheDir = tmp.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return (skillsDir, backupsDir, cacheDir)
    }
}

// MARK: — Scenario 1: SHA matches → Update proceeds (install side-effect)

/// When the live origin SHA still matches the snapshot SHA captured at window-open time,
/// calling `appModel.performUpdate(skills:engine:)` must invoke `engine.install(…)` and
/// return `.committed`. The cache must reflect the installed content and the skill file
/// must exist on disk under the skills directory.
@Suite("ReviewSession — SHA match → Update commits")
struct ReviewSessionUpdateTests {

    @Test @MainActor func shaMatchAllowsUpdate() async throws {
        let sha = "snapshot-sha-v1"
        let transport = ReviewSessionStubTransport(sha: sha)

        let (skillsDir, backupsDir, cacheDir) = try ReviewSessionTestHelpers.makeTempInstallDirs(label: "update")
        let appCacheDir = cacheDir.appending(path: "appcache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: skillsDir.deletingLastPathComponent())
        }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: appCacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )
        // Run a check so lastDerivedState is populated with "test-skill".
        await model.start()

        // Open the Review window — captures the immutable snapshot.
        model.openReviewSession()

        // Confirm a session was captured with the origin SHA.
        guard let session = model.reviewSession else {
            Issue.record("reviewSession must be non-nil after openReviewSession()")
            return
        }
        #expect(session.originSHA == sha, "snapshot SHA must match the live origin SHA at open time")

        // Build install engine pointed at temp dirs.
        let installCacheStore = CacheStore(root: cacheDir)
        let engine = InstallEngine(
            skillsDirectory: skillsDir,
            backupsDirectory: backupsDir,
            cache: installCacheStore
        )

        // The update payload: one skill with known files.
        let skillFiles: [String: Data] = ["SKILL.md": Data("v1 content".utf8)]
        let updates = [ReviewSkillUpdate(name: "test-skill", files: skillFiles)]

        // Perform update — SHA still matches → should commit.
        let outcome = await model.performUpdate(skills: updates, engine: engine, liveTransport: transport)

        #expect(outcome == .committed, "Update should commit when SHA matches snapshot")
        #expect(installCacheStore.cachedSkillNames().contains("test-skill"),
                "Cache must contain test-skill after a successful update")

        // Also verify the skill file was written to the skills directory on disk
        // (not just the cache). A successful Update must deliver the file to the skills dir.
        let installedFile = skillsDir.appending(path: "test-skill/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: installedFile.path(percentEncoded: false)),
                "SKILL.md must exist under skillsDir/test-skill/ after a successful Update")
    }
}

// MARK: — Scenario 2: SHA moved → action blocked (no install)

/// When the live origin SHA differs from the snapshot SHA, calling `performUpdate` or
/// `performSkip` must return `.shaMovedReloadRequired` and must NOT invoke any install.
@Suite("ReviewSession — SHA moved → action blocked")
struct ReviewSessionSHAMovedTests {

    @Test @MainActor func shaMovedBlocksUpdate() async throws {
        let originalSHA = "snapshot-sha-v1"
        let transport = ReviewSessionStubTransport(sha: originalSHA)

        let (skillsDir, backupsDir, cacheDir) = try ReviewSessionTestHelpers.makeTempInstallDirs(label: "shamoved-update")
        let appCacheDir = cacheDir.appending(path: "appcache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: skillsDir.deletingLastPathComponent())
        }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: appCacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )
        await model.start()

        // Capture snapshot with original SHA.
        model.openReviewSession()
        #expect(model.reviewSession?.originSHA == originalSHA)

        // Origin moves AFTER the snapshot was captured.
        transport.sha = "moved-sha-v2"

        let installCacheStore = CacheStore(root: cacheDir)
        let engine = InstallEngine(
            skillsDirectory: skillsDir,
            backupsDirectory: backupsDir,
            cache: installCacheStore
        )

        let skillFiles: [String: Data] = ["SKILL.md": Data("v2 content".utf8)]
        let updates = [ReviewSkillUpdate(name: "test-skill", files: skillFiles)]

        let outcome = await model.performUpdate(skills: updates, engine: engine, liveTransport: transport)

        #expect(outcome == .shaMovedReloadRequired,
                "Update must be blocked when origin SHA has moved since snapshot")
        #expect(!installCacheStore.cachedSkillNames().contains("test-skill"),
                "No install must happen when SHA has moved")
    }

    @Test @MainActor func shaMovedBlocksSkip() async throws {
        let originalSHA = "snapshot-sha-v1"
        let transport = ReviewSessionStubTransport(sha: originalSHA)

        let (skillsDir, backupsDir, cacheDir) = try ReviewSessionTestHelpers.makeTempInstallDirs(label: "shamoved-skip")
        let appCacheDir = cacheDir.appending(path: "appcache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: skillsDir.deletingLastPathComponent())
        }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: appCacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )
        await model.start()

        model.openReviewSession()
        // Intermediate assertion: session captures the original SHA right at window-open.
        #expect(model.reviewSession?.originSHA == originalSHA,
                "reviewSession must capture the original SHA immediately after openReviewSession()")

        // Origin moves.
        transport.sha = "moved-sha-v2"

        let installCacheStore = CacheStore(root: cacheDir)
        let engine = InstallEngine(
            skillsDirectory: skillsDir,
            backupsDirectory: backupsDir,
            cache: installCacheStore
        )

        let skillFiles: [String: Data] = ["SKILL.md": Data("v1 content".utf8)]
        let skips = [ReviewSkillUpdate(name: "test-skill", files: skillFiles)]

        let outcome = await model.performSkip(skills: skips, engine: engine, liveTransport: transport)

        #expect(outcome == .shaMovedReloadRequired,
                "Skip must be blocked when origin SHA has moved since snapshot")
        #expect(!installCacheStore.cachedSkillNames().contains("test-skill"),
                "No cache write must happen when SHA has moved on skip")
    }
}

// MARK: — Scenario 3: Background check during open review → snapshot unchanged

/// A background check (scheduler tick) may update `lastDerivedState` on AppModel,
/// but must NOT mutate the open `reviewSession`. The window's captured SHA and skill
/// list remain stable for the lifetime of the review.
@Suite("ReviewSession — background check does not mutate open session")
struct ReviewSessionConcurrentCheckTests {

    @Test @MainActor func backgroundCheckLeavesReviewSessionStable() async throws {
        let sha = "window-open-sha"
        let transport = ReviewSessionStubTransport(sha: sha)

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "rs-concurrent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )
        await model.start()

        // Open the review window — capture snapshot.
        model.openReviewSession()
        let capturedSession = model.reviewSession
        let capturedSHA = capturedSession?.originSHA

        // Simulate a background check: origin moves, scheduler fires another check.
        transport.sha = "new-background-sha"
        await model.triggerCheck()  // scheduler check — updates lastDerivedState

        // lastDerivedState may have changed (background check is allowed to update it),
        // but reviewSession must remain immutable and unchanged.
        let sessionAfterCheck = model.reviewSession
        #expect(sessionAfterCheck?.originSHA == capturedSHA,
                "reviewSession SHA must be unchanged after a background scheduler check")
        #expect(model.reviewSession?.originSHA == sha,
                "reviewSession must still hold the SHA captured at window-open time")
    }
}

// MARK: — Scenario 4: Close + reopen captures a fresh snapshot (Fix 1 — bug)

/// After the Review window CLOSES (`closeReviewSession()`), `reviewSession` is `nil`.
/// If the origin then moves to a new SHA and the window REOPENS (`openReviewSession()`),
/// the new session must reflect the MOVED sha — not the stale SHA from the first open.
///
/// This test FAILS against the pre-fix code (where `closeReviewSession()` is never called
/// by the view), because `openReviewSession()` won't overwrite a non-nil session — so
/// the session persists across the close/reopen cycle, yielding the stale SHA.
@Suite("ReviewSession — close clears session so reopen captures fresh snapshot")
struct ReviewSessionReopenTests {

    @Test @MainActor func closeAndReopenCapturesFreshSnapshot() async throws {
        let shaA = "sha-at-first-open"
        let transport = ReviewSessionStubTransport(sha: shaA)

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "rs-reopen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )
        await model.start()

        // ── First open: captures SHA-A ─────────────────────────────────────
        model.openReviewSession()
        #expect(model.reviewSession?.originSHA == shaA,
                "First open must capture SHA-A")

        // ── Window closes: clears the session ─────────────────────────────
        model.closeReviewSession()
        #expect(model.reviewSession == nil,
                "closeReviewSession() must nil out reviewSession")

        // ── Origin moves to SHA-B while window is closed ───────────────────
        let shaB = "sha-after-origin-moved"
        transport.sha = shaB
        await model.triggerCheck()  // updates lastKnownOriginSHA to SHA-B

        // ── Reopen: must capture SHA-B, not the stale SHA-A ───────────────
        model.openReviewSession()
        #expect(model.reviewSession?.originSHA == shaB,
                "Reopen after close must capture the moved SHA-B, not the stale SHA-A")
    }
}
