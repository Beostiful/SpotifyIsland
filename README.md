# SpotifyIsland

A macOS notch-style Spotify player that lives around your MacBook's notch — inspired by Dynamic Island.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)
[![Release](https://img.shields.io/github/v/release/Beostiful/SpotifyIsland?color=1DB954&logo=spotify)](https://github.com/Beostiful/SpotifyIsland/releases/latest)

<p align="center">
  <img src="assets/collapsed.png" alt="Collapsed view" width="400">
  <br><em>Collapsed — album art in the notch</em>
</p>

<p align="center">
  <img src="assets/expanded.png" alt="Expanded view" width="680">
  <br><em>Expanded — full player with album library</em>
</p>

## Features

- **Notch integration** — sits seamlessly around the MacBook notch
- **Collapsed view** — album art + current time, always visible
- **Expanded view** — hover to reveal full player with:
  - Album artwork and track info
  - Play/pause, skip, shuffle, repeat controls
  - Seek bar and volume slider
  - Like button
  - Library browser (Albums, Playlists, Liked Songs, Recently Played)
- **Standalone playback** — plays audio via Spotify Web Playback SDK, no Spotify desktop app needed
- **Easy setup** — built-in setup guide walks you through everything
- **OAuth 2.0 PKCE** — secure authentication, no client secret or server required

## Download

Grab the latest release:

> **[Download SpotifyIsland.zip](https://github.com/Beostiful/SpotifyIsland/releases/latest)**

### Install

1. Unzip and move `SpotifyIsland.app` to your Applications folder
2. Open Terminal and run:
   ```bash
   xattr -cr /Applications/SpotifyIsland.app
   ```
3. Double-click to open — the Setup Guide will appear automatically

> The `xattr` command is needed because the app isn't signed with an Apple Developer certificate. This is safe — you can [inspect the source code](https://github.com/Beostiful/SpotifyIsland) yourself.

## Requirements

- macOS 14+ (Sonoma) with a notched MacBook
- **Spotify Premium** account (required for playback control)
- A free Spotify Developer App (the setup guide walks you through this)

## Setup

The app includes a built-in setup guide, but here's the gist:

### 1. Create a Spotify Developer App

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
2. Click **Create App**
3. Fill in any name/description
4. Select **Web API** when asked which APIs to use
5. Add this **Redirect URI**: `spotifyisland://callback`
6. Save and copy your **Client ID**

### 2. Configure the App

When you first open SpotifyIsland, the Setup Guide will ask for your Client ID. Paste it in and click **Save & Continue**.

You can change it later from **Settings** (right-click the notch or use the menu bar icon).

### 3. Login

Click **Login with Spotify** — authorize on the web page and you're good to go.

## Usage

| Action | How |
|--------|-----|
| Expand player | Hover over the notch |
| Collapse | Move mouse away |
| Browse library | Use the dropdown filter in the left panel |
| Play an album/playlist/track | Click it in the left panel |
| Control playback | Use the transport controls |
| Adjust volume | Drag the volume slider |
| Like a track | Click the heart icon |
| Settings / Logout | Right-click the notch |

## Build from Source

```bash
git clone https://github.com/Beostiful/SpotifyIsland.git
cd SpotifyIsland

# Build, install to ~/Applications, and launch
make run
```

Or step by step:

```bash
swift build -c release
make install
open ~/Applications/SpotifyIsland.app
```

## Architecture

```
SpotifyIsland/
├── Models/          — Spotify API data models
├── Services/        — Auth (PKCE), API, Keychain, Web Playback
├── ViewModels/      — Player state management
├── Views/           — SwiftUI views (Island, Player, Albums, Login, SetupGuide)
└── Helpers/         — Floating panel, window management, logging, config
```

Key decisions:
- **NSPanel** at `.statusBar` level with passthrough hit testing
- **Actor-based services** for thread-safe API and auth
- **WKWebView** in a near-invisible window for Spotify Web Playback SDK audio
- **PKCE flow** with URL scheme callback — no client secret needed
- **Volume persistence** with safe minimum floor to prevent silent relaunches

## Troubleshooting

**No sound?**
Make sure Spotify isn't playing on another device. The app transfers playback to its built-in "SpotifyIsland" player on launch. Also check that the volume slider isn't too low.

**Login not working?**
Verify `spotifyisland://callback` is listed as a Redirect URI in your Spotify Developer Dashboard.

**"App is damaged" or "unidentified developer"?**
Run `xattr -cr /Applications/SpotifyIsland.app` in Terminal, then open again.

**Buttons not clickable?**
Right-click the notch → Quit, then relaunch.

## Author

Built by [@Beostiful](https://web.facebook.com/beostiful/)

## License

MIT
