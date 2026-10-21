import DoscCore
import DoscFeatures
import DoscGitHub
import DoscNetworking
import DoscStorage
import SwiftUI

@main
struct DoscApp: App {
    @State private var model: AppModel

    init() {
        let http = HTTPClient()
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String
        _model = State(
            initialValue: AppModel(
                connectors: [GitHubConnector(clientID: clientID, http: http)],
                stateStore: .standard(),
                tokenStore: KeychainTokenStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
