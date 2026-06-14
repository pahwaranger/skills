import Foundation
#if SWIFT_PACKAGE
import OriginClient
import Installer
#endif

// MARK: — ReviewSession

/// An immutable snapshot of the origin state captured when the Review window opens.
///
/// The Review window operates against THIS snapshot for its entire lifetime.
/// Background scheduler checks update `AppModel.lastDerivedState` but must never
/// mutate an open `ReviewSession` (ADR 0006 — review-session consistency).
///
/// Before any Update or Skip action commits, the live origin SHA is re-validated
/// against `originSHA`. If origin has moved since the window opened, the commit is
/// blocked and `ReviewActionOutcome.shaMovedReloadRequired` is returned.
public struct ReviewSession: Sendable, Equatable {
    /// The commit SHA of origin at the time the Review window opened.
    public let originSHA: String

    /// Per-skill file contents from the origin snapshot, keyed by skill name.
    /// Used by Update (to write to the skills directory and cache) and Skip
    /// (to write O → Cache only). Populated from the last known origin snapshot
    /// so the Review window can commit without a second network round-trip.
    public let skillFiles: [String: [String: Data]]

    public init(originSHA: String, skillFiles: [String: [String: Data]] = [:]) {
        self.originSHA = originSHA
        self.skillFiles = skillFiles
    }
}

// MARK: — ReviewSkillUpdate

/// A single skill to update or skip as part of a review action.
public struct ReviewSkillUpdate: Sendable {
    public let name: String
    /// The origin files for this skill (used to write to the skills dir on Update,
    /// or to the Cache only on Skip).
    public let files: [String: Data]

    public init(name: String, files: [String: Data]) {
        self.name = name
        self.files = files
    }
}

// MARK: — ReviewActionOutcome

/// The result of a `performUpdate` or `performSkip` call.
public enum ReviewActionOutcome: Sendable, Equatable {
    /// The action was committed successfully (install/cache wrote without error).
    case committed
    /// The live origin SHA has moved since the session snapshot was captured.
    /// The user must reload and re-review; no install was performed.
    case shaMovedReloadRequired
}

// MARK: — AppModel + ReviewSession wiring

extension AppModel {

    // MARK: — Convenience bulk Update/Skip (uses internal engine + transport)

    /// Convenience wrapper: performs a bulk Update for `skillNames` using the
    /// engine and transport injected at init. Returns `.shaMovedReloadRequired`
    /// if no engine is configured or the SHA check fails.
    public func performUpdate(skillNames: [String]) async -> ReviewActionOutcome {
        guard let engine = installEngine else { return .shaMovedReloadRequired }
        guard let session = reviewSession else { return .shaMovedReloadRequired }
        let updates = skillNames.compactMap { name -> ReviewSkillUpdate? in
            guard let files = session.skillFiles[name] else { return nil }
            return ReviewSkillUpdate(name: name, files: files)
        }
        guard !updates.isEmpty else { return .committed }
        return await performUpdate(skills: updates, engine: engine, liveTransport: _transport)
    }

    /// Convenience wrapper: performs a bulk Skip for `skillNames` using the
    /// engine and transport injected at init. Returns `.shaMovedReloadRequired`
    /// if no engine is configured or the SHA check fails.
    public func performSkip(skillNames: [String]) async -> ReviewActionOutcome {
        guard let engine = installEngine else { return .shaMovedReloadRequired }
        guard let session = reviewSession else { return .shaMovedReloadRequired }
        let skips = skillNames.compactMap { name -> ReviewSkillUpdate? in
            guard let files = session.skillFiles[name] else { return nil }
            return ReviewSkillUpdate(name: name, files: files)
        }
        guard !skips.isEmpty else { return .committed }
        return await performSkip(skills: skips, engine: engine, liveTransport: _transport)
    }

    // MARK: — Open / close review session

    /// Called when the Review window opens. Captures the current origin SHA from
    /// `lastDerivedState` (or the metadata cache) as an immutable `ReviewSession`.
    ///
    /// Background checks that fire after this call update `lastDerivedState` but must
    /// NOT replace `reviewSession` — the open window stays stable until explicitly
    /// re-checked by the user.
    ///
    /// If no origin SHA is available yet (no check has completed), `reviewSession` is set
    /// to `nil` and the caller should disable Update/Skip until a check completes.
    public func openReviewSession() {
        // Derive the origin SHA from the most recent check's snapshot SHA in the cache.
        // We use `lastDerivedState` as a signal that a check has completed, but we need
        // the actual SHA — which comes from the cache metadata written by `makePerformCheck`.
        //
        // Implementation note: we read the SHA from the check result stored in the
        // scheduler's last outcome. The most reliable source is the cache metadata's
        // commitSHA, which is written after every successful 200 response.
        // We do NOT fetch the live SHA at window-open time to avoid a network round-trip;
        // the SHA from the most recent completed check is authoritative.
        let sha = snapshotOriginSHA
        guard let sha else {
            reviewSession = nil
            return
        }
        reviewSession = ReviewSession(originSHA: sha, skillFiles: lastOriginSkillFiles)
    }

