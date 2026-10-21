import DoscCore
import DoscUI
import SwiftUI

struct IssueRow: View {
    let issue: Issue
    let account: Account?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IssueStateIcon(issue).font(.body).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(issue.repo.path) #\(issue.number)").lineLimit(1)
                    Spacer()
                    Text(issue.updatedAt.shortRelative)
                }
                .font(.caption)
                .foregroundStyle(Palette.fgMuted)
                Text(issue.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                if !issue.labels.isEmpty || issue.commentCount > 0 || account != nil {
                    HStack(spacing: 4) {
                        ForEach(issue.labels.prefix(3)) { LabelChip($0) }
                        if issue.labels.count > 3 {
                            Text("+\(issue.labels.count - 3)").font(.caption).foregroundStyle(Palette.fgMuted)
                        }
                        Spacer(minLength: 0)
                        if let account { AccountBadge(account) }
                        if issue.commentCount > 0 {
                            SwiftUI.Label("\(issue.commentCount)", systemImage: "bubble.left")
                                .font(.caption)
                                .foregroundStyle(Palette.fgMuted)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Issues or pull requests, either in one repository or involving the active accounts.
struct IssueListView: View {
    let kind: IssueKind
    /// `nil` lists items involving the active accounts across repositories.
    let target: RepoTarget?
    @Environment(AppModel.self) private var app
    @State private var state: IssueState = .open
    @State private var list = PagedList<Issue>(areInOrder: { $0.updatedAt > $1.updatedAt })

    var body: some View {
        PagedListView(
            list: list, emptyTitle: "Nothing \(state == .open ? "open" : "closed")",
            emptySymbol: IssueStateIcon.symbol(kind: kind, state: state), reload: reload
        ) { item in
            NavigationLink(
                value: Route.issue(
                    RepoTarget(accountID: item.account.id, repo: item.item.repo), number: item.item.number,
                    kind: item.item.kind)
            ) {
                IssueRow(issue: item.item, account: target == nil && app.showsAccountBadges ? item.account : nil)
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("State", selection: $state) {
                Text("Open").tag(IssueState.open)
                Text("Closed").tag(IssueState.closed)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .inlineTitle(kind == .issue ? "Issues" : "Pull Requests")
        .task(id: TaskKey(state: state, selection: app.selection)) { await reload() }
    }

    private struct TaskKey: Hashable {
        let state: IssueState
        let selection: AccountSelection
    }

    private func reload() async {
        let capability: Capability = kind == .issue ? .issues : .changeRequests
        let query: IssueQuery
        let list: [PagedList<Issue>.Source]
        if let target {
            query = IssueQuery(scope: .repo(target.repo), kind: kind, state: state)
            if let account = app.account(target.accountID), let provider = app.provider(for: account) {
                list = [.init(account: account) { cursor in try await provider.issues(query, cursor: cursor) }]
            } else {
                list = []
            }
        } else {
            query = IssueQuery(scope: .involvingMe, kind: kind, state: state)
            list = sources(app, needs: capability) { provider, cursor in
                try await provider.issues(query, cursor: cursor)
            }
        }
        await self.list.load(list)
    }
}

/// An issue or pull request. Pull requests get Files and Commits tabs next to the conversation.
struct IssueDetailView: View {
    enum Tab: Hashable { case conversation, files, commits }

    let target: RepoTarget
    let account: Account
    let provider: any SourceControlProvider
    let number: Int
    let kind: IssueKind
    @State private var issue = Loader<Issue>()
    @State private var comments = PagedList<Comment>()
    @State private var files = PagedList<FileChange>()
    @State private var commits = PagedList<Commit>()
    @State private var tab: Tab = .conversation

    var body: some View {
        VStack(spacing: 0) {
            if kind == .changeRequest {
                Picker("Section", selection: $tab) {
                    Text("Conversation").tag(Tab.conversation)
                    Text("Files").tag(Tab.files)
                    Text("Commits").tag(Tab.commits)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            switch tab {
            case .conversation: conversation
            case .files: filesTab
            case .commits:
                PagedListView(list: commits, emptyTitle: "No commits", emptySymbol: "clock", reload: loadCommits) {
                    item in
                    NavigationLink(value: Route.commit(target, id: item.item.id)) { CommitRow(commit: item.item) }
                }
                .task { if case .idle = commits.phase { await loadCommits() } }
            }
        }
        .inlineTitle("\(target.repo.name) #\(number)")
        .toolbar {
            if let url = issue.value?.webURL {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
        .task { await load() }
    }

    private var conversation: some View {
        LoaderView(loader: issue, retry: load) { issue in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink(value: Route.repo(target)) {
                            RepoNameText(issue.repo).font(.subheadline)
                        }
                        Text(issue.title).font(.title3.bold())
                        HStack(spacing: 8) {
                            StateBadge(issue)
                            if let cr = issue.changeRequest, !cr.sourceBranch.isEmpty {
                                Text("\(cr.sourceBranch) → \(cr.targetBranch)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.fgMuted)
                                    .lineLimit(2)
                            }
                        }
                        if !issue.labels.isEmpty {
                            FlowLayout(spacing: 4) { ForEach(issue.labels) { LabelChip($0) } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    CommentView(
                        author: issue.author, date: issue.createdAt,
                        markdown: (issue.body ?? "").isEmpty ? "_No description provided._" : issue.body!)
                }
                ForEach(comments.items) { item in
                    Section {
                        CommentView(author: item.item.author, date: item.item.createdAt, markdown: item.item.body)
                            .onAppear {
                                if item.id == comments.items.last?.id { Task { await comments.loadMore() } }
                            }
                    }
                }
                if case .loading = comments.phase {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .refreshable { await load() }
        }
    }

    private var filesTab: some View {
        Group {
            switch files.phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                MessageView(
                    systemImage: "exclamationmark.triangle", title: "Couldn't load", message: message,
                    retry: { Task { await loadFiles() } })
            case .loaded:
                let changes = files.items.map(\.item)
                List {
                    Section {
                        FileChangesSummary(
                            files: changes, additions: changes.reduce(0) { $0 + $1.additions },
                            deletions: changes.reduce(0) { $0 + $1.deletions })
                    }
                    FileChangeSections(files: changes)
                    if files.hasMore {
                        Button("Load more files") { Task { await files.loadMore() } }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { if case .idle = files.phase { await loadFiles() } }
    }

    private func load() async {
        let (provider, repo, number, kind) = (provider, target.repo, number, kind)
        async let loadIssue: Void = issue.load { try await provider.issue(repo, number: number, kind: kind) }
        async let loadComments: Void = comments.load([
            .init(account: account) { cursor in try await provider.comments(repo, number: number, cursor: cursor) }
        ])
        _ = await (loadIssue, loadComments)
    }

    private func loadFiles() async {
        let (provider, repo, number) = (provider, target.repo, number)
        await files.load([
            .init(account: account) { cursor in
                try await provider.changeRequestFiles(repo, number: number, cursor: cursor)
            }
        ])
    }

    private func loadCommits() async {
        let (provider, repo, number) = (provider, target.repo, number)
        await commits.load([
            .init(account: account) { cursor in
                try await provider.changeRequestCommits(repo, number: number, cursor: cursor)
            }
        ])
    }
}

struct CommentView: View {
    let author: UserSummary
    let date: Date
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(author, size: 24)
                Text(author.login).font(.subheadline.bold())
                Text(date.shortRelative).font(.caption).foregroundStyle(Palette.fgMuted)
            }
            MarkdownText(markdown)
        }
        .padding(.vertical, 4)
    }
}

/// Lays children out in rows, wrapping like text. Used for label chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
