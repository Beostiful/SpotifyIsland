import SwiftUI

struct IslandView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onOpenSettings: () -> Void
    let menuBarHeight: CGFloat

    // MARK: - Layout Constants

    private let kCollapsedWidth: CGFloat = 340
    private let kCollapsedHeight: CGFloat = 42
    private let kExpandedWidth: CGFloat = 680

    private var expandedHeight: CGFloat {
        kCollapsedHeight + 1 + 430
    }

    var body: some View {
        VStack(spacing: 0) {
            pillBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pill Body

    private let profileURL = URL(string: "https://web.facebook.com/beostiful/")!

    /// Loads the author avatar from ~/Applications/SpotifyIsland.app/../avatar.png
    /// or a known local path.
    private static let avatarImage: NSImage? = {
        // Try next to the app bundle first
        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() {
            let beside = bundlePath.deletingLastPathComponent().appendingPathComponent("avatar.png")
            if let img = NSImage(contentsOf: beside) { return img }
        }
        // Try a fixed config path
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spotifyisland/avatar.png")
        if let img = NSImage(contentsOf: configPath) { return img }
        return nil
    }()

    private var pillBody: some View {
        VStack(spacing: 0) {
            ZStack {
                // Collapsed: album art + time
                headerRow
                    .opacity(viewModel.isExpanded ? 0 : 1)

                // Expanded: avatar + author
                if viewModel.isExpanded {
                    authorBar
                        .transition(.opacity)
                }
            }
            .frame(height: kCollapsedHeight)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isExpanded)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(viewModel.isExpanded ? 0.12 : 0))
                .frame(height: 0.5)
                .animation(.spring(response: 0.35, dampingFraction: 1.0), value: viewModel.isExpanded)

            // Expanded content
            if viewModel.isExpanded {
                Group {
                    if !viewModel.isAppConfigured {
                        setupPrompt
                    } else if viewModel.isAuthenticated {
                        expandedContent
                    } else {
                        LoginView(onLogin: viewModel.login)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(
            width: viewModel.isExpanded ? kExpandedWidth : kCollapsedWidth,
            height: viewModel.isExpanded ? expandedHeight : kCollapsedHeight,
            alignment: .top
        )
        .background(notchBackground)
        .clipped()
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                viewModel.isExpanded = hovering
            }
        }
        .contextMenu {
            Button("Settings…", action: onOpenSettings)
            Divider()
            if viewModel.isAuthenticated {
                Button("Logout") {
                    Task { await viewModel.logout() }
                }
            } else {
                Button("Login with Spotify", action: viewModel.login)
            }
            Divider()
            Button("Quit SpotifyIsland") {
                NSApplication.shared.terminate(nil)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1.0), value: viewModel.isExpanded)
    }

    // MARK: - Expanded Content (Albums + Player)

    private var expandedContent: some View {
        HStack(spacing: 0) {
            // Left: Album list
            AlbumListView(viewModel: viewModel)
                .frame(width: kExpandedWidth - kCollapsedWidth)

            // Vertical divider
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 0.5)

            // Right: Player controls
            PlayerControlsView(viewModel: viewModel)
                .frame(width: kCollapsedWidth - 1)
        }
    }

    // MARK: - Notch Background

    private var notchBackground: some View {
        NotchShape(
            earWidth: 5,
            earHeight: 10,
            bottomRadius: viewModel.isExpanded ? 18 : 14
        )
        .fill(Color.black)
    }

    // MARK: - Author Bar (Expanded)

    private var authorBar: some View {
        HStack(spacing: 0) {
            // Left: Author avatar
            Group {
                if let nsImage = Self.avatarImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())

            Spacer()

            // Right: Author credit
            HStack(spacing: 4) {
                Text("Author:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                Button {
                    NSWorkspace.shared.open(profileURL)
                } label: {
                    Text("@Beostiful")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .underline(color: .white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Header Row (Collapsed)

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left: album art
            albumArtThumbnail

            Spacer()

            // Right: current time
            timeLabel
        }
        .padding(.horizontal, 12)
    }

    private var albumArtThumbnail: some View {
        Group {
            if let url = viewModel.smallAlbumArtURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        musicIconPlaceholder
                    }
                }
            } else {
                musicIconPlaceholder
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var musicIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.1))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.white.opacity(0.4))
            )
    }

    // MARK: - Setup Prompt (Not Configured)

    private var setupPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "gearshape.2")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.5))

            VStack(spacing: 6) {
                Text("Setup Required")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("Open Settings to configure your\nSpotify Developer credentials")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button(action: onOpenSettings) {
                Text("Open Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var trackNameLabel: some View {
        if !viewModel.isAppConfigured {
            Text("Setup Required")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        } else if !viewModel.isAuthenticated {
            Text("Sign in to Spotify")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        } else if let track = viewModel.currentTrack {
            Text(track.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        } else {
            Text("Not Playing")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if viewModel.isAuthenticated && viewModel.currentTrack != nil {
            Text(SpotifyTrack.formatTime(viewModel.progressMs))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        } else {
            Text("0:00")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.clear)
        }
    }
}
