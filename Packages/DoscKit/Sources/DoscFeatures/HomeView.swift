import DoscCore
import DoscUI
import SwiftUI

/// The Home tab, laid out like the GitHub app's: "My Work" shortcuts, then recent repositories.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section("My Work") {
                NavigationLink(value: Route.myIssues(.issue)) {
                    row("Issues", icon: "smallcircle.filled.circle", color: Palette.homeIssues)
                }
                NavigationLink(value: Route.myIssues(.changeRequest)) {
                    row("Pull Requests", icon: "arrow.triangle.pull", color: Palette.homePulls)
                }
                NavigationLink(value: Route.repoList(.mine)) {
                    row("Repositories", icon: "book.closed", color: Palette.homeRepos)
                }
                NavigationLink(value: Route.repoList(.starred)) {
                    row("Starred", icon: "star", color: Palette.homeStarred)
                }
                NavigationLink(value: Route.feed) {
                    row("Activity", icon: "waveform.path.ecg", color: Palette.homeActivity)
                }
            }

            let recents = app.state.recentRepos.filter { recent in
                app.activeAccounts.contains { $0.id == recent.accountID }
            }
            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents, id: \.self) { recent in
                        NavigationLink(value: Route.repo(RepoTarget(accountID: recent.accountID, repo: recent.repo))) {
                            HStack(spacing: 12) {
                                IconTile("book.closed", color: Palette.neutral)
                                VStack(alignment: .leading, spacing: 2) {
                                    RepoNameText(recent.repo).lineLimit(1)
                                    if app.showsAccountBadges, let account = app.account(recent.accountID) {
                                        AccountBadge(account)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
        .accountSwitcher(app)
    }

    private func row(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(icon, color: color)
            Text(title)
        }
    }
}

/// Sources for a ``PagedList`` covering every active account whose provider can do `capability`.
@MainActor
func sources<Item>(
    _ app: AppModel, needs capability: Capability? = nil,
    _ fetch: @escaping @Sendable (any SourceControlProvider, PageCursor?) async throws -> Page<Item>
) -> [PagedList<Item>.Source] {
    app.activeAccounts.compactMap { account in
        guard let provider = app.provider(for: account),
            capability.map({ provider.capabilities.contains($0) }) ?? true
        else { return nil }
        return .init(account: account) { cursor in try await fetch(provider, cursor) }
    }
}
