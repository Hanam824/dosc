import DoscCore
import DoscUI
import SwiftUI

/// A repository on a given account.
public struct RepoTarget: Hashable, Sendable {
    public let accountID: UUID
    public let repo: RepoRef

    public init(accountID: UUID, repo: RepoRef) {
        self.accountID = accountID
        self.repo = repo
    }
}

public enum RepoListKind: Hashable, Sendable { case mine, starred }

/// Every screen that can be pushed onto a navigation stack.
public enum Route: Hashable, Sendable {
    case repoList(RepoListKind)
    /// Issues or pull requests involving the active accounts.
    case myIssues(IssueKind)
    case feed
    case repo(RepoTarget)
    case repoIssues(RepoTarget, IssueKind)
    case tree(RepoTarget, path: String, revision: String?)
    case file(RepoTarget, path: String, revision: String?)
    case commits(RepoTarget, revision: String?, path: String?)
    case commit(RepoTarget, id: String)
    case issue(RepoTarget, number: Int, kind: IssueKind)
}

extension View {
    /// Registers the screens for ``Route`` values on the enclosing navigation stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}

struct RouteView: View {
    let route: Route
    @Environment(AppModel.self) private var app

    var body: some View {
        switch route {
        case .repoList(let kind): RepoListView(kind: kind)
        case .myIssues(let kind): IssueListView(kind: kind, target: nil)
        case .feed: FeedView()
        case .repo(let t): withProvider(t) { RepoView(target: t, account: $0, provider: $1) }
        case .repoIssues(let t, let kind): IssueListView(kind: kind, target: t)
        case .tree(let t, let path, let rev):
            withProvider(t) { _, p in TreeView(target: t, provider: p, path: path, revision: rev) }
        case .file(let t, let path, let rev):
            withProvider(t) { _, p in FileView(target: t, provider: p, path: path, revision: rev) }
        case .commits(let t, let rev, let path):
            withProvider(t) { a, p in CommitListView(target: t, account: a, provider: p, revision: rev, path: path) }
        case .commit(let t, let id):
            withProvider(t) { _, p in CommitDetailView(target: t, provider: p, id: id) }
        case .issue(let t, let number, let kind):
            withProvider(t) { a, p in IssueDetailView(target: t, account: a, provider: p, number: number, kind: kind) }
        }
    }

    @ViewBuilder
    private func withProvider<V: View>(
        _ target: RepoTarget, @ViewBuilder _ content: (Account, any SourceControlProvider) -> V
    ) -> some View {
        if let account = app.account(target.accountID), let provider = app.provider(for: account) {
            content(account, provider)
        } else {
            MessageView(
                systemImage: "person.crop.circle.badge.exclamationmark", title: "Account unavailable",
                message: "The account for this screen was removed or needs to sign in again.")
        }
    }
}
