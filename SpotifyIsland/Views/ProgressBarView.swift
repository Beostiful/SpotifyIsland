import SwiftUI

struct ProgressBarView: View {
    let progressMs: Int
    let durationMs: Int
    let isPlaying: Bool
    let onSeekStart: () -> Void
    let onSeekComplete: (Int) -> Void

    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0
    @State private var isHovering = false

    private var fraction: CGFloat {
        guard durationMs > 0 else { return 0 }
        let f = isDragging ? dragProgress : CGFloat(progressMs) / CGFloat(durationMs)
        return max(0, min(1, f))
    }

    private var currentDisplay: String {
        if isDragging {
            let ms = Int(dragProgress * CGFloat(durationMs))
            return SpotifyTrack.formatTime(ms)
        }
        return SpotifyTrack.formatTime(progressMs)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let barHeight: CGFloat = 4

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: barHeight)

                    // Filled track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(0, width * fraction), height: barHeight)

                    // Thumb dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, width * fraction - 6))
                        .opacity(isHovering || isDragging ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isHovering || isDragging)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onSeekStart()
                            }
                            dragProgress = max(0, min(1, value.location.x / width))
                        }
                        .onEnded { value in
                            let finalProgress = max(0, min(1, value.location.x / width))
                            let seekMs = Int(finalProgress * CGFloat(durationMs))
                            isDragging = false
                            onSeekComplete(seekMs)
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
            }
            .frame(height: 12)

            // Time labels
            HStack {
                Text(currentDisplay)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(SpotifyTrack.formatTime(durationMs))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}
