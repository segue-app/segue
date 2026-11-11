<p align="center"><img src="assets/brand/icon_256.png" width="128" alt="Segue"></p>

<h1 align="center">Segue</h1>

**One music player for everything you listen to.** Search YouTube and
SoundCloud at once, import your Spotify and Yandex Music playlists, and keep
your library in sync between your computer and your phone — free, open
source, no account and no server.

Segue runs on **Android, iOS, Windows, macOS and Linux** from one Flutter
codebase.

## Features

**Listen**
- One search across YouTube and SoundCloud, with source filters
- Artist and album pages, charts by genre, similar artists
- **My wave** — an endless mix from what you like, tuned by activity,
  character, mood and language
- Artist and track waves
- Import playlists from Spotify, Yandex Music, YouTube and SoundCloud by link
  (songs are matched on YouTube when they play)
- Downloads for offline listening, and your own music folders

**Sound**
- 10-band equalizer with presets, speed and pitch
- Smooth transitions between tracks
- Trim any track to the part you want
- Sleep timer that fades out

**Look and feel**
- Living background made of the cover's colours
- Lyrics that fill word by word, with a 3D side-by-side layout on wide
  screens, adjustable animation, and line-by-line translation
- Accent colour, fonts, sizes and motion are all yours to tune

**Your devices**
- Pair a phone and a computer on the same network with a code or a QR
- Likes, playlists and history stay in sync
- Hand playback over from one device to the other

**Integrations**
- Last.fm scrobbling (with your own API key)
- Discord "Listening to" status (Windows, Linux)
- Update check against GitHub releases
- Keyboard shortcuts: Space, ← →, ⌘/Ctrl + ← → ↑ ↓, M, L, ⌘/Ctrl + F

## Download

Builds are attached to every [release](../../releases).

| Platform | File |
| --- | --- |
| Android | `segue-android-arm64.apk` (most phones), `-armv7`, `-x86_64` |
| Windows | `segue-windows-x64.zip` — unzip and run `segue.exe` |
| Linux | `segue-linux-x64.tar.gz` — needs `libmpv` (`sudo apt install libmpv2`) |
| macOS | `segue-macos.zip` |

iOS builds need signing; build it yourself from source (below).

## Build from source

Requirements: [Flutter](https://flutter.dev) 3.47 or newer.

```sh
git clone https://github.com/segue-app/segue.git
cd segue
flutter pub get
flutter run                  # on a connected device or this computer
```

Release builds:

```sh
flutter build apk --release --split-per-abi   # Android
flutter build windows --release               # Windows
flutter build linux --release                 # Linux (apt install libmpv-dev)
flutter build macos --release                 # macOS (needs CocoaPods)
flutter build ios --release                   # iOS (needs signing)
```

Discord status needs an application id from
[discord.com/developers](https://discord.com/developers/applications):

```sh
flutter build windows --dart-define=DISCORD_CLIENT_ID=<your id>
```

## How it works

- **Playback** — [media_kit](https://github.com/media-kit/media-kit)
  (libmpv) on every platform, so the equalizer and effects are the same
  FFmpeg filters everywhere. A small loopback proxy keeps HLS streams on one
  connection and preloads the next track.
- **Sources** — YouTube through its player API, SoundCloud through its public
  web API. Metadata for the catalogue, charts and waves comes from Deezer's
  public API; those songs are matched on YouTube when they play.
- **Lyrics** — [LRCLIB](https://lrclib.net), with word timing estimated when
  the lyrics only have line timing.
- **Library** — SQLite on the device. Sync uses change counters and
  last-writer-wins per item, over the local network (Bonjour/mDNS).
- **Nothing is hosted.** Segue talks to the services directly from your
  device; there is no Segue server and no account.

```
lib/
  core/      sources, player, library, sync, catalog, lyrics, integrations
  ui/        screens, widgets, theme
test/        unit tests (`flutter test`; network tests: `--tags live`)
integration_test/   real playback and screenshot runs on a desktop
```

## Tests

```sh
flutter test --exclude-tags live            # fast, offline
flutter test --tags live                    # talks to the real services
flutter test integration_test/playback_test.dart -d macos   # real playback, muted
```

## Disclaimer

Segue is a client for content that is publicly available on the services it
connects to. It does not host, store or redistribute any media. Respect the
terms of those services and the rights of artists in your country.

## License

[GPL-3.0](LICENSE)
