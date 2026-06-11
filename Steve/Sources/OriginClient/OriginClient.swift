import Foundation
import Cache

/// The result of a single check against Origin.
public enum CheckOutcome: Sendable {
    case unchanged(sha: String)      // 304 — nothing moved; the SHA we already had
    case updated(OriginSnapshot)     // 200 — Origin moved; freshly fetched tarball
    case ignored                     // a check was already in flight (single-flight)
}

/// Every failure mode is non-destructive: the caller keeps its last known state
/// and Cache, and retries per the taxonomy in ADR 0003.
public enum OriginError: Error, Equatable {
    case networkError(lastChecked: Date)  // unreachable / timeout / 5xx — retry next tick
    case rateLimited(retryAt: Date)       // 403 — back off until X-RateLimit-Reset
    case originNotFound                   // 404 / private — config error, slow retry
    case fetchFailed(lastChecked: Date)   // tarball corrupt/incomplete — retry next tick
}

/// Reads Origin over plain public HTTPS — no git, no auth (ADR 0003). The only
/// module that touches the network; everything goes through an injected
/// `HTTPTransport` so the whole client is exercised offline against a stub.
public actor OriginClient {
    private let owner: String
    private let repo: String
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private var inFlight = false

    public init(
        owner: String,
        repo: String,
        transport: HTTPTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.owner = owner
        self.repo = repo
        self.transport = transport
        self.now = now
    }

    /// Resolve and return Origin's default branch from the GitHub API. Never
    /// hardcoded to `main`/`master` — Slices 6 & 11 use it for GitHub links.
    public func resolveDefaultBranch() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
        let response = try await transport.get(url: url, headers: apiHeaders)
        struct RepoInfo: Decodable { let default_branch: String }
        let info = try JSONDecoder().decode(RepoInfo.self, from: response.body)
        return info.default_branch
    }

    /// Probe Origin for movement and, if it moved, fetch the new tree.
    /// `knownETag`/`knownSHA` are the caller's last-seen values from the Cache.
    public func check(branch: String, knownETag: String?, knownSHA: String?) async throws -> CheckOutcome {
        // Single-flight: a trigger that fires during a running check is ignored,
        // not queued or run concurrently (ADR 0003). Reentrancy-safe because the
        // actor only suspends at the awaits below, after this guard is set.
        if inFlight { return .ignored }
        inFlight = true
        defer { inFlight = false }

        let probeURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(branch)")!
        var headers = apiHeaders
        headers["Accept"] = "application/vnd.github.sha"  // body is the bare commit SHA
        if let knownETag { headers["If-None-Match"] = knownETag }
        let response = try await get(probeURL, headers: headers)

        switch response.status {
        case 304:
            return .unchanged(sha: knownSHA ?? "")
        case 403:
            let reset = response.header("X-RateLimit-Reset").flatMap(TimeInterval.init) ?? 0
            throw OriginError.rateLimited(retryAt: Date(timeIntervalSince1970: reset))
        case 404:
            throw OriginError.originNotFound
        case 200:
            return try await fetchUpdated(from: response)
        default:
            // Any other status is unexpected; stay non-destructive and retry next tick.
            throw OriginError.networkError(lastChecked: now())
        }
    }

    /// Fetch and extract the tarball named by a 200 probe response, returning the
    /// fresh snapshot. A corrupt/incomplete tarball surfaces as `fetchFailed`.
    private func fetchUpdated(from probeResponse: HTTPResponse) async throws -> CheckOutcome {
        let newSHA = String(decoding: probeResponse.body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let newETag = probeResponse.header("ETag") ?? ""

        let tarballURL = URL(string: "https://codeload.github.com/\(owner)/\(repo)/tar.gz/\(newSHA)")!
        let tarball = try await get(tarballURL, headers: apiHeaders)
        let skills: [OriginSnapshot.Skill]
        do {
            skills = try TarballExtractor.extractSkills(fromTarGz: tarball.body)
        } catch {
            throw OriginError.fetchFailed(lastChecked: now())
        }

        return .updated(OriginSnapshot(
            commitSHA: newSHA, etag: newETag, lastChecked: now(), skills: skills
        ))
    }

    /// All network access funnels through here so transport failures and 5xx
    /// map uniformly to `networkError` (ADR 0003 error taxonomy).
    private func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.get(url: url, headers: headers)
        } catch {
            throw OriginError.networkError(lastChecked: now())
        }
        if response.status >= 500 {
            throw OriginError.networkError(lastChecked: now())
        }
        return response
    }

    private var apiHeaders: [String: String] {
        ["Accept": "application/vnd.github+json", "User-Agent": "Steve"]
    }
}
