import SwiftUI

struct AlbumListView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Your Library")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Album list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.savedAlbums) { item in
                        albumRow(item.album)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private func albumRow(_ album: SpotifyFullAlbum) -> some View {
        Button {
            Task { await viewModel.playAlbum(album) }
        } label: {
            HStack(spacing: 10) {
                // Album art
                Group {
                    if let url = album.smallImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        albumPlaceholder
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Album info
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(album.artistName)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.001)) // ensures hit area
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.25))
            )
    }
}
