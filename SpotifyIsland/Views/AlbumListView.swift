import SwiftUI

struct AlbumListView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    switch viewModel.libraryFilter {
                    case .albums:
                        ForEach(viewModel.savedAlbums) { item in
                            albumRow(item.album)
                        }
                    case .playlists:
                        ForEach(viewModel.playlists) { playlist in
                            playlistRow(playlist)
                        }
                    case .likedSongs:
                        ForEach(viewModel.likedSongs) { item in
                            trackRow(item.track)
                        }
                    case .recentlyPlayed:
                        ForEach(viewModel.recentlyPlayed) { item in
                            trackRow(item.track)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        Menu {
            ForEach(LibraryFilter.allCases, id: \.self) { filter in
                Button {
                    viewModel.libraryFilter = filter
                    Task { await viewModel.fetchLibrary() }
                } label: {
                    Label(filter.rawValue, systemImage: filter.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.libraryFilter.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text(viewModel.libraryFilter.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - Album Row

    private func albumRow(_ album: SpotifyFullAlbum) -> some View {
        Button {
            Task { await viewModel.playAlbum(album) }
        } label: {
            rowContent(
                imageURL: album.smallImageURL,
                title: album.name,
                subtitle: album.artistName,
                isRounded: false
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playlist Row

    private func playlistRow(_ playlist: SpotifyPlaylist) -> some View {
        Button {
            Task { await viewModel.playPlaylist(playlist) }
        } label: {
            rowContent(
                imageURL: playlist.smallImageURL,
                title: playlist.name,
                subtitle: playlist.ownerName,
                isRounded: false
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Track Row

    private func trackRow(_ track: SpotifyTrack) -> some View {
        Button {
            Task { await viewModel.playTrack(track) }
        } label: {
            rowContent(
                imageURL: track.album.smallImageURL,
                title: track.name,
                subtitle: track.artistName,
                isRounded: false
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Row Layout

    private func rowContent(
        imageURL: URL?,
        title: String,
        subtitle: String,
        isRounded: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: isRounded ? 20 : 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.001))
        )
        .contentShape(Rectangle())
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.25))
            )
    }
}
