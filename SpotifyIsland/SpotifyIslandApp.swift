import SwiftUI
import AppKit

@main
struct SpotifyIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel = PlayerViewModel()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        setupFloatingPanel()
        registerURLSchemeHandler()

        // Listen for screen changes (external monitor connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Auto-open setup guide on first launch (no Client ID configured)
        if !AppConfig.isConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettings()
            }
        }
    }

    // Fallback URL handler — called by macOS when spotifyisland:// URL is opened
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "spotifyisland" {
                Task { await SpotifyAuthService.shared.receiveURLSchemeCallback(url) }
            }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "SpotifyIsland")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Login with Spotify",
            action: #selector(menuLogin),
            keyEquivalent: ""
        )
        menu.addItem(loginItem)

        let logoutItem = NSMenuItem(
            title: "Logout",
            action: #selector(menuLogout),
            keyEquivalent: ""
        )
        menu.addItem(logoutItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit SpotifyIsland",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
    }

    @objc private func menuLogin() {
        viewModel.login()
    }

    @objc private func menuLogout() {
        Task { await viewModel.logout() }
    }

    @objc private func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let isSetup = !AppConfig.isConfigured
        let size = isSetup ? NSRect(x: 0, y: 0, width: 520, height: 560) : NSRect(x: 0, y: 0, width: 380, height: 340)

        let window = NSWindow(
            contentRect: size,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = isSetup ? "SpotifyIsland Setup" : "SpotifyIsland Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false

        let settingsContent = SettingsContentView(viewModel: viewModel, window: window)
        window.contentView = NSHostingView(rootView: settingsContent.preferredColorScheme(.dark))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Floating Panel

    private func setupFloatingPanel() {
        let menuBarHeight = FloatingPanel.menuBarHeight
        let islandView = IslandView(
            viewModel: viewModel,
            onOpenSettings: { [weak self] in self?.openSettings() },
            menuBarHeight: menuBarHeight
        )
        WindowManager.shared.createPanel(content: islandView)
    }

    // MARK: - URL Scheme Handler (OAuth callback)

    private func registerURLSchemeHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }

        Task {
            await SpotifyAuthService.shared.receiveURLSchemeCallback(url)
        }
    }

    // MARK: - Screen Changes

    @objc private func screenParametersChanged() {
        WindowManager.shared.reposition()
    }
}

// MARK: - Settings View

private let settingsGreen = Color(red: 0.11, green: 0.73, blue: 0.33)

struct SettingsContentView: View {
    @ObservedObject var viewModel: PlayerViewModel
    weak var window: NSWindow?

    @State private var isConfigured = AppConfig.isConfigured

    var body: some View {
        Group {
            if isConfigured {
                settingsPanel
            } else {
                SetupGuideView(isConfigured: $isConfigured)
            }
        }
        .onChange(of: isConfigured) { _, configured in
            if configured {
                viewModel.refreshConfigState()
                window?.setContentSize(NSSize(width: 380, height: 340))
                window?.title = "SpotifyIsland Settings"
                window?.center()
            }
        }
    }

    // MARK: - Settings Panel (After Configuration)

    private var settingsPanel: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.7))

            Text("SpotifyIsland")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Divider()

            // Connection status
            if viewModel.isAuthenticated {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to Spotify")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }

                    Button("Logout") {
                        Task { await viewModel.logout() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Not connected")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))

                    Button("Login with Spotify") {
                        viewModel.login()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settingsGreen)
                }
            }

            Divider()

            // Client ID display
            VStack(alignment: .leading, spacing: 6) {
                Text("Spotify Client ID")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))

                HStack {
                    Text(maskedClientId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Button("Change") {
                        isConfigured = false
                        window?.setContentSize(NSSize(width: 520, height: 560))
                        window?.title = "SpotifyIsland Setup"
                        window?.center()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundColor(settingsGreen)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Text("Hover over the notch to control playback")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 380, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var maskedClientId: String {
        guard let id = AppConfig.clientId, id.count > 8 else { return "Not set" }
        let prefix = String(id.prefix(4))
        let suffix = String(id.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}
