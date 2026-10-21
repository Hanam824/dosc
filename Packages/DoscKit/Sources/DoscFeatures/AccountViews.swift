import DoscCore
import DoscUI
import SwiftUI

/// The Accounts tab: signed-in accounts, adding and removing them, and settings.
struct AccountsView: View {
    @Environment(AppModel.self) private var app
    @State private var addingAccount = false
    @State private var removing: Account?

    var body: some View {
        @Bindable var app = app
        List {
            Section {
                ForEach(app.accounts) { account in
                    HStack(spacing: 12) {
                        AvatarView(url: account.avatarURL, login: account.login, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName ?? account.login).font(.headline)
                            Text("\(account.login) · \(account.host.host() ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(Palette.fgMuted)
                        }
                        Spacer()
                        Text(account.kind.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.canvasSubtle, in: Capsule())
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { removing = account }
                    }
                    .contextMenu {
                        Button("Remove from dosc", systemImage: "trash", role: .destructive) { removing = account }
                    }
                }
                .onMove { app.moveAccounts(from: $0, to: $1) }
                Button {
                    addingAccount = true
                } label: {
                    SwiftUI.Label("Add Account", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Removing an account only signs it out of dosc. Tokens are kept in this device's Keychain.")
            }

            Section("Security") {
                Toggle("Require Face ID or passcode", isOn: $app.appLockEnabled)
            }

            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("dosc is read-only: it never creates, edits or deletes anything on your servers.")
                    .font(.footnote)
                    .foregroundStyle(Palette.fgMuted)
                if let error = app.saveError {
                    Text("Couldn't save settings: \(error)").font(.footnote).foregroundStyle(Palette.closed)
                }
            }
        }
        .navigationTitle("Accounts")
        .sheet(isPresented: $addingAccount) { AddAccountView() }
        .confirmationDialog(
            "Remove \(removing?.label ?? "account")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let removing { app.removeAccount(removing.id) }
                removing = nil
            }
        } message: {
            Text("dosc forgets this account and its token. You can add it again later.")
        }
    }
}

/// Sign-in: choose a provider, then paste a token or use the device flow.
struct AddAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind: ProviderKind = .github
    @State private var hostText = ""
    @State private var token = ""
    @State private var working = false
    @State private var error: String?
    @State private var deviceCode: DeviceCode?
    @State private var deviceTask: Task<Void, Never>?

    private var connector: (any ProviderConnector)? { app.connector(for: kind) }

    /// The entered host, defaulting to the provider's public one. Accepts `example.com` or a full URL.
    private var host: URL? {
        let text = hostText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return connector?.defaultHost }
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $kind) {
                        ForEach(ProviderKind.allCases, id: \.self) { kind in
                            Text(kind.isAvailable ? kind.displayName : "\(kind.displayName) (coming soon)")
                                .tag(kind)
                        }
                    }
                    TextField(connector?.defaultHost.host() ?? "Server", text: $hostText)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        #endif
                } footer: {
                    Text(
                        "Leave the server empty for \(connector?.defaultHost.host() ?? "the public service"). Enter your GitHub Enterprise address otherwise."
                    )
                }

                if kind.isAvailable, let connector, let host {
                    if connector.supportsDeviceFlow(host: host) {
                        Section {
                            if let deviceCode {
                                deviceCodeView(deviceCode)
                            } else {
                                Button {
                                    startDeviceFlow(connector, host: host)
                                } label: {
                                    SwiftUI.Label("Sign in with \(kind.displayName)", systemImage: "person.badge.key")
                                }
                                .disabled(working)
                            }
                        } footer: {
                            Text("Opens \(kind.displayName) in the browser, where you enter a short code.")
                        }
                    }

                    Section {
                        SecureField("Personal access token", text: $token)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                        Button("Add with Token") { signIn(connector, host: host) }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    } header: {
                        Text("Token")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(
                                "Create a fine-grained token with read-only access to contents, issues, pull requests and metadata, or a classic token with the repo, read:org and notifications scopes."
                            )
                            if let url = connector.tokenCreationURL(host: host) {
                                Link("Create a token on \(host.host() ?? "the server")", destination: url)
                            }
                        }
                    }
                } else if !kind.isAvailable {
                    Section {
                        Text("\(kind.displayName) accounts are coming in a later version.")
                            .foregroundStyle(Palette.fgMuted)
                    }
                } else if host == nil {
                    Section { Text("Enter a valid server address.").foregroundStyle(Palette.closed) }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Palette.closed) }
                }
            }
            .navigationTitle("Add Account")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        deviceTask?.cancel()
                        dismiss()
                    }
                }
                if working {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .onChange(of: kind) {
                deviceTask?.cancel()
                deviceCode = nil
                error = nil
            }
        }
    }

    private func deviceCodeView(_ code: DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on \(code.verificationURL.host() ?? "the website"):")
                .font(.subheadline)
            Text(code.userCode)
                .font(.system(.largeTitle, design: .monospaced).bold())
                .textSelection(.enabled)
            HStack {
                Button("Copy Code", systemImage: "doc.on.doc") { copy(code.userCode) }
                    .buttonStyle(.bordered)
                Button("Open \(code.verificationURL.host() ?? "Browser")", systemImage: "safari") {
                    copy(code.userCode)
                    openURL(code.verificationURL)
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 6) {
                ProgressView()
                Text("Waiting for approval…").font(.footnote).foregroundStyle(Palette.fgMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func signIn(_ connector: any ProviderConnector, host: URL) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let account = try await connector.signIn(host: host, token: token)
                try app.addAccount(account, token: token)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func startDeviceFlow(_ connector: any ProviderConnector, host: URL) {
        working = true
        error = nil
        deviceTask = Task {
            defer { working = false }
            do {
                let code = try await connector.startDeviceFlow(host: host)
                deviceCode = code
                let token = try await connector.finishDeviceFlow(host: host, code: code)
                let account = try await connector.signIn(host: host, token: token)
                try app.addAccount(account, token: token)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                deviceCode = nil
                self.error = error.localizedDescription
            }
        }
    }
}
