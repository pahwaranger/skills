import Testing
import Foundation
@testable import DiffBridge

// MARK: — UnifiedDiffGenerator tests
//
// These tests verify that `UnifiedDiffGenerator.generate(installed:origin:skillName:)`
// produces a unified-diff string that:
//   1. Parses correctly via `UnifiedDiffParser` into the expected `[FileDiff]`
//   2. Has the correct `+`/`-` line content for at least one modified-file case
//
// Coverage: added file, removed file, modified text file, binary file, unchanged (omitted),
// and mixed multi-file scenarios.

// MARK: — Helpers

private func makeData(_ string: String) -> Data {
    Data(string.utf8)
}

private func makeBinary() -> Data {
    // Contains a NUL byte — detected as binary
    Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02, 0x03])
}

// MARK: — Added file (only in origin, not installed)

struct DiffGenerator_AddedFileTests {

    @Test func addedFileParsesToAddedStatus() {
        let installed: [String: Data] = [:]
        let origin: [String: Data]    = ["SKILL.md": makeData("# hello\n")]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].status == .added)
        #expect(parsed[0].filename.hasSuffix("SKILL.md"))
        #expect(parsed[0].isBinary == false)
    }

    @Test func addedFileLineCountMatchesOrigin() {
        let content = "line1\nline2\nline3\n"
        let installed: [String: Data] = [:]
        let origin: [String: Data]    = ["SKILL.md": makeData(content)]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].addedLines == 3)
        #expect(parsed[0].removedLines == 0)
    }

    @Test func addedFileHasDevNullFromHeader() {
        let installed: [String: Data] = [:]
        let origin: [String: Data]    = ["SKILL.md": makeData("# hello\n")]

        let diff = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        #expect(diff.contains("--- /dev/null"))
        #expect(diff.contains("+++ b/my-skill/SKILL.md"))
    }
}

// MARK: — Removed file (only installed, not in origin)

struct DiffGenerator_RemovedFileTests {

    @Test func removedFileParsesToRemovedStatus() {
        let installed: [String: Data] = ["SKILL.md": makeData("# hello\n")]
        let origin: [String: Data]    = [:]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].status == .removed)
        #expect(parsed[0].filename.hasSuffix("SKILL.md"))
        #expect(parsed[0].isBinary == false)
    }

    @Test func removedFileLineCountMatchesInstalled() {
        let content = "line1\nline2\n"
        let installed: [String: Data] = ["SKILL.md": makeData(content)]
        let origin: [String: Data]    = [:]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].removedLines == 2)
        #expect(parsed[0].addedLines == 0)
    }

    @Test func removedFileHasDevNullToHeader() {
        let installed: [String: Data] = ["SKILL.md": makeData("# hello\n")]
        let origin: [String: Data]    = [:]

        let diff = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        #expect(diff.contains("--- a/my-skill/SKILL.md"))
        #expect(diff.contains("+++ /dev/null"))
    }
}

// MARK: — Modified file (in both, different content)

struct DiffGenerator_ModifiedFileTests {

    @Test func modifiedFileParsesToModifiedStatus() {
        let installed: [String: Data] = ["SKILL.md": makeData("old line\n")]
        let origin: [String: Data]    = ["SKILL.md": makeData("new line\n")]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].status == .modified)
    }

    @Test func modifiedFileLineCounts() {
        let installed: [String: Data] = ["SKILL.md": makeData("line1\nold line\nline3\n")]
        let origin: [String: Data]    = ["SKILL.md": makeData("line1\nnew line\nnew line2\nline3\n")]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].removedLines == 1)  // "old line" removed
        #expect(parsed[0].addedLines   == 2)  // "new line" + "new line2" added
    }

    @Test func modifiedFileHasCorrectPlusMinus() {
        let installed: [String: Data] = ["SKILL.md": makeData("old\n")]
        let origin: [String: Data]    = ["SKILL.md": makeData("new\n")]

        let diff = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        // The old line should be a `-` line, the new a `+` line
        let lines = diff.components(separatedBy: "\n")
        let minusLines = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("--- ") }
        let plusLines  = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++ ") }

        #expect(minusLines.contains("-old"))
        #expect(plusLines.contains("+new"))
    }

    @Test func unchangedFileIsOmitted() {
        // When installed == origin, the file should not appear in the diff at all.
        let content   = "unchanged content\n"
        let installed: [String: Data] = ["SKILL.md": makeData(content)]
        let origin: [String: Data]    = ["SKILL.md": makeData(content)]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.isEmpty)
    }

    @Test func multipleModifiedFilesAllPresent() {
        let installed: [String: Data] = [
            "SKILL.md":   makeData("old skill\n"),
            "CONTEXT.md": makeData("old context\n"),
        ]
        let origin: [String: Data] = [
            "SKILL.md":   makeData("new skill\n"),
            "CONTEXT.md": makeData("new context\n"),
        ]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 2)
        for fd in parsed {
            #expect(fd.status == .modified)
        }
    }
}

