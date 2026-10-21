import DoscCore
import DoscUI
import SwiftUI

struct RepoRow: View {
    let repo: Repo
    let account: Account?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(repo.owner, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RepoNameText(repo.ref).lineLimit(1)
                    if repo.isPrivate {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.fgMuted)
                    }
                }
                if let summary = repo.summary, !summary.isEmpty {
                    Text(summary).font(.subheadline).foregroundStyle(Palette.fgMuted).lineLimit(2)
                }
                HStack(spacing: 12) {
                    SwiftUI.Label(repo.stars.compact, systemImage: "star")
                    if let language = repo.language {
                        HStack(spacing: 4) {
                            Circle().fill(LanguageColor.color(for: language)).frame(width: 9, height: 9)
                            Text(language)
                        }
                    }
                    if let account { AccountBadge(account) }
                }
                .font(.caption)
                .foregroundStyle(Palette.fgMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RepoListView: View {
    let kind: RepoListKind
    @Environment(AppModel.self) private var app
    @State private var list = PagedList<Repo>(areInOrder: {
        ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
    })

    var body: some View {
        PagedListView(list: list, emptyTitle: "No repositories", emptySymbol: "book.closed", reload: reload) { item in
            NavigationLink(value: Route.repo(RepoTarget(accountID: item.account.id, repo: item.item.ref))) {
                RepoRow(repo: item.item, account: app.showsAccountBadges ? item.account : nil)
            }
        }
        .inlineTitle(kind == .mine ? "Repositories" : "Starred")
        .task(id: app.selection) { await reload() }
    }

    private func reload() async {
        let kind = kind
        await list.load(
            sources(app, needs: kind == .starred ? .starred : nil) { provider, cursor in
                kind == .mine
                    ? try await provider.repositories(cursor: cursor)
                    : try await provider.starredRepositories(cursor: cursor)
            })
    }
}

/// A repository's front page: header, shortcuts to issues/PRs/code/commits, branch picker, README.
struct RepoView: View {
    let target: RepoTarget
    let account: Account
    let provider: any SourceControlProvider
    @Environment(AppModel.self) private var app
    @State private var repo = Loader<Repo>()
    @State private var readme = Loader<FileContent?>()
    @State private var branches: [Branch] = []
    @State private var revision: String?

    var body: some View {
        LoaderView(loader: repo, retry: load) { repo in
            List {
                Section { header(repo) }
                Section {
                    if provider.capabilities.contains(.issues) {
                        NavigationLink(value: Route.repoIssues(target, .issue)) {
                            shortcut("Issues", icon: "smallcircle.filled.circle", color: Palette.homeIssues)
                        }
                    }
                    if provider.capabilities.contains(.changeRequests) {
                        NavigationLink(value: Route.repoIssues(target, .changeRequest)) {
                            shortcut("Pull Requests", icon: "arrow.triangle.pull", color: Palette.homePulls)
                        }
                    }
                    NavigationLink(value: Route.commits(target, revision: currentRevision(repo), path: nil)) {
                        shortcut("Commits", icon: "clock.arrow.circlepath", color: Palette.homeActivity)
                    }
                    NavigationLink(value: Route.tree(target, path: "", revision: currentRevision(repo))) {
                        shortcut("Browse Code", icon: "chevron.left.forwardslash.chevron.right", color: Palette.neutral)
                    }
                }
                if !branches.isEmpty {
                    Section {
                        Picker(selection: $revision) {
                            ForEach(branches) { branch in
                                Text(branch.name).tag(Optional(branch.name))
                            }
                        } label: {
                            SwiftUI.Label("Branch", systemImage: "arrow.triangle.branch")
                        }
                    }
                }
                Section("README") {
                    LoaderView(loader: readme, retry: loadReadme) { file in
                        if let file, let text = file.text {
                            MarkdownText(text, baseURL: file.assetBaseURL)
                        } else {
                            Text("This repository has no README.").foregroundStyle(Palette.fgMuted)
                        }
                    }
                    .frame(minHeight: 60)
                }
            }
            #if os(iOS)
                .listStyle(.insetGrouped)
            #endif
            .refreshable { await load() }
        }
        .inlineTitle(target.repo.name)
        .toolbar {
            if let url = repo.value?.webURL {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
        .task { await load() }
        .task(id: revision) { await loadReadme() }
    }

    private func currentRevision(_ repo: Repo) -> String? { revision ?? repo.defaultBranch }

    private func header(_ repo: Repo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AvatarView(repo.owner, size: 22)
                Text(repo.ref.owner).foregroundStyle(Palette.fgMuted)
                if app.showsAccountBadges { Spacer(); AccountBadge(account) }
            }
            Text(repo.ref.name).font(.title2.bold())
            if let summary = repo.summary, !summary.isEmpty { Text(summary) }
            HStack(spacing: 16) {
                SwiftUI.Label("\(repo.stars.compact) stars", systemImage: "star")
                SwiftUI.Label("\(repo.forks.compact) forks", systemImage: "tuningfork")
                if repo.isPrivate { SwiftUI.Label("Private", systemImage: "lock") }
            }
            .font(.footnote)
            .foregroundStyle(Palette.fgMuted)
        }
        .padding(.vertical, 4)
    }

    private func shortcut(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(icon, color: color)
            Text(title)
        }
    }

    private func load() async {
        let provider = provider
        let ref = target.repo
        await repo.load { try await provider.repository(ref) }
        app.noteOpened(ref, accountID: target.accountID)
        if revision == nil { revision = repo.value?.defaultBranch }
        if provider.capabilities.contains(.branches),
            let page = try? await provider.branches(ref, cursor: nil)
        {
            var list = page.items
            if let current = revision, !list.contains(where: { $0.name == current }) {
                list.insert(Branch(name: current), at: 0)
            }
            branches = list
        }
    }

    private func loadReadme() async {
        guard repo.value != nil else { return }
        let provider = provider
        let ref = target.repo
        let rev = revision
        await readme.load { try await provider.readme(ref, revision: rev) }
    }
}

/// Repository search on the active accounts.
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var list = PagedList<Repo>(areInOrder: { $0.stars > $1.stars })
    @State private var searched = false

    var body: some View {
        Group {
            if searched {
                PagedListView(list: list, emptyTitle: "No results", emptySymbol: "magnifyingglass", reload: search) {
                    item in
                    NavigationLink(value: Route.repo(RepoTarget(accountID: item.account.id, repo: item.item.ref))) {
                        RepoRow(repo: item.item, account: app.showsAccountBadges ? item.account : nil)
                    }
                }
            } else {
                MessageView(
                    systemImage: "magnifyingglass", title: "Search repositories",
                    message: "Search public repositories and the private ones your accounts can see.")
            }
        }
        .navigationTitle("Explore")
        .searchable(text: $query, prompt: "Repositories")
        .onSubmit(of: .search) { Task { await search() } }
        .accountSwitcher(app)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searched = true
        await list.load(
            sources(app, needs: .search) { provider, cursor in
                try await provider.searchRepositories(query: q, cursor: cursor)
            })
    }
}
