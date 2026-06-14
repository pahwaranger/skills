import Testing
import Foundation
@testable import DiffBridge

// MARK: — UnifiedDiffParser tests
//
// Exercises the parser that turns a raw unified-diff string into
// [FileDiff] — one entry per file, carrying filename, status, line
// counts, and binary flag. These are unit tests with no WKWebView.

// MARK: — Helpers

/// A representative multi-file unified diff (matching the prototype PROMPT.md
/// fake data for grill-with-docs): two modified files + one added file.
private let multiFileDiff = """
--- a/grill-with-docs/SKILL.md
+++ b/grill-with-docs/SKILL.md
@@ -1,12 +1,14 @@
 # grill-with-docs

-A disciplined grilling session.
+A disciplined grilling session that challenges your plan.

 ## When to use

-Use when you want to stress-test a plan.
+Use when you want to challenge a plan.
--- a/grill-with-docs/CONTEXT-FORMAT.md
+++ b/grill-with-docs/CONTEXT-FORMAT.md
@@ -8,6 +8,10 @@
 - Every concept should have one canonical term.
+- Terms introduced in one ADR must be used consistently.
+- If a term is redefined, the old ADR must be superseded.
--- /dev/null
+++ b/grill-with-docs/EXAMPLES.md
@@ -0,0 +1,5 @@
+# Examples — grill-with-docs
+
+## Example 1
+
+Some example content.
"""

/// An all-deletions diff for a removed-on-origin skill.
private let removedSkillDiff = """
--- a/zoom-out/SKILL.md
+++ /dev/null
@@ -1,10 +0,0 @@
-# Zoom Out
-
-Step back from the current task.
-
-## When to use
-
-When the user seems stuck.
-
-## Notes
-
"""

/// A binary-file marker as produced by `git diff` when a binary changes.
private let binaryDiff = """
--- a/assets/logo.png
+++ b/assets/logo.png
Binary files a/assets/logo.png and b/assets/logo.png differ
"""

/// A binary file that is newly added.
private let addedBinaryDiff = """
--- /dev/null
+++ b/assets/icon.icns
Binary files /dev/null and b/assets/icon.icns differ
"""

// MARK: — Status detection

struct FileDiffStatusTests {

    @Test func modifiedFileStatusIsModified() throws {
        let diff = """
        --- a/foo/SKILL.md
        +++ b/foo/SKILL.md
        @@ -1,3 +1,3 @@
         # foo
        -old line
        +new line
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].status == .modified)
    }

    @Test func addedFileStatusIsAdded() throws {
        let diff = """
        --- /dev/null
        +++ b/foo/EXAMPLES.md
        @@ -0,0 +1,3 @@
        +# Examples
        +
        +Content here.
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].status == .added)
    }

    @Test func removedFileStatusIsRemoved() throws {
        let diff = """
        --- a/zoom-out/SKILL.md
        +++ /dev/null
        @@ -1,3 +0,0 @@
        -# Zoom Out
        -
        -Step back.
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].status == .removed)
    }

    @Test func multipleFilesDetectedCorrectly() throws {
        let files = UnifiedDiffParser.parse(multiFileDiff)
        #expect(files.count == 3)

        let skill = files[0]
        #expect(skill.filename == "grill-with-docs/SKILL.md")
        #expect(skill.status == .modified)

        let context = files[1]
        #expect(context.filename == "grill-with-docs/CONTEXT-FORMAT.md")
        #expect(context.status == .modified)

        let examples = files[2]
        #expect(examples.filename == "grill-with-docs/EXAMPLES.md")
        #expect(examples.status == .added)
    }

    @Test func removedSkillAllDeletions() throws {
        let files = UnifiedDiffParser.parse(removedSkillDiff)
        #expect(files.count == 1)
        #expect(files[0].filename == "zoom-out/SKILL.md")
        #expect(files[0].status == .removed)
    }
}

// MARK: — Line count parsing

struct FileDiffLineCountTests {

    @Test func addedLinesCountedCorrectly() throws {
        let diff = """
        --- /dev/null
        +++ b/foo/EXAMPLES.md
        @@ -0,0 +1,3 @@
        +# Examples
        +
        +Content here.
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].addedLines == 3)
        #expect(files[0].removedLines == 0)
    }

    @Test func removedLinesCountedCorrectly() throws {
        let files = UnifiedDiffParser.parse(removedSkillDiff)
        #expect(files.count == 1)
        // 10 lines deleted (the removedSkillDiff has 10 "-" lines)
        #expect(files[0].removedLines == 10)
        #expect(files[0].addedLines == 0)
    }

    @Test func modifiedFileHasBothAddedAndRemovedLines() throws {
        let diff = """
        --- a/foo/SKILL.md
        +++ b/foo/SKILL.md
        @@ -1,4 +1,5 @@
         # foo
        -old line 1
        -old line 2
        +new line 1
        +new line 2
        +new line 3
         context
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].addedLines == 3)
        #expect(files[0].removedLines == 2)
    }

    @Test func multiFileLineCounts() throws {
        let files = UnifiedDiffParser.parse(multiFileDiff)
        #expect(files.count == 3)

        // SKILL.md: 2 removed, 2 added
        let skill = files[0]
        #expect(skill.addedLines == 2)
        #expect(skill.removedLines == 2)

        // CONTEXT-FORMAT.md: 0 removed, 2 added
        let context = files[1]
        #expect(context.addedLines == 2)
        #expect(context.removedLines == 0)

        // EXAMPLES.md: 5 added (new file)
        let examples = files[2]
        #expect(examples.addedLines == 5)
        #expect(examples.removedLines == 0)
    }

    @Test func contextLinesAreNotCounted() throws {
        let diff = """
        --- a/foo/SKILL.md
        +++ b/foo/SKILL.md
        @@ -1,5 +1,5 @@
         context line 1
         context line 2
        -removed
        +added
         context line 3
         context line 4
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        // Only 1 added and 1 removed — context lines (starting with space) excluded
        #expect(files[0].addedLines == 1)
        #expect(files[0].removedLines == 1)
    }
}

