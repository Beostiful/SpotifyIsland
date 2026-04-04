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

    // UI
    @Published var isSeeking = false
    @Published var errorMessage: String?
    @Published var isPremiumError = false

    // MARK: - Web Playback

    private let playbackService = WebPlaybackService.shared
    private var playbackCancellable: AnyCancellable?

    // MARK: - Timers

    private var pollTimer: Timer?
    private var progressTimer: Timer?

    // MARK: - Init

    init() {
        Task { await checkAuth() }
    }

    // MARK: - Auth

    func checkAuth() async {
        let tokens = await KeychainService.shared.loadTokens()
        isAuthenticated = tokens != nil
        if isAuthenticated {
            await startWebPlayback()
            startTimers()
            await pollPlayback()
            await fetchSavedAlbums()
        }
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
        guard let tokens = await KeychainService.shared.loadTokens() else { return }

        playbackService.setup { [weak self] in
            guard self != nil else { return nil }
            let t = await KeychainService.shared.loadTokens()
            if let t, t.isExpired {
                let refreshed = try? await SpotifyAuthService.shared.refreshAccessToken(refreshToken: t.refreshToken)
                return refreshed?.accessToken
            }
            return t?.accessToken
        }
        playbackService.updateToken(tokens.accessToken)

        // When the SDK is ready, transfer playback to this device
        playbackCancellable = playbackService.$deviceId
            .compactMap { $0 }
            .first()
            .sink { [weak self] deviceId in
                Task { [weak self] in
                    guard self != nil else { return }
                    try? await SpotifyAPIService.shared.transferPlayback(toDeviceId: deviceId)
                    NSLog("[SpotifyIsland] Transferred playback to local device: \(deviceId)")
                }
            }
    }

    // MARK: - Timers

    private func startTimers() {
        stopTimers()

        // Poll API every 2 seconds
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

    // MARK: - Polling

    private func pollPlayback() async {
        do {
            guard let state = try await SpotifyAPIService.shared.getCurrentPlayback() else {
                // No active device / nothing playing
                currentTrack = nil
                isPlaying = false
                return
            }

            let previousTrackId = currentTrack?.id
            let newTrack = state.item

            // Detect track change
            if newTrack?.id != previousTrackId {
                currentTrack = newTrack
                albumArtURL = newTrack?.album.bestImageURL
                smallAlbumArtURL = newTrack?.album.smallImageURL

                // Check liked status on track change
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

            if let deviceVolume = state.device?.volumePercent {
                volumePercent = deviceVolume
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

    // MARK: - Playback Controls

    func togglePlayPause() async {
        do {
            if isPlaying {
                try await SpotifyAPIService.shared.pause()
            } else {
                try await SpotifyAPIService.shared.play()
            }
            isPlaying.toggle()
        } catch {
            handlePlaybackError(error)
        }
    }

    func skipNext() async {
        do {
            try await SpotifyAPIService.shared.skipNext()
            // Poll immediately to get the new track
            try? await Task.sleep(nanoseconds: 500_000_000)
            await pollPlayback()
        } catch {
            handlePlaybackError(error)
        }
    }

    func skipPrevious() async {
        do {
            try await SpotifyAPIService.shared.skipPrevious()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await pollPlayback()
        } catch {
            handlePlaybackError(error)
        }
    }

    func seek(toMs ms: Int) async {
        isSeeking = false
        progressMs = ms
        do {
            try await SpotifyAPIService.shared.seek(toMs: ms)
        } catch {
            handlePlaybackError(error)
        }
    }

    func setVolume(_ percent: Int) async {
        do {
            try await SpotifyAPIService.shared.setVolume(percent)
        } catch {
            handlePlaybackError(error)
        }
    }

    func toggleShuffle() async {
        let newState = !shuffleState
        shuffleState = newState
        do {
            try await SpotifyAPIService.shared.setShuffle(newState)
        } catch {
            shuffleState = !newState
            handlePlaybackError(error)
        }
    }

    func cycleRepeat() async {
        let newMode = repeatMode.next()
        repeatMode = newMode
        do {
            try await SpotifyAPIService.shared.setRepeat(newMode)
        } catch {
            repeatMode = repeatMode.next().next() // roll back
            handlePlaybackError(error)
        }
    }

    func toggleLike() async {
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

    // MARK: - Albums

    func fetchSavedAlbums() async {
        do {
            let response = try await SpotifyAPIService.shared.getSavedAlbums()
            savedAlbums = response.items
        } catch {
            // Silently ignore — album list is non-critical
        }
    }

    func playAlbum(_ album: SpotifyFullAlbum) async {
        do {
            try await SpotifyAPIService.shared.playAlbum(uri: album.uri)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await pollPlayback()
        } catch {
            handlePlaybackError(error)
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
    }
}
