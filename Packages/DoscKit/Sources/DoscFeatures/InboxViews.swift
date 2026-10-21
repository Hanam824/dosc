import DoscCore
import DoscUI
import SwiftUI

/// The Notifications tab: unread (or all) notifications of the active accounts, newest first.
struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @State private var includeRead = false
    @State private var list = PagedList<NotificationItem>(areInOrder: { $0.updatedAt > $1.updatedAt })

    var body: some View {
        PagedListView(
            list: list, emptyTitle: includeRead ? "No notifications" : "All caught up",
            emptySymbol: "bell.slash", reload: reload
        ) { item in
            NavigationLink(value: route(item)) { row(item) }
        }
        .safeAreaInset(edge: .top) {
            Picker("Show", selection: $includeRead) {
                Text("Unread").tag(false)
                Text("All").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .navigationTitle("Notifications")
        .accountSwitcher(app)
        .task(id: TaskKey(includeRead: includeRead, selection: app.selection)) { await reload() }
    }

    private struct TaskKey: Hashable {
        let includeRead: Bool
        let selection: AccountSelection
    }

    private func route(_ item: Sourced<NotificationItem>) -> Route {
        let target = RepoTarget(accountID: item.account.id, repo: item.item.repo)
        if let number = item.item.number {
            return .issue(target, number: number, kind: item.item.subject == .changeRequest ? .changeRequest : .issue)
        }
        return .repo(target)
    }

    private func row(_ item: Sourced<NotificationItem>) -> some View {
        let n = item.item
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(n.subject))
                .foregroundStyle(n.isUnread ? Palette.accent : Palette.fgMuted)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(n.number.map { "\(n.repo.path) #\($0)" } ?? n.repo.path).lineLimit(1)
                    Spacer()
                    Text(n.updatedAt.shortRelative)
                }
                .font(.caption)
                .foregroundStyle(Palette.fgMuted)
                Text(n.title)
                    .font(.subheadline.weight(n.isUnread ? .semibold : .regular))
                    .lineLimit(3)
                HStack {
                    Text(n.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .foregroundStyle(Palette.fgMuted)
                    Spacer()
                    if app.showsAccountBadges { AccountBadge(item.account) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(_ subject: NotificationItem.Subject) -> String {
        switch subject {
        case .issue: "smallcircle.filled.circle"
        case .changeRequest: "arrow.triangle.pull"
        case .commit: "point.topleft.down.to.point.bottomright.curvepath"
        case .release: "tag"
        case .discussion: "bubble.left.and.bubble.right"
        case .checks: "checkmark.seal"
        case .other: "bell"
        }
    }

    private func reload() async {
        let includeRead = includeRead
        await list.load(
            sources(app, needs: .notifications) { provider, cursor in
                try await provider.notifications(includeRead: includeRead, cursor: cursor)
            })
    }
}

/// Activity of people and repositories the active accounts follow.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @State private var list = PagedList<FeedEvent>(areInOrder: { $0.createdAt > $1.createdAt })

    var body: some View {
        PagedListView(list: list, emptyTitle: "No activity", emptySymbol: "waveform.path.ecg", reload: reload) { item in
            NavigationLink(value: route(item)) { row(item) }
        }
        .inlineTitle("Activity")
        .task(id: app.selection) { await reload() }
    }

    private func route(_ item: Sourced<FeedEvent>) -> Route {
        let target = RepoTarget(accountID: item.account.id, repo: item.item.repo)
        if let number = item.item.number, [.issue, .changeRequest, .comment].contains(item.item.kind) {
            return .issue(target, number: number, kind: item.item.kind == .changeRequest ? .changeRequest : .issue)
        }
        return .repo(target)
    }

    private func row(_ item: Sourced<FeedEvent>) -> some View {
        let e = item.item
        return HStack(alignment: .top, spacing: 10) {
            AvatarView(e.actor, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(e.actor.login).bold()) \(e.summary) \(Text(e.repo.path).bold())")
                    .font(.subheadline)
                if let detail = e.detail {
                    Text(detail).font(.caption).foregroundStyle(Palette.fgMuted).lineLimit(3)
                }
                HStack {
                    Text(e.createdAt.shortRelative).font(.caption).foregroundStyle(Palette.fgMuted)
                    Spacer()
                    if app.showsAccountBadges { AccountBadge(item.account) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        await list.load(sources(app, needs: .feed) { provider, cursor in try await provider.feed(cursor: cursor) })
    }
}
