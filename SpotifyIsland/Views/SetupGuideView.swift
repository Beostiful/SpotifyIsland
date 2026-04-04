import SwiftUI
import AppKit

private let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)

struct SetupGuideView: View {
    @Binding var isConfigured: Bool
    @State private var clientIdInput = ""
    @State private var currentStep = 0
    @State private var showError = false
    @State private var errorText = ""

    private let steps: [(icon: String, title: String, detail: String)] = [
        (
            "1.circle.fill",
            "Create a Spotify Developer App",
            "Go to the Spotify Developer Dashboard and create a new app. Choose \"Web API\" when asked which APIs you'll use."
        ),
        (
            "2.circle.fill",
            "Add Redirect URI",
            "In your app settings, add this as a Redirect URI:"
        ),
        (
            "3.circle.fill",
            "Copy Your Client ID",
            "From your app's overview page, copy the Client ID and paste it below."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.top, 28)
                .padding(.bottom, 20)

            Divider()
                .background(Color.white.opacity(0.1))

            // Steps
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index: index, step: step)
                    }

                    // Client ID input
                    clientIdSection
                        .padding(.top, 4)
                }
                .padding(24)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Footer
            footer
                .padding(16)
        }
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            clientIdInput = AppConfig.clientId ?? ""
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [spotifyGreen, spotifyGreen.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Welcome to SpotifyIsland")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text("A few steps to get your notch player running")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Step Row

    private func stepRow(index: Int, step: (icon: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(spotifyGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(step.detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                // Step-specific extras
                if index == 0 {
                    linkButton(
                        title: "Open Spotify Developer Dashboard",
                        url: "https://developer.spotify.com/dashboard"
                    )
                }

                if index == 1 {
                    redirectURICopyBox
                }
            }
        }
    }

    // MARK: - Redirect URI Copy Box

    private var redirectURICopyBox: some View {
        HStack(spacing: 8) {
            Text(AppConfig.defaultRedirectURI)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AppConfig.defaultRedirectURI, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Client ID Section

    private var clientIdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spotify Client ID")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                TextField("Paste your Client ID here", text: $clientIdInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        showError ? Color.red.opacity(0.5) : Color.white.opacity(0.1),
                                        lineWidth: 0.5
                                    )
                            )
                    )
            }

            if showError {
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.leading, 40) // Align with step text
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Need help?") {
                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/documentation/web-api/tutorials/getting-started")!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.4))

            Spacer()

            Button(action: saveAndContinue) {
                HStack(spacing: 6) {
                    Text("Save & Continue")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(spotifyGreen)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func saveAndContinue() {
        let trimmed = clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            showError = true
            errorText = "Please enter your Spotify Client ID"
            return
        }

        // Basic validation — Spotify Client IDs are 32-char hex strings
        guard trimmed.count >= 20 else {
            showError = true
            errorText = "Client ID looks too short — check your Spotify Dashboard"
            return
        }

        showError = false
        AppConfig.clientId = trimmed
        isConfigured = true
    }

    // MARK: - Helpers

    private func linkButton(title: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) {
                NSWorkspace.shared.open(link)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(spotifyGreen)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