// MARK: — Binary file

struct DiffGenerator_BinaryFileTests {

    @Test func binaryFileParsedAsIsBinary() {
        let installed: [String: Data] = [:]
        let origin: [String: Data]    = ["icon.png": makeBinary()]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].isBinary == true)
    }

    @Test func binaryFileHasZeroLineCounts() {
        let installed: [String: Data] = [:]
        let origin: [String: Data]    = ["icon.png": makeBinary()]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed[0].addedLines == 0)
        #expect(parsed[0].removedLines == 0)
    }

    @Test func binaryFileDoesNotCrash() {
        // Should not throw or crash — just emit the binary marker
        let installed: [String: Data] = ["icon.png": makeBinary()]
        let origin: [String: Data]    = ["icon.png": makeBinary()]

        let diff = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        // Two identical binaries → no diff (unchanged) OR binary marker
        // Either way no crash
        _ = UnifiedDiffParser.parse(diff)
    }

    @Test func installedBinaryRemovedProducesRemovedBinary() {
        let installed: [String: Data] = ["icon.png": makeBinary()]
        let origin: [String: Data]    = [:]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        #expect(parsed.count == 1)
        #expect(parsed[0].isBinary == true)
        #expect(parsed[0].status == .removed)
    }
}

// MARK: — Mixed scenario (added + removed + modified + binary)

struct DiffGenerator_MixedScenarioTests {

    @Test func mixedScenarioProducesCorrectFileDiffs() {
        let installed: [String: Data] = [
            "SKILL.md":       makeData("old skill\n"),   // modified
            "OLD.md":         makeData("old only\n"),    // removed
            "unchanged.md":   makeData("same\n"),        // unchanged → omitted
        ]
        let origin: [String: Data] = [
            "SKILL.md":       makeData("new skill\n"),   // modified
            "NEW.md":         makeData("brand new\n"),   // added
            "unchanged.md":   makeData("same\n"),        // unchanged → omitted
            "icon.png":       makeBinary(),              // added binary
        ]

        let diff   = UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: "my-skill")
        let parsed = UnifiedDiffParser.parse(diff)

        // Expect: modified SKILL.md, removed OLD.md, added NEW.md, added binary icon.png (4 total)
        #expect(parsed.count == 4)

        let byFilename = Dictionary(uniqueKeysWithValues: parsed.map { ($0.filename.components(separatedBy: "/").last ?? $0.filename, $0) })
        #expect(byFilename["SKILL.md"]?.status   == .modified)
        #expect(byFilename["OLD.md"]?.status     == .removed)
        #expect(byFilename["NEW.md"]?.status     == .added)
        #expect(byFilename["icon.png"]?.isBinary == true)
    }
}

// MARK: — Empty skill (no files on either side)

struct DiffGenerator_EmptySkillTests {

    @Test func bothEmptyProducesEmptyDiff() {
        let diff   = UnifiedDiffGenerator.generate(installed: [:], origin: [:], skillName: "empty-skill")
        let parsed = UnifiedDiffParser.parse(diff)
        #expect(parsed.isEmpty)
    }
}
