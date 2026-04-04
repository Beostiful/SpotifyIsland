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

// MARK: - Playlists

struct SpotifyPlaylistsResponse: Codable {
    let items: [SpotifyPlaylist]
    let total: Int
    let limit: Int
    let offset: Int
}

struct SpotifyPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]
    let uri: String
    let owner: SpotifyPlaylistOwner?
    let tracksInfo: SpotifyPlaylistTracksInfo?

    enum CodingKeys: String, CodingKey {
        case id, name, images, uri, owner
        case tracksInfo = "tracks"
    }

    var smallImageURL: URL? {
        let sorted = images.sorted { ($0.width ?? 9999) < ($1.width ?? 9999) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }

    var ownerName: String {
        owner?.displayName ?? ""
    }
}

struct SpotifyPlaylistOwner: Codable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct SpotifyPlaylistTracksInfo: Codable {
    let total: Int
}

// MARK: - Saved Tracks (Liked Songs)

struct SpotifySavedTracksResponse: Codable {
    let items: [SpotifySavedTrackItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct SpotifySavedTrackItem: Codable, Identifiable {
    let addedAt: String
    let track: SpotifyTrack

    var id: String { track.id }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track
    }
}

// MARK: - Recently Played

struct SpotifyRecentlyPlayedResponse: Codable {
    let items: [SpotifyRecentItem]
}

struct SpotifyRecentItem: Codable, Identifiable {
    let track: SpotifyTrack
    let playedAt: String

    var id: String { "\(track.id)-\(playedAt)" }

    enum CodingKeys: String, CodingKey {
        case track
        case playedAt = "played_at"
    }
}

// MARK: - Library Filter

enum LibraryFilter: String, CaseIterable {
    case albums = "Albums"
    case playlists = "Playlists"
    case likedSongs = "Liked Songs"
    case recentlyPlayed = "Recently Played"

    var icon: String {
        switch self {
        case .albums: return "square.stack"
        case .playlists: return "music.note.list"
        case .likedSongs: return "heart.fill"
        case .recentlyPlayed: return "clock"
        }
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
