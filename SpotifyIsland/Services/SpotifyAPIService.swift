import Foundation

actor SpotifyAPIService {
    static let shared = SpotifyAPIService()

    private let baseURL = "https://api.spotify.com/v1"
    private var retryAfter: Date?

    // MARK: - Authorized Request Core

    @discardableResult
    private func authorizedRequest(
        _ urlString: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        // Rate limit check
        if let retryAfter, Date() < retryAfter {
            throw APIError.rateLimited
        }

        let tokens = try await validTokens()

        var components = URLComponents(string: urlString)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...204:
            return (data, httpResponse)
        case 401:
            // Try one token refresh and retry
            let newTokens = try await refreshTokens()
            var retryRequest = request
            retryRequest.setValue("Bearer \(newTokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            return (retryData, retryHTTP)
        case 403:
            throw APIError.premiumRequired
        case 429:
            let retrySeconds = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
            self.retryAfter = Date().addingTimeInterval(retrySeconds)
            throw APIError.rateLimited
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    private func validTokens() async throws -> AuthTokens {
        guard let tokens = await KeychainService.shared.loadTokens() else {
            throw APIError.notAuthenticated
        }
        if tokens.isExpired {
            return try await refreshTokens()
        }
        return tokens
    }

    private func refreshTokens() async throws -> AuthTokens {
        guard let tokens = await KeychainService.shared.loadTokens() else {
            throw APIError.notAuthenticated
        }
        return try await SpotifyAuthService.shared.refreshAccessToken(refreshToken: tokens.refreshToken)
    }

    // MARK: - Playback Read

    func getCurrentPlayback() async throws -> SpotifyPlaybackState? {
        let url = "\(baseURL)/me/player"
        let (data, response) = try await authorizedRequest(url, queryItems: [
            URLQueryItem(name: "additional_types", value: "track")
        ])

        // 204 = no active device / nothing playing
        if response.statusCode == 204 || data.isEmpty {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(SpotifyPlaybackState.self, from: data)
    }

    // MARK: - Playback Control

    func play() async throws {
        try await authorizedRequest("\(baseURL)/me/player/play", method: "PUT")
    }

    func pause() async throws {
        try await authorizedRequest("\(baseURL)/me/player/pause", method: "PUT")
    }

    func skipNext() async throws {
        try await authorizedRequest("\(baseURL)/me/player/next", method: "POST")
    }

    func skipPrevious() async throws {
        try await authorizedRequest("\(baseURL)/me/player/previous", method: "POST")
    }

    func seek(toMs ms: Int) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/seek",
            method: "PUT",
            queryItems: [URLQueryItem(name: "position_ms", value: "\(ms)")]
        )
    }

    func setVolume(_ percent: Int) async throws {
        let clamped = max(0, min(100, percent))
        try await authorizedRequest(
            "\(baseURL)/me/player/volume",
            method: "PUT",
            queryItems: [URLQueryItem(name: "volume_percent", value: "\(clamped)")]
        )
    }

    func setShuffle(_ enabled: Bool) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/shuffle",
            method: "PUT",
            queryItems: [URLQueryItem(name: "state", value: enabled ? "true" : "false")]
        )
    }

    func setRepeat(_ mode: RepeatMode) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/repeat",
            method: "PUT",
            queryItems: [URLQueryItem(name: "state", value: mode.rawValue)]
        )
    }

    // MARK: - Transfer Playback

    func transferPlayback(toDeviceId deviceId: String, play: Bool = false) async throws {
        let body = try JSONEncoder().encode([
            "device_ids": [deviceId]
        ])
        try await authorizedRequest("\(baseURL)/me/player", method: "PUT", body: body)
    }

    // MARK: - Library

    func getSavedAlbums(limit: Int = 50, offset: Int = 0) async throws -> SpotifySavedAlbumsResponse {
        let (data, _) = try await authorizedRequest(
            "\(baseURL)/me/albums",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )
        return try JSONDecoder().decode(SpotifySavedAlbumsResponse.self, from: data)
    }

    func playAlbum(uri: String) async throws {
        let body = try JSONEncoder().encode(["context_uri": uri])
        try await authorizedRequest("\(baseURL)/me/player/play", method: "PUT", body: body)
    }

    func checkSaved(trackIds: [String]) async throws -> [Bool] {
        let ids = trackIds.joined(separator: ",")
        let (data, _) = try await authorizedRequest(
            "\(baseURL)/me/tracks/contains",
            queryItems: [URLQueryItem(name: "ids", value: ids)]
        )
        return (try? JSONDecoder().decode([Bool].self, from: data)) ?? [false]
    }

    func saveTrack(id: String) async throws {
        let body = try JSONEncoder().encode(["ids": [id]])
        try await authorizedRequest("\(baseURL)/me/tracks", method: "PUT", body: body)
    }

    func removeTrack(id: String) async throws {
        let body = try JSONEncoder().encode(["ids": [id]])
        try await authorizedRequest("\(baseURL)/me/tracks", method: "DELETE", body: body)
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case premiumRequired
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with Spotify"
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid server response"
        case .premiumRequired: return "Spotify Premium required for playback control"
        case .rateLimited: return "Rate limited — please wait"
        case .httpError(let code): return "API error: HTTP \(code)"
        }
    }
}
