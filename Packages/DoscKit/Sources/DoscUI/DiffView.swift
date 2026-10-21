import DoscCore
import SwiftUI

/// One file's diff with old/new line numbers and GitHub's red/green backgrounds. Long lines
/// scroll sideways instead of wrapping, so the code keeps its shape.
public struct DiffView: View {
    let hunks: [DiffHunk]

    public init(hunks: [DiffHunk]) { self.hunks = hunks }

    public var body: some View {
        let width = numberWidth
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                    Text(hunk.header)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.fgMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.hunkBackground)
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line, numberWidth: width)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, alignment: .leading)
        }
        .background(Palette.canvasDefault)
    }

    private var numberWidth: CGFloat {
        let maxLine = hunks.flatMap(\.lines).compactMap { max($0.oldNumber ?? 0, $0.newNumber ?? 0) }.max() ?? 0
        return CGFloat(max(String(maxLine).count, 2)) * 8 + 8
    }
}

struct DiffLineRow: View {
    let line: DiffLine
    let numberWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(marker + line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(line.kind == .noNewline ? Palette.fgMuted : Palette.fgDefault)
                .padding(.horizontal, 6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        case .noNewline: ""
        }
    }

    private func number(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Palette.fgMuted)
            .frame(width: numberWidth, alignment: .trailing)
            .padding(.trailing, 4)
            .background(numberBackground)
    }

    private var background: Color {
        switch line.kind {
        case .addition: Palette.additionBackground
        case .deletion: Palette.deletionBackground
        default: .clear
        }
    }

    private var numberBackground: Color {
        switch line.kind {
        case .addition: Palette.additionNumberBackground
        case .deletion: Palette.deletionNumberBackground
        default: .clear
        }
    }
}

/// "+12 −3" with GitHub's five little squares.
public struct DiffStat: View {
    let additions: Int
    let deletions: Int

    public init(additions: Int, deletions: Int) {
        self.additions = additions
        self.deletions = deletions
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text("+\(additions)").foregroundStyle(Palette.open)
            Text("−\(deletions)").foregroundStyle(Palette.closed)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(at: i))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(additions) additions, \(deletions) deletions")
    }

    private func color(at i: Int) -> Color {
        let total = additions + deletions
        guard total > 0 else { return Palette.border }
        let green = Int((Double(additions) / Double(total) * 5).rounded())
        let red = min(5 - green, Int((Double(deletions) / Double(total) * 5).rounded()))
        if i < green { return Palette.open }
        if i < green + red { return Palette.closed }
        return Palette.border
    }
}
