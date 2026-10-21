import Foundation

/// One line of a diff hunk.
public struct DiffLine: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case context, addition, deletion, noNewline }

    public let kind: Kind
    /// The line without its leading `+`, `-` or space.
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
}

/// One `@@ -a,b +c,d @@` section of a unified diff.
public struct DiffHunk: Hashable, Sendable {
    /// The whole `@@ … @@ section` line.
    public let header: String
    public let oldStart: Int
    public let newStart: Int
    public var lines: [DiffLine]
}

/// Parses unified diffs as produced by `git diff`, GitHub/GitLab APIs and `svn diff`.
public enum UnifiedDiffParser {
    /// Parses the hunks of one file's diff. Lines before the first `@@` (file headers) are skipped;
    /// malformed hunk headers end the parse instead of failing it.
    public static func parseHunks(_ patch: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var current: DiffHunk?
        var oldLine = 0
        var newLine = 0

        // Splitting on `isNewline` handles "\r\n", which Swift treats as one Character.
        for line in patch.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.hasPrefix("@@") {
                if let current { hunks.append(current) }
                guard let (o, n) = parseHeader(line) else {
                    current = nil
                    break
                }
                current = DiffHunk(header: String(line), oldStart: o, newStart: n, lines: [])
                oldLine = o
                newLine = n
                continue
            }
            guard current != nil else { continue }
            switch line.first {
            case "+":
                current?.lines.append(
                    DiffLine(kind: .addition, text: String(line.dropFirst()), oldNumber: nil, newNumber: newLine))
                newLine += 1
            case "-":
                current?.lines.append(
                    DiffLine(kind: .deletion, text: String(line.dropFirst()), oldNumber: oldLine, newNumber: nil))
                oldLine += 1
            case "\\":
                current?.lines.append(DiffLine(kind: .noNewline, text: String(line), oldNumber: nil, newNumber: nil))
            case " ":
                current?.lines.append(
                    DiffLine(
                        kind: .context, text: String(line.dropFirst()), oldNumber: oldLine, newNumber: newLine))
                oldLine += 1
                newLine += 1
            case nil:
                // A trailing empty line at the end of the patch isn't part of the hunk.
                continue
            default:
                // A new file header (multi-file diffs) ends the hunk.
                if let c = current { hunks.append(c) }
                current = nil
            }
        }
        if let current { hunks.append(current) }
        return hunks
    }

    /// Reads the old and new start lines from `@@ -a[,b] +c[,d] @@`.
    static func parseHeader(_ line: Substring) -> (Int, Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        func start(_ s: Substring) -> Int? { Int(s.dropFirst().split(separator: ",").first ?? "") }
        guard let o = start(parts[1]), let n = start(parts[2]) else { return nil }
        return (o, n)
    }
}
