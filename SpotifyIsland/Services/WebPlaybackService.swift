import Foundation
import WebKit
import AppKit

/// Embeds a hidden WKWebView running the Spotify Web Playback SDK.
/// This registers SpotifyIsland as a Spotify Connect device that can
/// play audio directly — no need for the Spotify desktop app.
@MainActor
final class WebPlaybackService: NSObject, ObservableObject {
    static let shared = WebPlaybackService()

    private var webView: WKWebView?
    private var hiddenWindow: NSWindow?
    @Published var deviceId: String?
    @Published var isReady = false

    private var tokenProvider: (() async -> String?)?
    private var pendingToken: String?

    func setup(tokenProvider: @escaping () async -> String?) {
        self.tokenProvider = tokenProvider

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

        // WKWebView must be in a window for macOS to allow audio playback
        if hiddenWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 300),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.orderBack(nil)
            self.hiddenWindow = window
        }
        hiddenWindow?.contentView = wv

        // Navigate to the SDK CDN origin so script loading is same-origin
        let sdkPageURL = URL(string: "https://sdk.scdn.co/spotify-player.js")!
        NSLog("[SpotifyIsland] Loading Spotify Web Playback SDK...")
        wv.load(URLRequest(url: sdkPageURL))
    }

    func updateToken(_ token: String) {
        pendingToken = token
        webView?.evaluateJavaScript("if(typeof updateToken==='function') updateToken('\(token)')")
    }

    func disconnect() {
        webView?.evaluateJavaScript("if(typeof disconnectPlayer==='function') disconnectPlayer()")
        deviceId = nil
        isReady = false
    }

    /// Called after the SDK JS file finishes loading. We inject our player setup code.
    private func injectPlayerSetup() {
        let token = pendingToken ?? ""

        let js = """
        (function() {
            // We're on the SDK page — the SDK script is already loaded.
            // Set up globals and the player.
            window.currentToken = '\(token)';

            window.updateToken = function(t) { window.currentToken = t; };
            window.disconnectPlayer = function() { if(window.spotPlayer) window.spotPlayer.disconnect(); };

            function initPlayer() {
                if (typeof Spotify === 'undefined' || !Spotify.Player) {
                    // SDK defines onSpotifyWebPlaybackSDKReady callback
                    window.onSpotifyWebPlaybackSDKReady = function() { createPlayer(); };
                    // Also load SDK again in case we navigated to the raw JS
                    var s = document.createElement('script');
                    s.src = 'https://sdk.scdn.co/spotify-player.js';
                    document.head.appendChild(s);
                } else {
                    createPlayer();
                }
            }

            function createPlayer() {
                window.webkit.messageHandlers.spotifyCallback.postMessage({type:'log', message:'Creating player...'});

                var player = new Spotify.Player({
                    name: 'SpotifyIsland',
                    getOAuthToken: function(cb) {
                        if (window.currentToken) {
                            cb(window.currentToken);
                        } else {
                            window.webkit.messageHandlers.spotifyCallback.postMessage({type:'getToken'});
                            setTimeout(function() { if(window.currentToken) cb(window.currentToken); }, 1000);
                        }
                    },
                    volume: 0.5
                });
                window.spotPlayer = player;

                player.addListener('ready', function(data) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'ready', deviceId: data.device_id});
                });
                player.addListener('not_ready', function(data) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'not_ready', deviceId: data.device_id});
                });
                player.addListener('initialization_error', function(data) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'error', message:'init: ' + data.message});
                });
                player.addListener('authentication_error', function(data) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'error', message:'auth: ' + data.message});
                });
                player.addListener('account_error', function(data) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'error', message:'account: ' + data.message});
                });
                player.addListener('player_state_changed', function(state) {
                    if (state) {
                        window.webkit.messageHandlers.spotifyCallback.postMessage({type:'state_changed'});
                    }
                });

                player.connect().then(function(success) {
                    window.webkit.messageHandlers.spotifyCallback.postMessage({type:'log', message:'connect() result: ' + success});
                });
            }

            initPlayer();
        })();
        """

        webView?.evaluateJavaScript(js) { result, error in
            if let error {
                NSLog("[SpotifyIsland] JS injection error: \(error.localizedDescription)")
            }
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
                NSLog("[SpotifyIsland] Web Playback SDK ready, device: \(id)")
            }
        case "not_ready":
            isReady = false
            NSLog("[SpotifyIsland] Web Playback SDK not ready")
        case "getToken":
            Task {
                if let token = await tokenProvider?() {
                    pendingToken = token
                    updateToken(token)
                }
            }
        case "error":
            let msg = body["message"] as? String ?? "unknown"
            NSLog("[SpotifyIsland] Web Playback SDK error: \(msg)")
        case "log":
            let msg = body["message"] as? String ?? ""
            NSLog("[SpotifyIsland] SDK: \(msg)")
        case "state_changed":
            break // Handled by API polling
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPlaybackService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[SpotifyIsland] Page loaded, injecting player setup...")
        // Small delay to ensure the SDK script is parsed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.injectPlayerSetup()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[SpotifyIsland] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[SpotifyIsland] Provisional navigation failed: \(error.localizedDescription)")
        // The raw JS file URL might fail to render as a page.
        // Load a blank page instead and inject the SDK via script tag.
        NSLog("[SpotifyIsland] Falling back to blank page + script injection...")
        let blankHTML = """
        <!DOCTYPE html><html><head></head><body>
        <script src="https://sdk.scdn.co/spotify-player.js"></script>
        </body></html>
        """
        webView.loadHTMLString(blankHTML, baseURL: nil)
    }
}

// MARK: - Prevent retain cycle with message handler

private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
