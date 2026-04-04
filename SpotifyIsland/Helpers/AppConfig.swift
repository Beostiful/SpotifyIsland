import Foundation

/// Stores user-configurable app settings (Client ID, redirect URI).
/// Uses UserDefaults — not secrets, just configuration.
enum AppConfig {
    private static let clientIdKey = "SpotifyIsland.clientId"
    private static let redirectURIKey = "SpotifyIsland.redirectURI"

    static let defaultRedirectURI = "spotifyisland://callback"

    static var clientId: String? {
        get {
            let val = UserDefaults.standard.string(forKey: clientIdKey)
            return (val?.isEmpty == false) ? val : nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: clientIdKey)
        }
    }

    static var redirectURI: String {
        get {
            let val = UserDefaults.standard.string(forKey: redirectURIKey)
            return (val?.isEmpty == false) ? val! : defaultRedirectURI
        }
        set {
            UserDefaults.standard.set(newValue, forKey: redirectURIKey)
        }
    }

    static var isConfigured: Bool {
        clientId != nil
    }
}
