import DoscCore
import DoscUI
import SwiftUI

struct CommitRow: View {
    let commit: Commit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(
                url: commit.authorUser?.avatarURL, login: commit.authorUser?.login ?? commit.author.name, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(commit.authorUser?.login ?? commit.author.name)
                    if let date = commit.author.date { Text("· \(date.shortRelative)") }
                    Spacer()
                    Text(commit.shortID).font(.caption.monospaced())
                }
                .font(.caption)
                .foregroundStyle(Palette.fgMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

/// History of a branch (or of one path on it), grouped by day like the GitHub app.
struct CommitListView: View {
    let target: RepoTarget
    let account: Account
    let provider: any SourceControlProvider
    let revision: String?
    let path: String?
    @State private var list = PagedList<Commit>()

    var body: some View {
        PagedListView(list: list, emptyTitle: "No commits", emptySymbol: "clock", reload: reload) { item in
            NavigationLink(value: Route.commit(target, id: item.item.id)) {
                CommitRow(commit: item.item)
            }
        }
        .inlineTitle(path.map { "History · \(($0 as NSString).lastPathComponent)" } ?? "Commits")
        .toolbar {
            if let revision {
                ToolbarItem(placement: .status) {
                    SwiftUI.Label(revision, systemImage: "arrow.triangle.branch").font(.caption)
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        let (provider, repo, revision, path) = (provider, target.repo, revision, path)
        await list.load([
            .init(account: account) { cursor in
                try await provider.commits(repo, revision: revision, path: path, cursor: cursor)
            }
        ])
    }
}

struct CommitDetailView: View {
    let target: RepoTarget
    let provider: any SourceControlProvider
    let id: String
    @State private var detail = Loader<CommitDetail>()

    var body: some View {
        LoaderView(loader: detail, retry: load) { detail in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.commit.title).font(.headline)
                        if let body = detail.commit.body {
                            Text(body).font(.subheadline).foregroundStyle(Palette.fgMuted)
                        }
                        HStack(spacing: 8) {
                            AvatarView(
                                url: detail.commit.authorUser?.avatarURL,
                                login: detail.commit.authorUser?.login ?? detail.commit.author.name, size: 20)
                            Text(detail.commit.authorUser?.login ?? detail.commit.author.name).bold()
                            if let date = detail.commit.author.date {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(Palette.fgMuted)
                            }
                        }
                        .font(.caption)
                        Text(detail.commit.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Palette.fgMuted)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    FileChangesSummary(files: detail.files, additions: detail.additions, deletions: detail.deletions)
                }
                FileChangeSections(files: detail.files)
            }
            .listStyle(.plain)
        }
        .inlineTitle("Commit \(String(id.prefix(7)))")
        .toolbar {
            if let url = detail.value?.commit.webURL {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let (provider, repo, id) = (provider, target.repo, id)
        await detail.load { try await provider.commit(repo, id: id) }
    }
}

struct FileChangesSummary: View {
    let files: [FileChange]
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack {
            Text("\(files.count) file\(files.count == 1 ? "" : "s") changed").font(.subheadline.weight(.semibold))
            Spacer()
            DiffStat(additions: additions, deletions: deletions)
        }
    }
}

/// One collapsible section per changed file, with its diff.
struct FileChangeSections: View {
    let files: [FileChange]
    @State private var collapsed: Set<String> = []

    var body: some View {
        ForEach(files) { file in
            Section {
                if !collapsed.contains(file.id) {
                    if file.patch == nil {
                        Text(
                            file.status == .renamed && file.additions + file.deletions == 0
                                ? "File renamed without changes." : "Binary file or diff too large to show."
                        )
                        .font(.footnote)
                        .foregroundStyle(Palette.fgMuted)
                    } else {
                        DiffView(hunks: file.hunks)
                            .listRowInsets(EdgeInsets())
                    }
                }
            } header: {
                Button {
                    if collapsed.contains(file.id) { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: collapsed.contains(file.id) ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                        Image(systemName: statusIcon(file.status)).foregroundStyle(statusColor(file.status))
                        Text(file.previousPath.map { "\($0) → \(file.path)" } ?? file.path)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.head)
                            .foregroundStyle(Palette.fgDefault)
                        Spacer()
                        DiffStat(additions: file.additions, deletions: file.deletions)
                    }
                }
                .buttonStyle(.plain)
                .textCase(nil)
            }
        }
    }

    private func statusIcon(_ status: FileChange.Status) -> String {
        switch status {
        case .added: "plus.square"
        case .removed: "minus.square"
        case .renamed: "arrow.right.square"
        case .modified, .other: "dot.square"
        }
    }

    private func statusColor(_ status: FileChange.Status) -> Color {
        switch status {
        case .added: Palette.open
        case .removed: Palette.closed
        case .renamed: Palette.accent
        case .modified, .other: Palette.attention
        }
    }
}
