import Testing
import Foundation
import Cache

struct CacheTests {
    private func tempStore() throws -> (CacheStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "steve-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (CacheStore(root: dir), dir)
    }

    // MARK: — Rebuild

    @Test func rebuildWipesAndWritesSnapshot() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed stale state
        try store.writeSkillFiles(named: "old-skill", files: ["SKILL.md": Data("old".utf8)])
        try store.writeMetadata(CacheMetadata(
            commitSHA: "stale", etag: "\"old\"",
            lastChecked: Date(timeIntervalSinceReferenceDate: 0), skipState: ["old-skill": "stale"]
        ))

        let snapshot = OriginSnapshot(
            commitSHA: "fresh",
            etag: "\"new\"",
            lastChecked: Date(timeIntervalSinceReferenceDate: 1_000_000),
            skills: [
                OriginSnapshot.Skill(name: "new-skill", files: ["SKILL.md": Data("new".utf8)])
            ]
        )
        try store.rebuild(from: snapshot)

        // New metadata matches snapshot
        let meta = try store.readMetadata()
        #expect(meta.commitSHA == "fresh")
        #expect(meta.etag == "\"new\"")
        #expect(meta.skipState.isEmpty)

        // New skill written
        let newFiles = try store.skillFiles(named: "new-skill")
        #expect(newFiles["SKILL.md"] == Data("new".utf8))

        // Old skill gone
        #expect(throws: CacheError.missing) {
            try store.skillFiles(named: "old-skill")
        }
    }

    // MARK: — Skill directory round-trip

    @Test func skillFilesRoundTrip() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let files: [String: Data] = [
            "SKILL.md": Data("# my-skill\nHello".utf8),
            "helper.sh": Data("#!/bin/bash\necho hi".utf8),
        ]
        try store.writeSkillFiles(named: "my-skill", files: files)
        let read = try store.skillFiles(named: "my-skill")
        #expect(read == files)
    }

    // MARK: — Corruption detection

    @Test func corruptMetadataThrows() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadataFile = dir.appending(path: "metadata.json")
        try Data("not valid json }{".utf8).write(to: metadataFile)

        #expect(throws: CacheError.corrupt) {
            try store.readMetadata()
        }
    }

    @Test func missingCacheDirThrows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "steve-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        // intentionally not created
        let store = CacheStore(root: dir)

        #expect(throws: CacheError.missing) {
            try store.readMetadata()
        }
    }

    // MARK: — Metadata round-trip

    @Test func metadataRoundTrip() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = CacheMetadata(
            commitSHA: "abc123",
            etag: "\"v1\"",
            lastChecked: Date(timeIntervalSinceReferenceDate: 1_000_000),
            skipState: ["my-skill": "abc123"]
        )
        try store.writeMetadata(metadata)
        let read = try store.readMetadata()
        #expect(read == metadata)
    }
}
