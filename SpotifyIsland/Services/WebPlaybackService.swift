import Foundation
import WebKit
import AppKit

/// Embeds a hidden WKWebView running the Spotify Web Playback SDK.
/// The SDK acts as an audio output device only — all playback control
/// goes through the REST API with the SDK's device_id pinned.
@MainActor
final class WebPlaybackService: NSObject, ObservableObject {
    static let shared = WebPlaybackService()

    private var webView: WKWebView?
    private var hiddenWindow: NSWindow?
    @Published var deviceId: String?
    @Published var isReady = false
    @Published var hasAuthError = false

    /// Called whenever the SDK reports a player state change (track change, pause, etc.)
    var onStateChanged: (() -> Void)?

    private var tokenProvider: (() async -> String?)?
    private var pendingToken: String?
    private var reconnectTask: Task<Void, Never>?
    private var connectRetryCount = 0
    private let maxConnectRetries = 3

    /// Prevents macOS App Nap from suspending our audio process.
    private var activityToken: NSObjectProtocol?

    /// Health monitoring — detects when WebContent process dies silently
    private var healthCheckTimer: Timer?
    private var lastHeartbeat = Date()
    private let healthCheckInterval: TimeInterval = 5.0
    private let heartbeatTimeout: TimeInterval = 15.0

    // MARK: - Public API

    func setup(tokenProvider: @escaping () async -> String?) {
        self.tokenProvider = tokenProvider
        connectRetryCount = 0
        hasAuthError = false
        reconnectTask?.cancel()

        // Clean up previous instance
        if let wv = webView {
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "spotifyCallback")
            wv.stopLoading()
        }

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(LeakAvoider(delegate: self), name: "spotifyCallback")

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = wv

