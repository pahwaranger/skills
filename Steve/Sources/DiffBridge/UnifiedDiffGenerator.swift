import Foundation

// MARK: — UnifiedDiffGenerator
//
// Generates a unified-diff string from two file sets: the INSTALLED (old/left) side
// and the ORIGIN (new/right) side for a single skill.
//
// Direction:
//   installed = OLD side (--- a/…, - lines)
//   origin    = NEW side (+++ b/…, + lines)
//
// A `+` line is what an Update would *add* to the user's installed skill.
//
// Algorithm: Wagner-Fischer LCS table for line-level diff (O(n*m) space/time).
// For production-size skill files (typically <1000 lines each) this is fast enough.

public enum UnifiedDiffGenerator {

    // MARK: — Public API

    /// Generates a unified-diff string covering all files in the union of `installed`
    /// and `origin`.
    ///
    /// - Parameters:
    ///   - installed: Files currently on disk in `~/.claude/skills/<skillName>/`.
    ///                Keys are relative file names (e.g. `"SKILL.md"`).
    ///   - origin:    Files from the origin snapshot (`ReviewSession.skillFiles[skillName]`).
    ///                Keys are relative file names.
    ///   - skillName: The skill directory name, used to build `a/<skillName>/…` paths.
    /// - Returns: A concatenated unified-diff string suitable for `UnifiedDiffParser` and
    ///            diff2html. Unchanged files are omitted. Empty string when no differences.
    public static func generate(
        installed: [String: Data],
        origin: [String: Data],
        skillName: String
    ) -> String {
        let allFiles = Set(installed.keys).union(origin.keys).sorted()

        var parts: [String] = []
        for filename in allFiles {
            if let chunk = diffChunk(
                filename: filename,
                skillName: skillName,
                installedData: installed[filename],
                originData: origin[filename]
            ) {
                parts.append(chunk)
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: — Per-file dispatch

    private static func diffChunk(
        filename: String,
        skillName: String,
        installedData: Data?,
        originData: Data?
    ) -> String? {
        let aPath = "a/\(skillName)/\(filename)"
        let bPath = "b/\(skillName)/\(filename)"

        switch (installedData, originData) {
        case (nil, nil):
            return nil

        case (nil, let newData?):
            // File only in origin → Added
            if isBinary(newData) {
                return binaryMarker(from: "/dev/null", to: bPath, aPath: aPath, bPath: bPath)
            }
            return addedFileDiff(data: newData, fromHeader: "/dev/null", toHeader: bPath,
                                 aPath: aPath, bPath: bPath)

        case (let oldData?, nil):
            // File only in installed → Removed
            if isBinary(oldData) {
                return binaryMarker(from: aPath, to: "/dev/null", aPath: aPath, bPath: bPath)
            }
            return removedFileDiff(data: oldData, fromHeader: aPath, toHeader: "/dev/null",
                                   aPath: aPath, bPath: bPath)

        case (let oldData?, let newData?):
            return modifiedFileDiff(oldData: oldData, newData: newData, aPath: aPath, bPath: bPath)
        }
    }

    // MARK: — Added file (all lines are insertions)

    private static func addedFileDiff(data: Data, fromHeader: String, toHeader: String,
                                       aPath: String, bPath: String) -> String {
        let lines = textLines(from: data)
        var body = "@@ -0,0 +1,\(lines.count) @@\n"
        body += lines.map { "+\($0)\n" }.joined()
        return "--- \(fromHeader)\n+++ \(toHeader)\n\(body)"
    }

    // MARK: — Removed file (all lines are deletions)

    private static func removedFileDiff(data: Data, fromHeader: String, toHeader: String,
                                         aPath: String, bPath: String) -> String {
        let lines = textLines(from: data)
        var body = "@@ -1,\(lines.count) +0,0 @@\n"
        body += lines.map { "-\($0)\n" }.joined()
        return "--- \(fromHeader)\n+++ \(toHeader)\n\(body)"
    }

    // MARK: — Modified file (LCS diff)

    private static func modifiedFileDiff(oldData: Data, newData: Data,
                                          aPath: String, bPath: String) -> String? {
        let oldBin = isBinary(oldData)
        let newBin = isBinary(newData)

        if oldBin || newBin {
            if oldData == newData { return nil }
            return binaryMarker(from: aPath, to: bPath, aPath: aPath, bPath: bPath)
        }

        if oldData == newData { return nil }

        let oldLines = textLines(from: oldData)
        let newLines = textLines(from: newData)

        let script = lcsDiff(old: oldLines, new: newLines)
        let hunks  = buildHunks(script: script, oldCount: oldLines.count,
                                 newCount: newLines.count, context: 3)
        guard !hunks.isEmpty else { return nil }

        var output = "--- \(aPath)\n+++ \(bPath)\n"
        for hunk in hunks {
            output += formatHunk(hunk, old: oldLines, new: newLines)
        }
        return output
    }

    // MARK: — Binary marker

    private static func binaryMarker(from: String, to: String, aPath: String, bPath: String) -> String {
        "--- \(from)\n+++ \(to)\nBinary files \(aPath) and \(bPath) differ\n"
    }

    // MARK: — Binary detection

    /// Returns `true` if `data` is not valid UTF-8 or contains a NUL byte.
    static func isBinary(_ data: Data) -> Bool {
        if data.contains(0x00) { return true }
        return String(data: data, encoding: .utf8) == nil
    }

    // MARK: — Text helpers

    private static func textLines(from data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
        if trimmed.isEmpty { return [] }
        return trimmed.components(separatedBy: "\n")
    }

    // MARK: — LCS diff (Wagner-Fischer)

    /// An edit operation in the edit script.
    fileprivate enum DiffOp {
        case equal(oldIdx: Int, newIdx: Int)
        case delete(oldIdx: Int)
        case insert(newIdx: Int)
    }

    /// Computes a line-level diff using the Wagner-Fischer LCS algorithm.
    /// Returns operations in document order (top to bottom).
    private static func lcsDiff(old: [String], new: [String]) -> [DiffOp] {
        let n = old.count
        let m = new.count

        if n == 0 { return (0 ..< m).map { .insert(newIdx: $0) } }
        if m == 0 { return (0 ..< n).map { .delete(oldIdx: $0) } }

        // dp[i][j] = length of LCS of old[0..<i], new[0..<j]
        // We use flat arrays for performance.
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)

        for i in 1 ... n {
            for j in 1 ... m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to build edit script
        var script: [DiffOp] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
                script.append(.equal(oldIdx: i - 1, newIdx: j - 1))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                script.append(.insert(newIdx: j - 1))
                j -= 1
            } else {
                script.append(.delete(oldIdx: i - 1))
                i -= 1
            }
        }
        script.reverse()
        return script
    }

    // MARK: — Hunk building

    private struct HunkDef {
        let oldStart: Int   // 0-based, inclusive
        let oldEnd: Int     // 0-based, exclusive
        let newStart: Int
        let newEnd: Int
        let ops: [DiffOp]
    }

    private static func buildHunks(script: [DiffOp], oldCount: Int, newCount: Int, context: Int) -> [HunkDef] {
        // Find indices of changed operations (delete / insert).
        var changedPositions: [(oldIdx: Int, newIdx: Int)] = []
        for op in script {
            switch op {
            case .delete(let oi): changedPositions.append((oi, -1))
            case .insert(let ni): changedPositions.append((-1, ni))
            case .equal:          break
            }
        }
        guard !changedPositions.isEmpty else { return [] }

        // Compute hunk windows: group changes that are within 2*context of each other.
        struct HunkWindow {
            var oldStart: Int
            var oldEnd: Int   // exclusive
            var newStart: Int
            var newEnd: Int
        }

        var windows: [HunkWindow] = []
        var current = HunkWindow(
            oldStart: max(0, firstOld(changedPositions[0]) - context),
            oldEnd:   min(oldCount, firstOld(changedPositions[0]) + 1 + context),
            newStart: max(0, firstNew(changedPositions[0]) - context),
            newEnd:   min(newCount, firstNew(changedPositions[0]) + 1 + context)
        )

        for pos in changedPositions.dropFirst() {
            let posOld = firstOld(pos)
            let posNew = firstNew(pos)
            // Distance from the end of the current window to this change.
            let gapOld = posOld >= 0 ? posOld - current.oldEnd : 0
            let gapNew = posNew >= 0 ? posNew - current.newEnd : 0
            let gap = max(gapOld, gapNew)

            if gap <= context {
                // Extend current window.
                if posOld >= 0 { current.oldEnd = min(oldCount, posOld + 1 + context) }
                if posNew >= 0 { current.newEnd = min(newCount, posNew + 1 + context) }
            } else {
                windows.append(current)
                current = HunkWindow(
                    oldStart: max(0, (posOld >= 0 ? posOld : current.oldEnd) - context),
                    oldEnd:   min(oldCount, (posOld >= 0 ? posOld : current.oldEnd) + 1 + context),
                    newStart: max(0, (posNew >= 0 ? posNew : current.newEnd) - context),
                    newEnd:   min(newCount, (posNew >= 0 ? posNew : current.newEnd) + 1 + context)
                )
            }
        }
        windows.append(current)

        // For each window, collect relevant ops.
        return windows.map { win in
            let ops = script.filter { op in
                switch op {
                case .equal(let oi, let ni):
                    return oi >= win.oldStart && oi < win.oldEnd && ni >= win.newStart && ni < win.newEnd
                case .delete(let oi):
                    return oi >= win.oldStart && oi < win.oldEnd
                case .insert(let ni):
                    return ni >= win.newStart && ni < win.newEnd
                }
            }
            return HunkDef(oldStart: win.oldStart, oldEnd: win.oldEnd,
                           newStart: win.newStart, newEnd: win.newEnd,
                           ops: ops)
        }
    }

    private static func firstOld(_ pos: (oldIdx: Int, newIdx: Int)) -> Int { pos.oldIdx }
    private static func firstNew(_ pos: (oldIdx: Int, newIdx: Int)) -> Int { pos.newIdx }

    // MARK: — Hunk formatting

    private static func formatHunk(_ hunk: HunkDef, old: [String], new: [String]) -> String {
        let oldCount = hunk.oldEnd - hunk.oldStart
        let newCount = hunk.newEnd - hunk.newStart
        let oldStartDisp = oldCount == 0 ? hunk.oldStart : hunk.oldStart + 1
        let newStartDisp = newCount == 0 ? hunk.newStart : hunk.newStart + 1

        var header = "@@ -\(oldStartDisp)"
        if oldCount != 1 { header += ",\(oldCount)" }
        header += " +\(newStartDisp)"
        if newCount != 1 { header += ",\(newCount)" }
        header += " @@\n"

        var body = ""
        for op in hunk.ops {
            switch op {
            case .equal(let oi, _): body += " \(old[oi])\n"
            case .delete(let oi):   body += "-\(old[oi])\n"
            case .insert(let ni):   body += "+\(new[ni])\n"
            }
        }
        return header + body
    }
}
