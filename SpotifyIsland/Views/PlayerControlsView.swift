import SwiftUI

private let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33) // #1DB954

struct PlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            albumArt
                .padding(.top, 16)

            trackInfo
                .padding(.top, 12)
                .padding(.horizontal, 16)

            progressSection
                .padding(.top, 14)
                .padding(.horizontal, 16)

            transportControls
                .padding(.top, 14)
                .padding(.horizontal, 16)

            bottomRow
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Album Art

    private var albumArt: some View {
        Group {
            if let url = viewModel.albumArtURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        albumArtPlaceholder
                    @unknown default:
                        albumArtPlaceholder
                    }
                }
            } else {
                albumArtPlaceholder
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
    }

    private var albumArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.06))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentTrack?.name ?? "Not Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(viewModel.currentTrack?.artistName ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                Text(viewModel.currentTrack?.album.name ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Spacer()

            // Like button
            Button {
                Task { await viewModel.toggleLike() }
            } label: {
                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundColor(viewModel.isLiked ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        ProgressBarView(
            progressMs: viewModel.progressMs,
            durationMs: viewModel.durationMs,
            isPlaying: viewModel.isPlaying,
            onSeekStart: {
                viewModel.isSeeking = true
            },
            onSeekComplete: { ms in
                Task { await viewModel.seek(toMs: ms) }
            }
        )
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            // Shuffle
            controlButton(
                systemImage: "shuffle",
                size: 16,
                color: viewModel.shuffleState ? spotifyGreen : .white.opacity(0.6)
            ) {
                Task { await viewModel.toggleShuffle() }
            }

            Spacer()

            // Previous
            controlButton(systemImage: "backward.fill", size: 20, color: .white) {
                Task { await viewModel.skipPrevious() }
            }

            Spacer()

            // Play / Pause (large)
            Button {
                Task { await viewModel.togglePlayPause() }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Spacer()

            // Next
            controlButton(systemImage: "forward.fill", size: 20, color: .white) {
                Task { await viewModel.skipNext() }
            }

            Spacer()

            // Repeat
            controlButton(
                systemImage: viewModel.repeatMode.systemImage,
                size: 16,
                color: viewModel.repeatMode.isActive ? spotifyGreen : .white.opacity(0.6)
            ) {
                Task { await viewModel.cycleRepeat() }
            }
        }
    }

    // MARK: - Bottom Row (Volume)

    private var bottomRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

            Slider(
                value: Binding(
                    get: { Double(viewModel.volumePercent) },
                    set: { val in
                        viewModel.setVolume(Int(val))
                    }
                ),
                in: 0...100
            )
            .tint(.white)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Helpers

    private func controlButton(
        systemImage: String,
        size: CGFloat,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}
