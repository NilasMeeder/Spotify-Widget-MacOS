<div align="center">

# ◈ Spotify Widget

**A native macOS widget, menu bar player, and notch player for Spotify.**

Now-playing artwork as the backdrop, sliding track titles, playback controls, and Liked Songs: on your desktop, in your menu bar, or dropping out of your MacBook's notch.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-1ED760?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-1ED760?style=flat-square&logo=swift&logoColor=white)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-1ED760?style=flat-square)](#license)

</div>

<br>

## What it is

Spotify Widget is a lightweight, menu-bar-only macOS app (no Dock icon) built with SwiftUI and WidgetKit. It drives Spotify's desktop app directly, so a widget can show what's playing on the desktop or in Notification Center. The same controls are available from the menu bar or the notch.

**Features**

- 🎧 **Desktop widgets** in small and medium sizes, backed by the current track's artwork. Click a widget to open Spotify.
- 🎛 **Adjustable look.** Set the widget's transparency and greyscale in Settings, with a live preview.
- 🖥 **Notch player.** On a MacBook with a notch, hover the notch and a player drops out of it with the cover, track, a scrubber, and controls.
- 🪟 **Menu bar player.** A popover with the cover, a scrubber, controls, shuffle, and volume. The menu bar item can show the cover and the song title.
- ⚖️ **Notch or menu bar.** With the notch player on, the menu bar item becomes a plain menu, so the controls aren't in two places.
- ❤️ **Liked Songs.** Save or remove the current track through Spotify's Web API. Sign-in uses PKCE, and the app never sees your password.
- 🔁 **Open at login**, with one toggle.
- 🪶 **Light.** No polling while Spotify is paused or closed, and nothing runs while the notch player is collapsed.

<br>

## Requirements

| | |
|---|---|
| **macOS** | 14.0 (Sonoma) or later. The notch player needs a Mac with a notch. |
| **Spotify** | The Spotify desktop app. Playback is driven through Apple Events, so the web player won't work. |
| **Xcode** | 15 or later |
| **Apple ID** | Any Apple ID signed in to Xcode. A free account works. |

<br>

## Install

There's no download yet. A downloadable app has to be notarized, which needs a paid Apple Developer account, so for now you build it yourself. It takes a few minutes.

1. **Clone the repo**

   ```sh
   git clone https://github.com/NilasMeeder/Spotify-Widget-MacOS.git
   cd Spotify-Widget-MacOS
   ```

2. **Set your team**

   The widget shares data with the app through an App Group, and macOS requires its name to start with your team ID. Your team ID goes in a local file that git ignores:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Open `Config/Local.xcconfig` and replace `YOUR_TEAM_ID`. You can find it in Xcode → Settings → Accounts: select your Apple ID, then your team. It's also on [developer.apple.com/account](https://developer.apple.com/account) under Membership.

3. **Build**

   ```sh
   open SpotifyWidget.xcodeproj
   ```

   Select the **SpotifyWidget** scheme, choose **My Mac**, and press **⌘R** to try it. To keep it for good, choose **Product → Archive**, then **Distribute App → Custom → Copy App**, and move the copied `Spotify Widget.app` to `/Applications`.

4. **Add the widget**

   Right-click the desktop → **Edit Widgets** → search **Spotify Widget** → drag in the small or medium size.

> The `.xcodeproj` is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml` or adding files, run `brew install xcodegen` (once), then `xcodegen generate`.

<br>

## First run

1. Open the **Spotify** desktop app and play something.
2. Open **Spotify Widget**. An item appears in the menu bar.
3. macOS asks for **Automation access** so the app can read and control Spotify. If you missed the prompt, go to:

   ```
   System Settings → Privacy & Security → Automation → Spotify Widget → Spotify
   ```

4. Open **Settings** from the menu bar item to choose between the notch and the menu bar, adjust the widget's look, and turn on Open at login.

### Liked Songs (optional)

The like button needs a sign-in through Spotify's Web API. Spotify only lets an app's own users in while it's in development mode, so create your own Spotify app:

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and create an app.
2. Add the redirect URI `spotifywidget://callback`, and tick **Web API**.
3. Put its client ID in `Config/Local.xcconfig`:

   ```
   SPOTIFY_CLIENT_ID = your_client_id
   ```