// MARK: — Binary file detection

struct FileDiffBinaryTests {

    @Test func binaryFileDetected() throws {
        let files = UnifiedDiffParser.parse(binaryDiff)
        #expect(files.count == 1)
        #expect(files[0].isBinary == true)
    }

    @Test func addedBinaryFileDetected() throws {
        let files = UnifiedDiffParser.parse(addedBinaryDiff)
        #expect(files.count == 1)
        #expect(files[0].isBinary == true)
        #expect(files[0].status == .added)
    }

    @Test func binaryFileHasZeroLineCounts() throws {
        let files = UnifiedDiffParser.parse(binaryDiff)
        #expect(files.count == 1)
        #expect(files[0].addedLines == 0)
        #expect(files[0].removedLines == 0)
    }

    @Test func binaryFileHasCorrectFilename() throws {
        let files = UnifiedDiffParser.parse(binaryDiff)
        #expect(files.count == 1)
        #expect(files[0].filename == "assets/logo.png")
    }

    @Test func textFileIsNotBinary() throws {
        let diff = """
        --- a/foo/SKILL.md
        +++ b/foo/SKILL.md
        @@ -1,3 +1,3 @@
         # foo
        -old
        +new
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].isBinary == false)
    }

    @Test func mixedDiffWithBinaryFile() throws {
        let mixed = """
        --- a/foo/SKILL.md
        +++ b/foo/SKILL.md
        @@ -1,3 +1,3 @@
         # foo
        -old
        +new
        --- a/assets/logo.png
        +++ b/assets/logo.png
        Binary files a/assets/logo.png and b/assets/logo.png differ
        """
        let files = UnifiedDiffParser.parse(mixed)
        #expect(files.count == 2)
        #expect(files[0].isBinary == false)
        #expect(files[1].isBinary == true)
    }
}

// MARK: — Extended git header (`diff --git`)

struct FileDiffExtendedHeaderTests {

    /// A diff as produced by `git diff` — includes the `diff --git a/… b/…` extended
    /// header line that precedes each `---` / `+++` pair. The parser must skip that line
    /// and produce exactly one clean FileDiff entry with the correct filename, status,
    /// and line counts.
    @Test func diffGitExtendedHeaderDoesNotCorruptParsing() throws {
        let diff = """
        diff --git a/grill-with-docs/SKILL.md b/grill-with-docs/SKILL.md
        index 4b2a1c3..9d8e7f1 100644
        --- a/grill-with-docs/SKILL.md
        +++ b/grill-with-docs/SKILL.md
        @@ -1,3 +1,4 @@
         # grill-with-docs
        -A disciplined grilling session.
        +A disciplined grilling session that challenges your plan.
        +
        """
        let files = UnifiedDiffParser.parse(diff)
        // Must produce exactly one entry — not split by the diff --git line.
        #expect(files.count == 1)
        #expect(files[0].filename == "grill-with-docs/SKILL.md")
        #expect(files[0].status == .modified)
        #expect(files[0].addedLines == 2)
        #expect(files[0].removedLines == 1)
        #expect(files[0].isBinary == false)
    }
}

// MARK: — Filename extraction

struct FileDiffFilenameTests {

    @Test func filenameStrippedOfAPrefix() throws {
        let diff = """
        --- a/skills/foo/SKILL.md
        +++ b/skills/foo/SKILL.md
        @@ -1 +1 @@
        -old
        +new
        """
        let files = UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].filename == "skills/foo/SKILL.md")
    }

    @Test func emptyDiffReturnsEmpty() throws {
        let files = UnifiedDiffParser.parse("")
        #expect(files.isEmpty)
    }

    @Test func diffWithNoFilesReturnsEmpty() throws {
        let files = UnifiedDiffParser.parse("just some random text\nno diff headers")
        #expect(files.isEmpty)
    }
}
