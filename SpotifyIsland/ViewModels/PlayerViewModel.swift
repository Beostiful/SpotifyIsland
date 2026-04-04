import Foundation
import Combine
import WebKit

@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isExpanded = false
    @Published var isAuthenticated = false

    // Track
    @Published var currentTrack: SpotifyTrack?
    @Published var albumArtURL: URL?
    @Published var smallAlbumArtURL: URL?

    // Playback
    @Published var isPlaying = false
    @Published var progressMs = 0
    @Published var durationMs = 0
    @Published var shuffleState = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volumePercent = 50

    // Library
    @Published var isLiked = false
    @Published var savedAlbums: [SpotifySavedAlbumItem] = []
    @Published var playlists: [SpotifyPlaylist] = []
    @Published var likedSongs: [SpotifySavedTrackItem] = []
    @Published var recentlyPlayed: [SpotifyRecentItem] = []
    @Published var libraryFilter: LibraryFilter = .albums

    // UI
    @Published var isSeeking = false
    @Published var isAdjustingVolume = false
    @Published var errorMessage: String?
    @Published var isPremiumError = false

    // MARK: - Volume Persistence

    private static let volumeKey = "SpotifyIsland.lastVolume"
    private static let defaultSafeVolume = 30  // Safe startup cap
    private static let minimumAudibleVolume = 15  // Floor to prevent "no sound"

    private var savedVolume: Int {
        let v = UserDefaults.standard.integer(forKey: Self.volumeKey)
        let vol = v > 0 ? v : Self.defaultSafeVolume
        // Never restore below minimum — prevents "no sound" from tiny saved values
        return max(vol, Self.minimumAudibleVolume)
    }

    private func persistVolume(_ percent: Int) {
        UserDefaults.standard.set(percent, forKey: Self.volumeKey)
    }

    // MARK: - Web Playback

    private let playbackService = WebPlaybackService.shared
    private var playbackCancellable: AnyCancellable?

    /// The SDK device ID — used to pin all REST API calls to the correct device.
    private var sdkDeviceId: String? { playbackService.deviceId }

    // MARK: - Debouncing

    private var inFlightActions: Set<String> = []
    private var volumeDebounceTask: Task<Void, Never>?
    private var didCorrectLowVolume = false

    private func debounced(_ key: String, action: () async -> Void) async {
        guard !inFlightActions.contains(key) else { return }
        inFlightActions.insert(key)
        defer { inFlightActions.remove(key) }
        await action()
    }

    // MARK: - Timers

    private var pollTimer: Timer?
    private var progressTimer: Timer?

    /// Consecutive polls that returned no active playback.
    /// We only clear UI state after several misses in a row to avoid
    /// flashing during track transitions.
    private var consecutiveEmptyPolls = 0
    private let emptyPollThreshold = 3

    // MARK: - Init

    init() {
        Task { await checkAuth() }
    }

    // MARK: - Auth

    func checkAuth() async {
        guard let tokens = await KeychainService.shared.loadTokens() else {
            isAuthenticated = false
            return
        }

        // Token from before streaming scope was added — force re-login once
        if !tokens.scope.isEmpty && !tokens.scope.contains("streaming") {
            await KeychainService.shared.deleteTokens()
            isAuthenticated = false
            return
        }

        isAuthenticated = true
        await startWebPlayback()
        startTimers()
        await pollPlayback()
        await fetchSavedAlbums()
    }

    func login() {
        Task {
            do {
                try await SpotifyAuthService.shared.startLogin()
                isAuthenticated = true
                await startWebPlayback()
                startTimers()
                await pollPlayback()
                await fetchSavedAlbums()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleAuthCallback(url: URL) async {
        do {
            try await SpotifyAuthService.shared.handleCallback(url: url)
            isAuthenticated = true
            await startWebPlayback()
            startTimers()
            await pollPlayback()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        stopTimers()
        playbackService.disconnect()
        playbackCancellable?.cancel()
        await KeychainService.shared.deleteTokens()
        isAuthenticated = false
        currentTrack = nil
        albumArtURL = nil
        smallAlbumArtURL = nil
        isPlaying = false
        progressMs = 0
        durationMs = 0
        isLiked = false
    }

    // MARK: - Web Playback SDK

    private func startWebPlayback() async {
        // Ensure we have a fresh (non-expired) token before starting SDK
        guard var tokens = await KeychainService.shared.loadTokens() else { return }

        if tokens.isExpired {
            AppLog.info(" Token expired on startup — refreshing before SDK init")
            do {
                tokens = try await SpotifyAuthService.shared.refreshAccessToken(refreshToken: tokens.refreshToken)
            } catch {
                AppLog.info(" Token refresh failed: \(error.localizedDescription)")
                return
            }
        }

        // Restore last-known volume (safe default if first launch)
        let safeVol = savedVolume
        volumePercent = safeVol
        playbackService.initialVolumeFraction = Double(safeVol) / 100.0

        // Wire up state_changed callback for instant polling
        playbackService.onStateChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Small delay to let Spotify backend catch up
                try? await Task.sleep(for: .milliseconds(200))
                await self.pollPlayback()
            }
        }

        playbackService.setup { [weak self] in
            guard self != nil else { return nil }
            let t = await KeychainService.shared.loadTokens()
            if let t, t.isExpired {
                AppLog.info(" Token provider: refreshing expired token")
                let refreshed = try? await SpotifyAuthService.shared.refreshAccessToken(refreshToken: t.refreshToken)
                return refreshed?.accessToken
            }
            return t?.accessToken
        }
        playbackService.updateToken(tokens.accessToken)

        // When the SDK is ready, transfer playback and apply safe volume
        playbackCancellable = playbackService.$deviceId
            .compactMap { $0 }
            .first()
            .sink { [weak self] deviceId in
                Task { [weak self] in
                    guard let self else { return }
                    if self.playbackService.hasAuthError == false {
                        // Set volume on the new device FIRST (before transfer starts playback)
                        let targetVolume = self.savedVolume
                        try? await SpotifyAPIService.shared.transferPlayback(toDeviceId: deviceId)
                        // Apply saved volume immediately after transfer
                        try? await SpotifyAPIService.shared.setVolume(targetVolume, deviceId: deviceId)
                        AppLog.info(" Transferred to SDK device: \(deviceId), volume: \(targetVolume)%")
                    } else {
                        AppLog.info(" SDK has auth error — using external device")
                    }
                }
            }
    }

    // MARK: - Timers

    private func startTimers() {
        stopTimers()

        // Poll API every 2 seconds (state_changed gives us instant updates too)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.pollPlayback() }
        }

        // Smooth progress update every 100ms
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPlaying && !self.isSeeking && self.durationMs > 0 {
                    self.progressMs = min(self.progressMs + 100, self.durationMs)
                }
            }
        }
    }

    private func stopTimers() {
        pollTimer?.invalidate()
        pollTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Token Maintenance

    /// Proactively refresh token if expiring within 5 minutes.
    private var lastTokenRefreshCheck = Date.distantPast

    private func refreshTokenIfNeeded() async {
        // Only check once per minute to avoid hammering keychain
        guard Date().timeIntervalSince(lastTokenRefreshCheck) > 60 else { return }
        lastTokenRefreshCheck = Date()

        guard let tokens = await KeychainService.shared.loadTokens() else { return }

        let expiryDate = tokens.grantedAt.addingTimeInterval(Double(tokens.expiresIn))
        let timeRemaining = expiryDate.timeIntervalSinceNow

        if timeRemaining < 300 {
            AppLog.info(" Token expiring in \(Int(timeRemaining))s — proactively refreshing")
            do {
                let newTokens = try await SpotifyAuthService.shared.refreshAccessToken(refreshToken: tokens.refreshToken)
                playbackService.updateToken(newTokens.accessToken)
            } catch {
                AppLog.info(" Proactive token refresh failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Polling

    private func pollAfterAction(expectingTrackChange: Bool = false) async {
        let trackIdBefore = currentTrack?.id
        // Give Spotify a moment to process the action
        try? await Task.sleep(for: .milliseconds(300))
        await pollPlayback()
        if expectingTrackChange, currentTrack?.id == trackIdBefore {
            try? await Task.sleep(for: .milliseconds(500))
            await pollPlayback()
        }
    }

    private func pollPlayback() async {
        await refreshTokenIfNeeded()

        do {
            guard let state = try await SpotifyAPIService.shared.getCurrentPlayback() else {
                // No active device / nothing playing
                consecutiveEmptyPolls += 1
                if consecutiveEmptyPolls >= emptyPollThreshold {
                    // Only clear after several consecutive empty responses
                    currentTrack = nil
                    isPlaying = false
                }
                return
            }

            // We have a valid state — reset empty counter
            consecutiveEmptyPolls = 0

            let previousTrackId = currentTrack?.id
            let newTrack = state.item

            // Detect track change
            if newTrack?.id != previousTrackId {
                currentTrack = newTrack
                albumArtURL = newTrack?.album.bestImageURL
                smallAlbumArtURL = newTrack?.album.smallImageURL

                if let trackId = newTrack?.id {
                    await checkLiked(trackId: trackId)
                } else {
                    isLiked = false
                }
            }

            isPlaying = state.isPlaying
            durationMs = newTrack?.durationMs ?? 0
            shuffleState = state.shuffleState
            repeatMode = RepeatMode(rawValue: state.repeatState) ?? .off

            if let deviceVolume = state.device?.volumePercent, !isAdjustingVolume {
                // Enforce minimum audible volume once per session
                if deviceVolume < Self.minimumAudibleVolume && deviceVolume > 0 && !didCorrectLowVolume {
                    didCorrectLowVolume = true
                    AppLog.info("⚠️ Device volume \(deviceVolume)% below floor — raising to \(Self.minimumAudibleVolume)%")
                    volumePercent = Self.minimumAudibleVolume
                    persistVolume(Self.minimumAudibleVolume)
                    Task {
                        try? await SpotifyAPIService.shared.setVolume(Self.minimumAudibleVolume, deviceId: sdkDeviceId)
                    }
                } else {
                    volumePercent = deviceVolume
                    if deviceVolume >= Self.minimumAudibleVolume {
                        didCorrectLowVolume = false  // Reset once volume is normal
                    }
                    persistVolume(deviceVolume)
                }
            }

            // Correct progress drift (only when not user-dragging)
            if !isSeeking, let serverProgress = state.progressMs {
                progressMs = serverProgress
            }

        } catch APIError.notAuthenticated {
            isAuthenticated = false
            stopTimers()
        } catch APIError.premiumRequired {
            isPremiumError = true
        } catch {
            // Silently ignore transient network errors
        }
    }

    private func checkLiked(trackId: String) async {
        do {
            let results = try await SpotifyAPIService.shared.checkSaved(trackIds: [trackId])
            isLiked = results.first ?? false
        } catch {
            isLiked = false
        }
    }

    // MARK: - Playback Controls (REST API with device pinning)

    func togglePlayPause() async {
        await debounced("playPause") {
            do {
                if isPlaying {
                    try await SpotifyAPIService.shared.pause(deviceId: sdkDeviceId)
                } else {
                    try await SpotifyAPIService.shared.play(deviceId: sdkDeviceId)
                }
                isPlaying.toggle()
                await pollAfterAction()
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func skipNext() async {
        await debounced("skipNext") {
            do {
                try await SpotifyAPIService.shared.skipNext(deviceId: sdkDeviceId)
                await pollAfterAction(expectingTrackChange: true)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func skipPrevious() async {
        await debounced("skipPrevious") {
            do {
                try await SpotifyAPIService.shared.skipPrevious(deviceId: sdkDeviceId)
                await pollAfterAction(expectingTrackChange: true)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func seek(toMs ms: Int) async {
        await debounced("seek") {
            isSeeking = false
            progressMs = ms
            do {
                try await SpotifyAPIService.shared.seek(toMs: ms, deviceId: sdkDeviceId)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func setVolume(_ percent: Int) {
        volumePercent = percent
        persistVolume(percent)
        isAdjustingVolume = true
        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                try await SpotifyAPIService.shared.setVolume(percent, deviceId: sdkDeviceId)
            } catch {
                handlePlaybackError(error)
            }
            isAdjustingVolume = false
        }
    }

    func toggleShuffle() async {
        await debounced("shuffle") {
            let newState = !shuffleState
            shuffleState = newState
            do {
                try await SpotifyAPIService.shared.setShuffle(newState, deviceId: sdkDeviceId)
            } catch {
                shuffleState = !newState
                handlePlaybackError(error)
            }
        }
    }

    func cycleRepeat() async {
        await debounced("repeat") {
            let newMode = repeatMode.next()
            let oldMode = repeatMode
            repeatMode = newMode
            do {
                try await SpotifyAPIService.shared.setRepeat(newMode, deviceId: sdkDeviceId)
            } catch {
                repeatMode = oldMode
                handlePlaybackError(error)
            }
        }
    }

    func toggleLike() async {
        await debounced("like") {
            guard let trackId = currentTrack?.id else { return }
            let wasLiked = isLiked
            isLiked = !wasLiked
            do {
                if wasLiked {
                    try await SpotifyAPIService.shared.removeTrack(id: trackId)
                } else {
                    try await SpotifyAPIService.shared.saveTrack(id: trackId)
                }
            } catch {
                isLiked = wasLiked
                handlePlaybackError(error)
            }
        }
    }

    // MARK: - Albums

    /// Fetches data for the current library filter.
    func fetchLibrary() async {
        switch libraryFilter {
        case .albums:
            await fetchSavedAlbums()
        case .playlists:
            await fetchPlaylists()
        case .likedSongs:
            await fetchLikedSongs()
        case .recentlyPlayed:
            await fetchRecentlyPlayed()
        }
    }

    func fetchSavedAlbums() async {
        do {
            let response = try await SpotifyAPIService.shared.getSavedAlbums()
            savedAlbums = response.items
        } catch {}
    }

    func fetchPlaylists() async {
        do {
            let response = try await SpotifyAPIService.shared.getMyPlaylists()
            playlists = response.items
        } catch {}
    }

    func fetchLikedSongs() async {
        do {
            let response = try await SpotifyAPIService.shared.getSavedTracks()
            likedSongs = response.items
        } catch {}
    }

    func fetchRecentlyPlayed() async {
        do {
            let response = try await SpotifyAPIService.shared.getRecentlyPlayed()
            recentlyPlayed = response.items
        } catch {}
    }

    func playAlbum(_ album: SpotifyFullAlbum) async {
        await debounced("playContext") {
            do {
                try await SpotifyAPIService.shared.playAlbum(uri: album.uri, deviceId: sdkDeviceId)
                await pollAfterAction(expectingTrackChange: true)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func playPlaylist(_ playlist: SpotifyPlaylist) async {
        await debounced("playContext") {
            do {
                try await SpotifyAPIService.shared.playPlaylist(uri: playlist.uri, deviceId: sdkDeviceId)
                await pollAfterAction(expectingTrackChange: true)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    func playTrack(_ track: SpotifyTrack) async {
        await debounced("playContext") {
            do {
                try await SpotifyAPIService.shared.playTrack(uri: track.uri, deviceId: sdkDeviceId)
                await pollAfterAction(expectingTrackChange: true)
            } catch {
                handlePlaybackError(error)
            }
        }
    }

    // MARK: - Helpers

    var progressTimeString: String {
        "\(SpotifyTrack.formatTime(progressMs)) / \(SpotifyTrack.formatTime(durationMs))"
    }

    private func handlePlaybackError(_ error: Error) {
        if case APIError.premiumRequired = error {
            isPremiumError = true
        }
        errorMessage = error.localizedDescription
    }

    deinit {
        pollTimer?.invalidate()
        progressTimer?.invalidate()
        volumeDebounceTask?.cancel()
    }
}
