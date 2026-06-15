import Foundation

// MARK: — FileDiff

/// Per-file metadata extracted from a raw unified diff string.
/// Used to drive the SwiftUI file-card affordances in the diff pane (Slice 9b).
public struct FileDiff: Equatable, Sendable {

    // MARK: — Status

    /// Whether the file was added, removed, or modified.
    public enum Status: String, Equatable, Sendable {
        case added
        case removed
        case modified
    }

    // MARK: — Properties

    /// The file path, with the `a/` / `b/` prefix stripped.
    /// Example: `"grill-with-docs/SKILL.md"`.
    public let filename: String

    /// Whether the file was added, removed, or modified.
    public let status: Status

    /// Number of `+` (added) lines in the diff for this file.
    /// Binary files always have `addedLines == 0`.
    public let addedLines: Int

    /// Number of `-` (removed) lines in the diff for this file.
    /// Binary files always have `removedLines == 0`.
    public let removedLines: Int

    /// `true` if the diff contains a `Binary files … differ` marker.
    /// When `true`, `addedLines` and `removedLines` are both `0`.
    public let isBinary: Bool

    /// The substring of the original unified diff that belongs exclusively to this file.
    ///
    /// Starts at the `--- ` header for this file and ends just before the `--- ` header of
    /// the next file (or at the end of the input). Passing this to `DiffRendererView` ensures
    /// each file card renders only its own hunk (Issue #44).
    public let rawSlice: String

    public init(
        filename: String,
        status: Status,
        addedLines: Int,
        removedLines: Int,
        isBinary: Bool,
        rawSlice: String = ""
    ) {
        self.filename     = filename
        self.status       = status
        self.addedLines   = addedLines
        self.removedLines = removedLines
        self.isBinary     = isBinary
        self.rawSlice     = rawSlice
    }
}

// MARK: — UnifiedDiffParser

/// Parses a raw unified-diff string (as produced by `git diff` or `git diff --no-index`)
/// into a list of per-file `FileDiff` values.
///
/// The parser handles:
/// - Modified files (`--- a/…` / `+++ b/…`)
/// - Added files (`--- /dev/null` / `+++ b/…`)
/// - Removed files (`--- a/…` / `+++ /dev/null`)
/// - Binary files (`Binary files … differ`)
///
/// It does NOT attempt to parse extended git headers (`diff --git …`, index lines,
/// mode lines). It works on the `---` / `+++` pairs produced by both `git diff`
/// and plain `diff -u` output, which is what diff2html receives.
public enum UnifiedDiffParser {

    /// Parse `rawDiff` into an ordered list of per-file `FileDiff` values.
    ///
    /// Files appear in the order they occur in `rawDiff`.
    /// An empty or non-diff string returns `[]`.
    ///
    /// Each returned `FileDiff` carries a `rawSlice` property containing only the
    /// portion of `rawDiff` that belongs to that file (from its `--- ` header up to,
    /// but not including, the next file's `--- ` header). This lets file cards
    /// render only their own hunk (Issue #44).
    public static func parse(_ rawDiff: String) -> [FileDiff] {
        let lines = rawDiff.components(separatedBy: "\n")
        var results: [FileDiff] = []

        // Track per-file slice boundaries using line indices.
        // sliceStart[k] = the index of the `---` line for the k-th file found.
        // After the loop we know sliceEnd[k] = sliceStart[k+1] (or EOF).

        // We collect (startLineIndex, FileDiff-without-slice) pairs, then
        // assemble slices in a second pass.
        struct Pending {
            let startLineIndex: Int  // index of the `---` header in `lines`
            let filename: String
            let status: FileDiff.Status
            let addedLines: Int
            let removedLines: Int
            let isBinary: Bool
        }
        var pending: [Pending] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Look for a `---` header line that starts a new file section.
            guard line.hasPrefix("--- ") else {
                i += 1
                continue
            }

            let fromPath = stripDiffPrefix(line.dropFirst(4))

            // The next line must be a `+++` header.
            let nextIndex = i + 1
            guard nextIndex < lines.count else { break }
            let nextLine = lines[nextIndex]
            guard nextLine.hasPrefix("+++ ") else {
                i += 1
                continue
            }

            let toPath = stripDiffPrefix(nextLine.dropFirst(4))

            // Determine status from the from/to paths.
            let isAdded   = fromPath == "/dev/null"
            let isRemoved = toPath   == "/dev/null"
            let status: FileDiff.Status = isAdded ? .added : isRemoved ? .removed : .modified

            // Canonical filename: prefer the non-null side, stripping the `a/` / `b/` prefix.
            let filename = isAdded ? toPath : fromPath

            // Record where this file's slice starts.
            let sliceStartIndex = i

            // Scan forward for the body lines of this file section.
            // Body ends when we hit the next `--- ` header or EOF.
            var addedCount   = 0
            var removedCount = 0
            var isBinary     = false

            var j = nextIndex + 1
            while j < lines.count {
                let bodyLine = lines[j]

                // Next file header — stop scanning this file's body.
                if bodyLine.hasPrefix("--- ") {
                    break
                }

                // Binary marker: "Binary files A and B differ"
                if bodyLine.hasPrefix("Binary files ") && bodyLine.hasSuffix(" differ") {
                    isBinary = true
                    j += 1
                    continue
                }

                // Count `+` / `-` hunk lines (exclude `+++` / `---` headers).
                if bodyLine.hasPrefix("+") && !bodyLine.hasPrefix("+++ ") {
                    addedCount += 1
                } else if bodyLine.hasPrefix("-") && !bodyLine.hasPrefix("--- ") {
                    removedCount += 1
                }

                j += 1
            }

            // Binary files have no meaningful line counts.
            if isBinary {
                addedCount   = 0
                removedCount = 0
            }

            pending.append(Pending(
                startLineIndex: sliceStartIndex,
                filename:       filename,
                status:         status,
                addedLines:     addedCount,
                removedLines:   removedCount,
                isBinary:       isBinary
            ))

            // Continue from where the inner scan stopped.
            i = j
        }

        // Second pass: build raw slices by joining lines[start..<end].
        for (idx, p) in pending.enumerated() {
            let endLineIndex = idx + 1 < pending.count ? pending[idx + 1].startLineIndex : lines.count
            // Join this file's lines back into a string, preserving the original "\n" separators.
            // We drop a trailing empty element that results from a trailing newline so the slice
            // mirrors the original structure faithfully.
            let sliceLines = Array(lines[p.startLineIndex ..< endLineIndex])
            // If the last line is an empty string caused by a trailing "\n" separator in the
            // original input, preserve it as-is (joined with "\n" it becomes a trailing newline).
            let rawSlice = sliceLines.joined(separator: "\n")

            results.append(FileDiff(
                filename:     p.filename,
                status:       p.status,
                addedLines:   p.addedLines,
                removedLines: p.removedLines,
                isBinary:     p.isBinary,
                rawSlice:     rawSlice
            ))
        }

        return results
    }

    // MARK: — Private helpers

    /// Strips the `a/` or `b/` prefix that `git diff` prepends to paths,
    /// and returns a plain path string. `/dev/null` is returned unchanged.
    private static func stripDiffPrefix(_ raw: some StringProtocol) -> String {
        let s = String(raw)
        if s == "/dev/null" { return s }
        if s.hasPrefix("a/") { return String(s.dropFirst(2)) }
        if s.hasPrefix("b/") { return String(s.dropFirst(2)) }
        return s
    }
}
