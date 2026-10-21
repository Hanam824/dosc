import DoscCore
import DoscNetworking
import Foundation

/// Signs in to GitHub with a personal access token or the OAuth device flow, and makes
/// ``GitHubProvider``s.
public struct GitHubConnector: ProviderConnector {
    /// The OAuth App's client ID; the device flow is off when it's `nil` or empty.
    let clientID: String?
    let http: HTTPClient
    let poster: FormPoster
    /// How long to wait between polls; tests replace it to avoid real sleeping.
    let sleep: @Sendable (Duration) async throws -> Void

    /// Read access to private repositories needs `repo`: GitHub's OAuth Apps have no read-only scope
    /// for them. dosc never writes, whatever the scope allows.
    static let scopes = "repo read:org read:user notifications"

    public init(
        clientID: String?, http: HTTPClient, poster: FormPoster = FormPoster(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.clientID = clientID
        self.http = http
        self.poster = poster
        self.sleep = sleep
    }

    public var kind: ProviderKind { .github }
    public var defaultHost: URL { URL(string: "https://github.com")! }

    public func tokenCreationURL(host: URL) -> URL? {
        host.appending(path: "settings/personal-access-tokens/new")
    }

    public func supportsDeviceFlow(host: URL) -> Bool {
        host.host() == "github.com" && !(clientID ?? "").isEmpty
    }

    public func signIn(host: URL, token: String) async throws -> Account {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let probe = Account(kind: .github, host: host, login: "")
        let user = try await makeProvider(account: probe, token: token).currentUser()
        return Account(
            kind: .github, host: host, login: user.login, displayName: user.name, avatarURL: user.avatarURL)
    }

    public func startDeviceFlow(host: URL) async throws -> DeviceCode {
        guard let clientID, supportsDeviceFlow(host: host) else { throw ProviderError.unsupported }
        let data = try await post(
            host.appending(path: "login/device/code"), ["client_id": clientID, "scope": Self.scopes])
        let dto = try GitHubAPI.decode(DeviceCodeDTO.self, from: data)
        return DeviceCode(
            userCode: dto.userCode, verificationURL: dto.verificationUri,
            expiresAt: .now.addingTimeInterval(TimeInterval(dto.expiresIn)), interval: dto.interval ?? 5,
            deviceCode: dto.deviceCode)
    }

    public func finishDeviceFlow(host: URL, code: DeviceCode) async throws -> String {
        guard let clientID else { throw ProviderError.unsupported }
        var interval = code.interval
        while Date.now < code.expiresAt {
            try await sleep(.seconds(interval))
            let data = try await post(
                host.appending(path: "login/oauth/access_token"),
                [
                    "client_id": clientID, "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            let dto = try GitHubAPI.decode(AccessTokenDTO.self, from: data)
            if let token = dto.accessToken { return token }
            switch dto.error {
            case "authorization_pending": continue
            case "slow_down": interval = dto.interval ?? interval + 5
            case "expired_token": throw DeviceFlowError.expired
            case "access_denied": throw DeviceFlowError.denied
            default: throw ProviderError.server(status: 400, message: dto.errorDescription ?? dto.error)
            }
        }
        throw DeviceFlowError.expired
    }

    public func makeProvider(account: Account, token: String) -> any SourceControlProvider {
        GitHubProvider(account: account, token: token, http: http)
    }

    private func post(_ url: URL, _ fields: [String: String]) async throws -> Data {
        do {
            return try await poster.post(url, fields: fields)
        } catch let error as HTTPError {
            throw GitHubAPI.providerError(error)
        }
    }
}

public enum DeviceFlowError: LocalizedError, Equatable {
    case expired
    case denied

    public var errorDescription: String? {
        switch self {
        case .expired: "The code expired before it was approved. Start again."
        case .denied: "Sign-in was cancelled on GitHub."
        }
    }
}
