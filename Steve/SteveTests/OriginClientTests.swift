import Testing
import Foundation
import Cache
import OriginClient

// MARK: — Stub transport (the only seam we fake; extraction stays real)

/// Routes each request through a caller-supplied handler and records what was sent.
/// A closure handler is flexible enough to key responses by URL, throw, or block.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let handler: @Sendable (URL, [String: String]) async throws -> HTTPResponse
    private let lock = NSLock()
    private var _recorded: [(url: URL, headers: [String: String])] = []

    var recorded: [(url: URL, headers: [String: String])] {
        lock.withLock { _recorded }
    }

    init(handler: @escaping @Sendable (URL, [String: String]) async throws -> HTTPResponse) {
        self.handler = handler
    }

    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        lock.withLock { _recorded.append((url, headers)) }
        return try await handler(url, headers)
    }
}

/// Build a real `.tar.gz` that mirrors GitHub's codeload layout: a single
/// top-level prefix dir containing `skills/<name>/<files>`. Extraction is real
/// business logic, so the fixture is a real archive, not a stub.
func makeTarball(prefix: String, skills: [String: [String: String]]) throws -> Data {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appending(path: "steve-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fm.removeItem(at: root) }

    for (skill, files) in skills {
        let dir = root.appending(path: "\(prefix)/skills/\(skill)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: dir.appending(path: name))
        }
    }

    let out = root.appending(path: "archive.tar.gz")
    let proc = Process()
    proc.executableURL = URL(filePath: "/usr/bin/tar")
    proc.arguments = [
        "czf", out.path(percentEncoded: false),
        "-C", root.path(percentEncoded: false), prefix,
    ]
    try proc.run()
    proc.waitUntilExit()
    return try Data(contentsOf: out)
}

struct OriginClientTests {
    // MARK: — Default-branch resolution

    @Test func resolveDefaultBranchReadsFromAPINotHardcoded() async throws {
        // A non-main/master value proves the branch is read, not assumed.
        let body = Data(#"{"name":"skills","default_branch":"trunk"}"#.utf8)
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 200, headers: [:], body: body)
        }
        let client = OriginClient(owner: "pahwaranger", repo: "skills", transport: transport)

        let branch = try await client.resolveDefaultBranch()

        #expect(branch == "trunk")
        #expect(
            transport.recorded.first?.url.absoluteString
                == "https://api.github.com/repos/pahwaranger/skills"
        )
    }

    // MARK: — Commit-SHA probe

    @Test func probe304ReturnsKnownSHAWithoutFetchingTarball() async throws {
        // 304 = nothing moved. The probe is the only request; no tarball.
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 304, headers: [:], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport)

        let outcome = try await client.check(branch: "main", knownETag: "\"abc\"", knownSHA: "sha123")

        guard case .unchanged(let sha) = outcome else {
            Issue.record("expected .unchanged, got \(outcome)")
            return
        }
        #expect(sha == "sha123")
        #expect(transport.recorded.count == 1)
        #expect(transport.recorded.allSatisfy { !$0.url.absoluteString.contains("codeload") })
    }

    @Test func probe200FetchesTarballAndReturnsUpdatedSnapshot() async throws {
        let tarball = try makeTarball(prefix: "skills-newsha456", skills: [
            "alpha": ["SKILL.md": "# alpha"],
            "beta": ["SKILL.md": "# beta", "helper.sh": "echo hi"],
        ])
        let transport = StubTransport { url, _ in
            if url.absoluteString.contains("codeload") {
                return HTTPResponse(status: 200, headers: [:], body: tarball)
            }
            // commits probe: new SHA as body (Accept: vnd.github.sha), new ETag header
            return HTTPResponse(status: 200, headers: ["ETag": "\"newetag\""], body: Data("newsha456".utf8))
        }
        let fixedNow = Date(timeIntervalSinceReferenceDate: 555)
        let client = OriginClient(owner: "o", repo: "r", transport: transport, now: { fixedNow })

        let outcome = try await client.check(branch: "main", knownETag: "\"oldetag\"", knownSHA: "oldsha")

        guard case .updated(let snapshot) = outcome else {
            Issue.record("expected .updated, got \(outcome)")
            return
        }
        #expect(snapshot.commitSHA == "newsha456")
        #expect(snapshot.etag == "\"newetag\"")
        #expect(snapshot.lastChecked == fixedNow)
        #expect(Set(snapshot.skills.map(\.name)) == ["alpha", "beta"])
        let beta = snapshot.skills.first { $0.name == "beta" }
        #expect(beta?.files["SKILL.md"] == Data("# beta".utf8))
        #expect(beta?.files["helper.sh"] == Data("echo hi".utf8))

        // If-None-Match carried the caller's ETag on the probe.
        let probe = transport.recorded.first { !$0.url.absoluteString.contains("codeload") }
        #expect(probe?.headers["If-None-Match"] == "\"oldetag\"")
        // Tarball fetched at the new SHA from codeload.
        #expect(transport.recorded.contains {
            $0.url.absoluteString == "https://codeload.github.com/o/r/tar.gz/newsha456"
        })
    }

    // MARK: — Error taxonomy

    @Test func probe403BacksOffUntilRateLimitReset() async throws {
        let resetEpoch = 1_700_000_000
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 403, headers: ["X-RateLimit-Reset": "\(resetEpoch)"], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport)

        await #expect(
            throws: OriginError.rateLimited(retryAt: Date(timeIntervalSince1970: TimeInterval(resetEpoch)))
        ) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    @Test func probe404SurfacesOriginNotFound() async throws {
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 404, headers: [:], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport)

        await #expect(throws: OriginError.originNotFound) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    @Test func transportFailureSurfacesNetworkError() async throws {
        struct Boom: Error {}
        let fixedNow = Date(timeIntervalSinceReferenceDate: 999)
        let transport = StubTransport { _, _ in throw Boom() }
        let client = OriginClient(owner: "o", repo: "r", transport: transport, now: { fixedNow })

        await #expect(throws: OriginError.networkError(lastChecked: fixedNow)) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    @Test func probe5xxSurfacesNetworkError() async throws {
        let fixedNow = Date(timeIntervalSinceReferenceDate: 42)
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 503, headers: [:], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport, now: { fixedNow })

        await #expect(throws: OriginError.networkError(lastChecked: fixedNow)) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    @Test func corruptTarballSurfacesFetchFailed() async throws {
        let fixedNow = Date(timeIntervalSinceReferenceDate: 7)
        let transport = StubTransport { url, _ in
            if url.absoluteString.contains("codeload") {
                return HTTPResponse(status: 200, headers: [:], body: Data("this is not a gzip tarball".utf8))
            }
            return HTTPResponse(status: 200, headers: ["ETag": "\"e\""], body: Data("sha".utf8))
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport, now: { fixedNow })

        await #expect(throws: OriginError.fetchFailed(lastChecked: fixedNow)) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    @Test func unexpectedStatusStaysNonDestructive() async throws {
        // A surprising status must never crash the app — it retries as networkError.
        let fixedNow = Date(timeIntervalSinceReferenceDate: 314)
        let transport = StubTransport { _, _ in
            HTTPResponse(status: 418, headers: [:], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport, now: { fixedNow })

        await #expect(throws: OriginError.networkError(lastChecked: fixedNow)) {
            try await client.check(branch: "main", knownETag: nil, knownSHA: nil)
        }
    }

    // MARK: — Single-flight

    @Test func secondConcurrentCheckIsIgnoredNotQueued() async throws {
        // Only the *first* transport entry blocks; a second entry (which should
        // never happen) returns immediately, so a broken guard fails cleanly
        // (.unchanged + entries == 2) instead of deadlocking the test.
        let gate = Gate()
        let transport = StubTransport { _, _ in
            let entry = gate.enter()
            if entry == 1 {
                while !gate.isReleased && !Task.isCancelled { await Task.yield() }
            }
            return HTTPResponse(status: 304, headers: [:], body: Data())
        }
        let client = OriginClient(owner: "o", repo: "r", transport: transport)

        // First check is launched and parked in-flight inside the transport.
        async let first = client.check(branch: "main", knownETag: "\"e\"", knownSHA: "sha1")
        while gate.entries == 0 { await Task.yield() }

        // Second trigger while the first is in flight → ignored, transport untouched.
        let second = try await client.check(branch: "main", knownETag: "\"e\"", knownSHA: "sha1")
        let secondIgnored = { if case .ignored = second { return true } else { return false } }()
        #expect(secondIgnored)
        #expect(gate.entries == 1)

        // Releasing lets the first finish normally.
        gate.release()
        let firstOutcome = try await first
        let firstUnchanged = { if case .unchanged(let sha) = firstOutcome { return sha == "sha1" } else { return false } }()
        #expect(firstUnchanged)
    }
}

/// Test-only latch: counts transport entries and gates the first one.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries = 0
    private var _released = false

    func enter() -> Int { lock.withLock { _entries += 1; return _entries } }
    var entries: Int { lock.withLock { _entries } }
    func release() { lock.withLock { _released = true } }
    var isReleased: Bool { lock.withLock { _released } }
}
