import DoscCore
import DoscUI
import LocalAuthentication
import SwiftUI

/// The app's root: the welcome screen until an account is added, then the tabs. Covered by the
/// lock screen while the app lock is on and not yet unlocked.
public struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            if app.accounts.isEmpty {
                WelcomeView()
            } else {
                MainTabView()
            }
            if app.isLocked {
                LockView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && app.appLockEnabled { app.isLocked = true }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView().routeDestinations() }
                .tabItem { SwiftUI.Label("Home", systemImage: "house") }
            NavigationStack { NotificationsView().routeDestinations() }
                .tabItem { SwiftUI.Label("Notifications", systemImage: "bell") }
            NavigationStack { ExploreView().routeDestinations() }
                .tabItem { SwiftUI.Label("Explore", systemImage: "safari") }
            NavigationStack { AccountsView() }
                .tabItem { SwiftUI.Label("Accounts", systemImage: "person.crop.circle") }
        }
    }
}

struct WelcomeView: View {
    @State private var addingAccount = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 64))
                .foregroundStyle(Palette.accent)
            Text("dosc").font(.largeTitle.bold())
            Text(
                "Browse code, history, issues and pull requests from all your GitHub accounts. Read only: dosc never changes anything."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.fgMuted)
            .padding(.horizontal, 32)
            Spacer()
            Button {
                addingAccount = true
            } label: {
                Text("Add an Account").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            Text("GitLab and Subversion are coming later.")
                .font(.footnote)
                .foregroundStyle(Palette.fgMuted)
                .padding(.bottom)
        }
        .sheet(isPresented: $addingAccount) { AddAccountView() }
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Palette.fgMuted)
            Text("dosc is locked").font(.title2.bold())
            if let error { Text(error).font(.footnote).foregroundStyle(Palette.closed) }
            Button("Unlock") { Task { await unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvasDefault)
        .task { await unlock() }
    }

    private func unlock() async {
        let context = LAContext()
        do {
            if try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "Unlock dosc to see your accounts")
            {
                app.isLocked = false
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
