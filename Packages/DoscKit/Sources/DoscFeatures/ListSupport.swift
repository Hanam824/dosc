import DoscCore
import DoscUI
import SwiftUI

/// A list backed by a ``PagedList``: loading and error states, pull to refresh, and the next page
/// when the last row appears.
struct PagedListView<Item: Identifiable & Sendable, Row: View>: View where Item.ID: Sendable {
    let list: PagedList<Item>
    let emptyTitle: String
    let emptySymbol: String
    let reload: () async -> Void
    @ViewBuilder let row: (Sourced<Item>) -> Row

    var body: some View {
        Group {
            switch list.phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                MessageView(
                    systemImage: "exclamationmark.triangle", title: "Couldn't load", message: message,
                    retry: { Task { await reload() } })
            case .loaded where list.items.isEmpty:
                MessageView(systemImage: emptySymbol, title: emptyTitle)
                    .refreshable { await reload() }
            case .loaded:
                List {
                    if !list.partialFailures.isEmpty {
                        Section {
                            ForEach(list.partialFailures, id: \.self) { failure in
                                SwiftUI.Label(failure, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.attention)
                            }
                        }
                    }
                    ForEach(list.items) { item in
                        row(item)
                            .onAppear {
                                if item.id == list.items.last?.id { Task { await list.loadMore() } }
                            }
                    }
                    if list.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
    }
}

/// Shows a ``Loader``'s value, a spinner, or the error with a retry button.
struct LoaderView<Value: Sendable, Content: View>: View {
    let loader: Loader<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch loader.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            MessageView(
                systemImage: "exclamationmark.triangle", title: "Couldn't load", message: message,
                retry: { Task { await retry() } })
        case .loaded(let value):
            content(value)
        }
    }
}

/// The avatar menu at the top left: pick one account or all of them.
struct AccountSwitcher: ToolbarContent {
    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Picker(
                    "Account",
                    selection: Binding(get: { app.selection }, set: { app.selection = $0 })
                ) {
                    SwiftUI.Label("All Accounts", systemImage: "person.2").tag(AccountSelection.all)
                    ForEach(app.accounts) { account in
                        Text("\(account.label) · \(account.kind.displayName)")
                            .tag(AccountSelection.account(account.id))
                    }
                }
            } label: {
                switch app.selection {
                case .all:
                    Image(systemName: "person.2.circle").font(.title3)
                case .account(let id):
                    if let account = app.account(id) {
                        AvatarView(url: account.avatarURL, login: account.login, size: 28)
                    }
                }
            }
            .accessibilityLabel("Switch account")
        }
    }
}

extension View {
    /// Adds the account switcher when there is more than one account.
    @ViewBuilder
    func accountSwitcher(_ app: AppModel) -> some View {
        if app.accounts.count > 1 {
            toolbar { AccountSwitcher() }
        } else {
            self
        }
    }

    /// The inline title style the GitHub app uses on pushed screens.
    func inlineTitle(_ title: String) -> some View {
        navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}