    /// Clears the current review session when the Review window closes.
    /// After this call, background checks may resume mutating `lastDerivedState` freely.
    public func closeReviewSession() {
        reviewSession = nil
    }

    // MARK: — SHA re-validation + Update commit

    /// Validates that the live origin SHA still matches the captured session snapshot,
    /// then installs each skill in `skills` via `engine.install(…)` if valid.
    ///
    /// - Parameters:
    ///   - skills: The skills to install (name + origin files).
    ///   - engine: The `InstallEngine` to use for the install.
    ///   - liveTransport: Transport used to re-fetch the current origin SHA for validation.
    /// - Returns: `.committed` if the SHA matched and installs succeeded;
    ///            `.shaMovedReloadRequired` if the origin SHA has moved.
    public func performUpdate(
        skills: [ReviewSkillUpdate],
        engine: InstallEngine,
        liveTransport: HTTPTransport
    ) async -> ReviewActionOutcome {
        guard let session = reviewSession else { return .shaMovedReloadRequired }
        let liveSHA = await AppModel.fetchLiveSHA(
            owner: owner, repo: repo, branch: branch,
            transport: liveTransport,
            sessionSHA: session.originSHA
        )
        guard let liveSHA, liveSHA == session.originSHA else {
            return .shaMovedReloadRequired
        }

        for skill in skills {
            engine.install(skillName: skill.name, files: skill.files)
        }
        return .committed
    }

    // MARK: — SHA re-validation + Skip commit

    /// Validates that the live origin SHA still matches the captured session snapshot,
    /// then records each skill as skipped by writing O → Cache via `engine.skipUpdate(…)`.
    ///
    /// - Parameters:
    ///   - skills: The skills to skip (name + origin files to acknowledge in cache).
    ///   - engine: The `InstallEngine` to use for the cache write.
    ///   - liveTransport: Transport used to re-fetch the current origin SHA for validation.
    /// - Returns: `.committed` if the SHA matched and cache writes succeeded;
    ///            `.shaMovedReloadRequired` if the origin SHA has moved.
    public func performSkip(
        skills: [ReviewSkillUpdate],
        engine: InstallEngine,
        liveTransport: HTTPTransport
    ) async -> ReviewActionOutcome {
        guard let session = reviewSession else { return .shaMovedReloadRequired }
        let liveSHA = await AppModel.fetchLiveSHA(
            owner: owner, repo: repo, branch: branch,
            transport: liveTransport,
            sessionSHA: session.originSHA
        )
        guard let liveSHA, liveSHA == session.originSHA else {
            return .shaMovedReloadRequired
        }

        for skill in skills {
            engine.skipUpdate(skillName: skill.name, files: skill.files)
        }
        return .committed
    }

    // MARK: — Private helpers

    /// Reads the captured origin SHA from the most recent scheduler check.
    /// Returns `nil` if no check has completed yet.
    private var snapshotOriginSHA: String? {
        // The SHA is stored in the cache's metadata after each successful 200 check.
        // AppModel does not expose the CacheStore directly; the scheduler's
        // lastDerivedState signals that a check has completed. We surface the SHA
        // via `lastKnownOriginSHA`, populated after each successful check.
        return lastKnownOriginSHA
    }

    /// Fetches the current live origin SHA from the transport (probe call only).
    ///
    /// Sends `If-None-Match: "<sessionSHA>"` so that GitHub returns 304 when the
    /// commit hasn't changed, allowing the validation to short-circuit without
    /// parsing a body. A 304 genuinely means "origin is still at sessionSHA —
    /// unchanged → still valid". A 200 returns the new SHA in the body.
    ///
    /// Returns `nil` if the fetch fails or returns an unexpected status.
    ///
    /// Static and nonisolated so it can be called from async contexts without
    /// crossing the main-actor boundary during the network hop.
    nonisolated static func fetchLiveSHA(
        owner: String,
        repo: String,
        branch: String,
        transport: HTTPTransport,
        sessionSHA: String
    ) async -> String? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(branch)")!
        // Send If-None-Match with the session SHA so the server can return 304 when
        // the commit is unchanged — more efficient than always parsing a 200 body.
        // GitHub's SHA endpoint uses the commit SHA directly as the ETag value
        // (without the typical "W/" weak prefix), so we quote it per RFC 7232.
        let headers: [String: String] = [
            "Accept": "application/vnd.github.sha",
            "User-Agent": "Steve",
            "If-None-Match": "\"\(sessionSHA)\""
        ]
        guard let response = try? await transport.get(url: url, headers: headers) else {
            return nil
        }
        switch response.status {
        case 200:
            return String(decoding: response.body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case 304:
            // Unchanged: the server confirmed the live SHA equals the session SHA.
            // Return the session SHA so the equality check passes — the action is valid.
            return sessionSHA
        default:
            return nil
        }
    }
}
