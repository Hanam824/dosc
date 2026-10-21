import DoscCore
import SwiftUI

/// A round avatar loaded from a URL, with the first letter of the login as placeholder.
public struct AvatarView: View {
    let url: URL?
    let login: String
    let size: CGFloat
    /// Organizations have rounded-square avatars on GitHub.
    let square: Bool

    public init(url: URL?, login: String, size: CGFloat = 24, square: Bool = false) {
        self.url = url
        self.login = login
        self.size = size
        self.square = square
    }

    public init(_ user: UserSummary, size: CGFloat = 24) {
        self.init(url: user.avatarURL, login: user.login, size: size)
    }

    public var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Palette.canvasSubtle
                Text(login.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Palette.fgMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: square ? size * 0.2 : size / 2))
        .overlay(
            RoundedRectangle(cornerRadius: square ? size * 0.2 : size / 2)
                .strokeBorder(Palette.border.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

/// An SF Symbol on a colored rounded square, like the rows of the GitHub app's Home screen.
public struct IconTile: View {
    let systemName: String
    let color: Color

    public init(_ systemName: String, color: Color) {
        self.systemName = systemName
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

/// A label pill in the label's own color, with readable text on top.
public struct LabelChip: View {
    let label: DoscCore.Label

    public init(_ label: DoscCore.Label) { self.label = label }

    public var body: some View {
        let color = Color(hex: label.color)
        Text(label.name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(Self.isLight(label.color) ? Color.black.opacity(0.85) : Color.white)
            .background(color, in: Capsule())
    }

    /// Whether dark text reads better on this background (WCAG relative luminance).
    static func isLight(_ hex: String) -> Bool {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        func channel(_ c: UInt32) -> Double {
            let s = Double(c) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * channel((v >> 16) & 0xff) + 0.7152 * channel((v >> 8) & 0xff) + 0.0722 * channel(v & 0xff)
        return l > 0.4
    }
}

/// The icon and color GitHub uses for an issue or pull request in a given state.
public struct IssueStateIcon: View {
    let kind: IssueKind
    let state: IssueState
    let isDraft: Bool

    public init(kind: IssueKind, state: IssueState, isDraft: Bool = false) {
        self.kind = kind
        self.state = state
        self.isDraft = isDraft
    }

    public init(_ issue: Issue) {
        self.init(kind: issue.kind, state: issue.state, isDraft: issue.isDraft)
    }

    public var body: some View {
        Image(systemName: Self.symbol(kind: kind, state: state))
            .foregroundStyle(Self.color(kind: kind, state: state, isDraft: isDraft))
            .accessibilityLabel(Self.title(kind: kind, state: state, isDraft: isDraft))
    }

    public static func symbol(kind: IssueKind, state: IssueState) -> String {
        switch (kind, state) {
        case (.issue, .open): "smallcircle.filled.circle"
        case (.issue, _): "checkmark.circle"
        case (.changeRequest, .merged): "arrow.triangle.merge"
        case (.changeRequest, .closed): "xmark.circle"
        case (.changeRequest, .open): "arrow.triangle.pull"
        }
    }

    public static func color(kind: IssueKind, state: IssueState, isDraft: Bool) -> Color {
        if isDraft && state == .open { return Palette.neutral }
        switch (kind, state) {
        case (_, .open): return Palette.open
        case (.issue, _): return Palette.done
        case (.changeRequest, .merged): return Palette.done
        case (.changeRequest, _): return Palette.closed
        }
    }

    public static func title(kind: IssueKind, state: IssueState, isDraft: Bool) -> String {
        if isDraft && state == .open { return "Draft" }
        switch state {
        case .open: return "Open"
        case .closed: return "Closed"
        case .merged: return "Merged"
        }
    }
}

/// The colored "Open"/"Closed"/"Merged" pill shown at the top of an issue or pull request.
public struct StateBadge: View {
    let issue: Issue

    public init(_ issue: Issue) { self.issue = issue }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: IssueStateIcon.symbol(kind: issue.kind, state: issue.state))
            Text(IssueStateIcon.title(kind: issue.kind, state: issue.state, isDraft: issue.isDraft))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            IssueStateIcon.color(kind: issue.kind, state: issue.state, isDraft: issue.isDraft), in: Capsule())
    }
}

/// A small badge naming the account an item comes from, shown when several accounts are mixed.
public struct AccountBadge: View {
    let account: Account

    public init(_ account: Account) { self.account = account }

    public var body: some View {
        HStack(spacing: 3) {
            AvatarView(url: account.avatarURL, login: account.login, size: 12)
            Text(account.label)
        }
        .font(.caption2)
        .foregroundStyle(Palette.fgMuted)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Palette.canvasSubtle, in: Capsule())
        .accessibilityLabel("Account \(account.label)")
    }
}

/// The repository name as `owner / name` with the name in bold.
public struct RepoNameText: View {
    let repo: RepoRef

    public init(_ repo: RepoRef) { self.repo = repo }

    public var body: some View {
        if repo.owner.isEmpty {
            Text(repo.name).bold()
        } else {
            Text("\(Text(repo.owner).foregroundStyle(Palette.fgMuted)) / \(Text(repo.name).bold())")
        }
    }
}

/// A full-screen message for empty lists and errors.
public struct MessageView: View {
    let systemImage: String
    let title: String
    let message: String?
    let retry: (() -> Void)?

    public init(systemImage: String, title: String, message: String? = nil, retry: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            SwiftUI.Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let retry { Button("Try Again", action: retry).buttonStyle(.bordered) }
        }
    }
}

extension Date {
    /// "5m", "3h", "2d", or a short date for older ones, like the GitHub app.
    public var shortRelative: String {
        let seconds = Date.now.timeIntervalSince(self)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(86400 * 30): return "\(Int(seconds / 86400))d"
        default: return formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
        }
    }
}

extension Int {
    /// 1234 → "1.2k".
    public var compact: String {
        formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}