        // WKWebView must be in a visible (non-suspended) window for audio.
        // Position on-screen but fully transparent so macOS doesn't suspend the WebProcess.
        if hiddenWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.alphaValue = 0.01  // Nearly invisible but macOS still considers it "visible"
            window.level = .init(rawValue: -1)  // Below everything
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.orderFrontRegardless()
            self.hiddenWindow = window
        }
        hiddenWindow?.contentView = wv

        // Prevent App Nap from suspending our audio playback process
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "SpotifyIsland audio playback via Web Playback SDK"
            )
        }

        AppLog.info("Loading Spotify Web Playback SDK...")
        let html = buildSDKPage(token: pendingToken ?? "")
        wv.loadHTMLString(html, baseURL: URL(string: "https://sdk.scdn.co"))

        startHealthCheck()
    }

    func updateToken(_ token: String) {
        pendingToken = token
        hasAuthError = false
        let escaped = token.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("if(typeof _updateToken==='function') _updateToken('\(escaped)')")
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopHealthCheck()
        webView?.evaluateJavaScript("if(typeof _disconnectPlayer==='function') _disconnectPlayer()")
        deviceId = nil
        isReady = false
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Health Monitoring

    private func startHealthCheck() {
        stopHealthCheck()
        lastHeartbeat = Date()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performHealthCheck()
            }
        }
    }

    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func performHealthCheck() {
        let timeSinceHeartbeat = Date().timeIntervalSince(lastHeartbeat)

        if timeSinceHeartbeat > heartbeatTimeout && isReady {
            AppLog.info("⚠️ No heartbeat for \(Int(timeSinceHeartbeat))s — WebContent may be dead, restarting SDK")
            isReady = false
            deviceId = nil
            fullRestart()
            return
        }

        // Also probe the WebView directly — if JS eval fails, the process is dead
        webView?.evaluateJavaScript("typeof _player !== 'undefined'") { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    AppLog.info("⚠️ WebView JS eval failed — process likely dead, restarting")
                    self.isReady = false
                    self.deviceId = nil
                    self.fullRestart()
                }
            }
        }
    }

    // MARK: - HTML Page

    /// The initial SDK volume (0.0–1.0). Set before calling setup().
    var initialVolumeFraction: Double = 0.3

    private func buildSDKPage(token: String) -> String {
        let escaped = token.replacingOccurrences(of: "'", with: "\\'")
        let vol = max(0.0, min(1.0, initialVolumeFraction))
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"></head>
        <body>
        <script>
        var _currentToken = '\(escaped)';
        var _pendingCb = null;
        var _player = null;

        function _updateToken(t) {
            _currentToken = t;
            if (_pendingCb) {
                _pendingCb(t);
                _pendingCb = null;
            }
        }

        function _disconnectPlayer() {
            if (_player) _player.disconnect();
        }

        function _post(obj) {
            try { window.webkit.messageHandlers.spotifyCallback.postMessage(obj); } catch(e) {}
        }

        window.onSpotifyWebPlaybackSDKReady = function() {
            _post({type:'log', message:'SDK loaded, creating player...'});
            createPlayer();
        };

        function createPlayer() {
            _player = new Spotify.Player({
                name: 'SpotifyIsland',
                getOAuthToken: function(cb) {
                    _pendingCb = cb;
                    _post({type:'getToken'});
                    // Fallback if native doesn't respond
                    setTimeout(function() {
                        if (_pendingCb && _currentToken) {
                            _pendingCb(_currentToken);
                            _pendingCb = null;
                        }
                    }, 5000);
                },
                volume: \(vol)
            });

            _player.addListener('ready', function(data) {
                _post({type:'ready', deviceId: data.device_id});
            });
            _player.addListener('not_ready', function(data) {
                _post({type:'not_ready', deviceId: data.device_id});
            });
            _player.addListener('initialization_error', function(data) {
                _post({type:'error', message:'init: ' + data.message});
            });
            _player.addListener('authentication_error', function(data) {
                _post({type:'error', message:'auth: ' + data.message});
            });
            _player.addListener('account_error', function(data) {
                _post({type:'error', message:'account: ' + data.message});
            });
            _player.addListener('player_state_changed', function(state) {
                // Notify native on EVERY state change (including null = track ended)
                _post({type:'state_changed', hasState: !!state});
            });
            _player.addListener('playback_error', function(data) {
                _post({type:'error', message:'playback: ' + data.message});
            });

            _player.connect().then(function(success) {
                _post({type:'connect_result', success: success});
            }).catch(function(err) {
                _post({type:'error', message:'connect error: ' + err});
            });
        }

        // Heartbeat — lets native side know the WebContent process is alive
        setInterval(function() {
            var state = 'no_player';
            if (_player) {
                _player.getCurrentState().then(function(s) {
                    _post({type:'heartbeat', playerState: s ? 'active' : 'idle'});
                }).catch(function() {
                    _post({type:'heartbeat', playerState: 'error'});
                });
            } else {
                _post({type:'heartbeat', playerState: state});
            }
        }, 4000);
        </script>
        <script src="https://sdk.scdn.co/spotify-player.js"></script>
        </body>
        </html>
        """
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }

            AppLog.info(" Attempting SDK reconnect...")
            if let freshToken = await self.tokenProvider?() {
                self.pendingToken = freshToken
                self.hasAuthError = false
                self.updateToken(freshToken)

                let escaped = freshToken.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    if (_player) {
                        _currentToken = '\(escaped)';
                        _player.disconnect();
                        setTimeout(function() {
                            _player.connect().then(function(ok) {
                                _post({type:'connect_result', success: ok});
                            });
                        }, 500);
                    }
                })();
                """
                try? await self.webView?.evaluateJavaScript(js)
            } else {
                AppLog.info(" Cannot reconnect — no valid token")
            }
        }
    }

    private func fullRestart() {
        AppLog.info(" Full SDK restart...")
        guard let provider = tokenProvider else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let freshToken = await provider() {
                self.pendingToken = freshToken
            }
            self.setup(tokenProvider: provider)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension WebPlaybackService: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            if let id = body["deviceId"] as? String {
                deviceId = id
                isReady = true
                hasAuthError = false
                connectRetryCount = 0
                AppLog.info(" SDK ready, device: \(id)")
            }

        case "not_ready":
            isReady = false
            AppLog.info(" SDK not ready — reconnecting")
            scheduleReconnect()

        case "connect_result":
            let success = body["success"] as? Bool ?? false
            AppLog.info(" connect() = \(success)")
            if !success {
                connectRetryCount += 1
                if connectRetryCount <= maxConnectRetries {
                    scheduleReconnect()
                } else {
                    connectRetryCount = 0
                    fullRestart()
                }
            }

        case "getToken":
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let token = await self.tokenProvider?() {
                    self.pendingToken = token
                    self.updateToken(token)
                }
            }

        case "error":
            let msg = body["message"] as? String ?? "unknown"
            AppLog.info(" SDK error: \(msg)")
            if msg.contains("auth:") || msg.contains("account:") {
                hasAuthError = true
                scheduleReconnect()
            }

        case "log":
            AppLog.info(" SDK: \(body["message"] as? String ?? "")")

        case "state_changed":
            // Immediately notify the view model to poll fresh state
            lastHeartbeat = Date()
            onStateChanged?()

        case "heartbeat":
            lastHeartbeat = Date()
            let playerState = body["playerState"] as? String ?? "unknown"
            if playerState == "error" {
                AppLog.info("💓 Heartbeat: player in error state — scheduling reconnect")
                scheduleReconnect()
            }

        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPlaybackService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        AppLog.info(" HTML loaded — SDK initializing...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        AppLog.info(" Navigation failed: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.fullRestart()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        AppLog.info(" Provisional navigation failed: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.fullRestart()
        }
    }
}

// MARK: - Prevent retain cycle

private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(uc, didReceive: message)
    }
}