4. Build again, then choose **Settings → Spotify account → Connect…**.

<br>

## How it works

```
┌─────────────────────┐        AppleScript / Apple Events        ┌──────────────┐
│   Spotify Widget    │ ───────────────────────────────────────▶ │  Spotify.app │
│ (menu bar + notch)  │ ◀─────────────────────────────────────── └──────────────┘
└──────────┬──────────┘        now playing · play/pause/skip
           │
           │  App Group (shared container)
           ▼
┌────────────────────────┐
│ SpotifyWidgetExtension │   WidgetKit timeline → desktop / Notification Center
└────────────────────────┘
```

- The app listens to Spotify's playback notifications and checks in every 15 seconds while music plays. It writes a snapshot (track, artwork, position, liked state) to a shared **App Group** container.
- The widget reads that snapshot. It never talks to Spotify itself.
- Widget buttons run an `AppIntent`, which signals the app over a Darwin notification to send the command. Clicking elsewhere on the widget opens the app through a `spotify-widget://` link, and the app brings Spotify forward.
- The notch player is a borderless panel above the menu bar. A tracking area picks up the hover, so it needs no Accessibility permission.
- Liked Songs uses Spotify's Web API over OAuth PKCE, since AppleScript can't touch your library.

<br>

## Project layout

```
SpotifyWidget/                 Menu bar app
  SpotifyWidgetApp.swift         App entry point; menu bar item (popover or menu)
  MenuBarPopover.swift           The popover: cover, scrubber, controls, volume
  NotchPlayer.swift              The notch player
  SettingsView.swift             Settings window
  PlayerController.swift         Refreshing, commands, publishing to the widget
  SpotifyProvider.swift          AppleScript bridge to Spotify.app
  SpotifyAccount.swift           OAuth (PKCE) and Liked Songs via the Web API
  ArtworkCache.swift             Downloads and caches album art
  CommandListener.swift          Receives commands from the widget

SpotifyWidgetExtension/        WidgetKit extension
  NowPlayingWidget.swift         Widget configuration and timeline provider
  Intents.swift                  AppIntents for play/pause/skip/like
  Views/NowPlayingView.swift     Widget UI (small and medium)

Shared/                        Used by both
  NowPlaying.swift               Snapshot written to the App Group
  SharedStore.swift              App Group read/write helpers
  SharedViews.swift              SlidingText, LikeIconShape
  AppSettings.swift              Preferences shared with the widget
  PlayerCommand.swift            Commands sent from widget to app
  AppGroup.swift                 App Group identifier

Config/                        Build settings; your own go in Local.xcconfig
project.yml                    XcodeGen project definition
```

<br>

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build fails with a signing or App Group error | Check that `Config/Local.xcconfig` exists and holds your team ID |
| Xcode says the bundle identifier is taken | Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` for both targets (the widget's must start with the app's), then run `xcodegen generate` |
| Widget shows "Needs access" | Grant Automation access: `System Settings → Privacy & Security → Automation → Spotify Widget → Spotify` |
| Widget shows "Spotify isn't open" | Open the Spotify desktop app |
| Widget doesn't change after a rebuild | macOS keeps the old widget running. Run `pkill SpotifyWidgetExtension`; it restarts by itself |
| Widget is stuck | Menu bar → **Reload Widget**, or quit and reopen Spotify Widget |
| Two Spotify Widgets in the widget gallery | One is Xcode's debug build. Delete it with **Product → Clean Build Folder** |
| No notch player | It only appears on a screen with a notch, with **Settings → Notch → Player in the notch** turned on |
| Liked Songs fails to connect | Use your own Spotify app's client ID, see [Liked Songs](#liked-songs-optional) |

<br>

## Credits

Spotify Widget was created by **[Kiran Prakash](https://github.com/geezkiran)**. The original project is at [geezkiran/Spotify-Widget-MacOS](https://github.com/geezkiran/Spotify-Widget-MacOS). It built the widget, the AppleScript bridge, and the Liked Songs sign-in.

This fork is maintained by **[Nilas Meeder](https://github.com/NilasMeeder)**. It adds the notch player, the menu bar popover, the settings window with the widget's look, and click-to-open.

<br>

## License

MIT, like the original project.

<br>

<div align="center">

Built with SwiftUI · WidgetKit · AppleScript · the Spotify Web API

</div>
