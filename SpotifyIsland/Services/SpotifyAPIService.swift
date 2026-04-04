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

    // All playback methods accept an optional device_id to pin commands to a specific device.
    // When using the Web Playback SDK, always pass its device ID.

    func play(deviceId: String? = nil) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/play",
            method: "PUT",
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func pause(deviceId: String? = nil) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/pause",
            method: "PUT",
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func skipNext(deviceId: String? = nil) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/next",
            method: "POST",
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func skipPrevious(deviceId: String? = nil) async throws {
        try await authorizedRequest(
            "\(baseURL)/me/player/previous",
            method: "POST",
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func seek(toMs ms: Int, deviceId: String? = nil) async throws {
        var items = [URLQueryItem(name: "position_ms", value: "\(ms)")]
        if let id = deviceId { items.append(URLQueryItem(name: "device_id", value: id)) }
        try await authorizedRequest(
            "\(baseURL)/me/player/seek",
            method: "PUT",
            queryItems: items
        )
    }

    func setVolume(_ percent: Int, deviceId: String? = nil) async throws {
        let clamped = max(0, min(100, percent))
        var items = [URLQueryItem(name: "volume_percent", value: "\(clamped)")]
        if let id = deviceId { items.append(URLQueryItem(name: "device_id", value: id)) }
        try await authorizedRequest(
            "\(baseURL)/me/player/volume",
            method: "PUT",
            queryItems: items
        )
    }

    func setShuffle(_ enabled: Bool, deviceId: String? = nil) async throws {
        var items = [URLQueryItem(name: "state", value: enabled ? "true" : "false")]
        if let id = deviceId { items.append(URLQueryItem(name: "device_id", value: id)) }
        try await authorizedRequest(
            "\(baseURL)/me/player/shuffle",
            method: "PUT",
            queryItems: items
        )
    }

    func setRepeat(_ mode: RepeatMode, deviceId: String? = nil) async throws {
        var items = [URLQueryItem(name: "state", value: mode.rawValue)]
        if let id = deviceId { items.append(URLQueryItem(name: "device_id", value: id)) }
        try await authorizedRequest(
            "\(baseURL)/me/player/repeat",
            method: "PUT",
            queryItems: items
        )
    }

    private func deviceIdQuery(_ deviceId: String?) -> [URLQueryItem] {
        guard let id = deviceId else { return [] }
        return [URLQueryItem(name: "device_id", value: id)]
    }

    // MARK: - Transfer Playback

    func transferPlayback(toDeviceId deviceId: String, play: Bool = true) async throws {
        let bodyDict: [String: Any] = [
            "device_ids": [deviceId],
            "play": play
        ]
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
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

    func playAlbum(uri: String, deviceId: String? = nil) async throws {
        let body = try JSONEncoder().encode(["context_uri": uri])
        try await authorizedRequest(
            "\(baseURL)/me/player/play",
            method: "PUT",
            body: body,
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func getMyPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPlaylistsResponse {
        let (data, _) = try await authorizedRequest(
            "\(baseURL)/me/playlists",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )
        return try JSONDecoder().decode(SpotifyPlaylistsResponse.self, from: data)
    }

    func getSavedTracks(limit: Int = 50, offset: Int = 0) async throws -> SpotifySavedTracksResponse {
        let (data, _) = try await authorizedRequest(
            "\(baseURL)/me/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )
        return try JSONDecoder().decode(SpotifySavedTracksResponse.self, from: data)
    }

    func getRecentlyPlayed(limit: Int = 50) async throws -> SpotifyRecentlyPlayedResponse {
        let (data, _) = try await authorizedRequest(
            "\(baseURL)/me/player/recently-played",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
    }

    func playPlaylist(uri: String, deviceId: String? = nil) async throws {
        let body = try JSONEncoder().encode(["context_uri": uri])
        try await authorizedRequest(
            "\(baseURL)/me/player/play",
            method: "PUT",
            body: body,
            queryItems: deviceIdQuery(deviceId)
        )
    }

    func playTrack(uri: String, deviceId: String? = nil) async throws {
        let bodyDict: [String: Any] = ["uris": [uri]]
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
        try await authorizedRequest(
            "\(baseURL)/me/player/play",
            method: "PUT",
            body: body,
            queryItems: deviceIdQuery(deviceId)
        )
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
