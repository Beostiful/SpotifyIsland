import Foundation

// MARK: - Playback State

struct SpotifyPlaybackState: Codable {
    let device: SpotifyDevice?
    let repeatState: String
    let shuffleState: Bool
    let progressMs: Int?
    let isPlaying: Bool
    let item: SpotifyTrack?

    enum CodingKeys: String, CodingKey {
        case device
        case repeatState = "repeat_state"
        case shuffleState = "shuffle_state"
        case progressMs = "progress_ms"
        case isPlaying = "is_playing"
        case item
    }
}

// MARK: - Track

struct SpotifyTrack: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int
    let uri: String

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album, uri
        case durationMs = "duration_ms"
    }

    static func == (lhs: SpotifyTrack, rhs: SpotifyTrack) -> Bool {
        lhs.id == rhs.id
    }

    var artistName: String {
        artists.map(\.name).joined(separator: ", ")
    }

    var formattedDuration: String {
        Self.formatTime(durationMs)
    }

    static func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Album

struct SpotifyAlbum: Codable {
    let id: String
    let name: String
    let images: [SpotifyImage]

    /// Best image for expanded view (~300px)
    var bestImageURL: URL? {
        let sorted = images.sorted { abs(($0.width ?? 0) - 300) < abs(($1.width ?? 0) - 300) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }

    /// Smallest image for collapsed pill
    var smallImageURL: URL? {
        let sorted = images.sorted { ($0.width ?? 9999) < ($1.width ?? 9999) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }
}

// MARK: - Supporting Types

struct SpotifyArtist: Codable, Identifiable {
    let id: String
    let name: String
}

struct SpotifyImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyDevice: Codable {
    let id: String?
    let name: String
    let type: String
    let volumePercent: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case volumePercent = "volume_percent"
    }
}

// MARK: - Saved Albums Response

struct SpotifySavedAlbumsResponse: Codable {
    let items: [SpotifySavedAlbumItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct SpotifySavedAlbumItem: Codable, Identifiable {
    let addedAt: String
    let album: SpotifyFullAlbum

    var id: String { album.id }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case album
    }
}

struct SpotifyFullAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let images: [SpotifyImage]
    let uri: String
    let totalTracks: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, images, uri
        case totalTracks = "total_tracks"
    }

    var artistName: String {
        artists.map(\.name).joined(separator: ", ")
    }

    var smallImageURL: URL? {
        let sorted = images.sorted { ($0.width ?? 9999) < ($1.width ?? 9999) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }

    var mediumImageURL: URL? {
        let sorted = images.sorted { abs(($0.width ?? 0) - 150) < abs(($1.width ?? 0) - 150) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }
}

// MARK: - Repeat Mode

enum RepeatMode: String {
    case off = "off"
    case context = "context"
    case track = "track"

    func next() -> RepeatMode {
        switch self {
        case .off: return .context
        case .context: return .track
        case .track: return .off
        }
    }

    var systemImage: String {
        switch self {
        case .off, .context: return "repeat"
        case .track: return "repeat.1"
        }
    }

    var isActive: Bool {
        self != .off
    }
}
