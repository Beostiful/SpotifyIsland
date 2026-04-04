import Foundation
import CryptoKit
import AppKit

actor SpotifyAuthService {
    static let shared = SpotifyAuthService()

    // MARK: - Configuration
    // Set your Spotify Client ID from https://developer.spotify.com/dashboard
    // Either replace this value or set the SPOTIFY_CLIENT_ID environment variable.
    static let clientId: String = {
        if let envId = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"], !envId.isEmpty {
            return envId
        }
        // Fallback — replace with your own Client ID
        return "7b5153efed80424698706aeb61c3d496"
    }()

    private let redirectURI = "spotifyisland://callback"
    private let authURL = "https://accounts.spotify.com/authorize"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let scopes = [
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-library-read",
        "user-library-modify"
    ].joined(separator: " ")

    // PKCE state
    private var codeVerifier: String?
    private var state: String?

    private var authContinuation: CheckedContinuation<URL, Error>?

    // MARK: - PKCE Login

    func startLogin() async throws {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let stateValue = generateState()

        self.codeVerifier = verifier
        self.state = stateValue

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation

            var components = URLComponents(string: authURL)!
            components.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: Self.clientId),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "state", value: stateValue),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "show_dialog", value: "true")
            ]
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        }

        try await handleCallback(url: callbackURL)
    }

    /// Called by AppDelegate when spotifyisland:// URL scheme is opened
    func receiveURLSchemeCallback(_ url: URL) {
        if let continuation = authContinuation {
            continuation.resume(returning: url)
            authContinuation = nil
        }
    }

    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw AuthError.invalidCallback
        }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let returnedState = params["state"], returnedState == self.state else {
            throw AuthError.stateMismatch
        }

        if let error = params["error"] {
            throw AuthError.authorizationDenied(error)
        }

        guard let code = params["code"], let verifier = self.codeVerifier else {
            throw AuthError.missingCode
        }

        let tokens = try await exchangeCode(code, verifier: verifier)
        NSLog("[SpotifyIsland] Token granted with scopes: '\(tokens.scope)'")
        try await KeychainService.shared.saveTokens(tokens)

        self.codeVerifier = nil
        self.state = nil
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, verifier: String) async throws -> AuthTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "client_id=\(Self.clientId)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }

        return try parseTokenResponse(data)
    }

    func refreshAccessToken(refreshToken: String) async throws -> AuthTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(Self.clientId)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.refreshFailed
        }

        // Load existing scope so it's preserved through refresh (Spotify may omit scope in refresh response)
        let existingTokens = await KeychainService.shared.loadTokens()
        let newTokens = try parseTokenResponse(data, existingRefreshToken: refreshToken, existingScope: existingTokens?.scope)
        try await KeychainService.shared.saveTokens(newTokens)
        return newTokens
    }

    // MARK: - Helpers

    private func parseTokenResponse(_ data: Data, existingRefreshToken: String? = nil, existingScope: String? = nil) throws -> AuthTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw AuthError.parseError
        }

        let refreshToken = (json["refresh_token"] as? String) ?? existingRefreshToken ?? ""
        let scope = (json["scope"] as? String) ?? existingScope ?? ""

        return AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            grantedAt: Date(),
            scope: scope
        )
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

// MARK: - Data Base64URL Extension

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCallback
    case stateMismatch
    case missingCode
    case authorizationDenied(String)
    case tokenExchangeFailed
    case refreshFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "Invalid OAuth callback URL"
        case .stateMismatch: return "OAuth state mismatch — possible CSRF attack"
        case .missingCode: return "No authorization code in callback"
        case .authorizationDenied(let reason): return "Authorization denied: \(reason)"
        case .tokenExchangeFailed: return "Token exchange failed"
        case .refreshFailed: return "Token refresh failed"
        case .parseError: return "Failed to parse token response"
        }
    }
}
