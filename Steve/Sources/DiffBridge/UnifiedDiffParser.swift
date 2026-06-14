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

    public init(
        filename: String,
        status: Status,
        addedLines: Int,
        removedLines: Int,
        isBinary: Bool
    ) {
        self.filename     = filename
        self.status       = status
        self.addedLines   = addedLines
        self.removedLines = removedLines
        self.isBinary     = isBinary
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
    public static func parse(_ rawDiff: String) -> [FileDiff] {
        let lines = rawDiff.components(separatedBy: "\n")
        var results: [FileDiff] = []

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

                // Count `+` / `-` hunk lines (exclude `+++` / `---` headers which start with `+++ ` / `--- `).
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

            results.append(FileDiff(
                filename:     filename,
                status:       status,
                addedLines:   addedCount,
                removedLines: removedCount,
                isBinary:     isBinary
            ))

            // Continue from where the inner scan stopped.
            i = j
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
