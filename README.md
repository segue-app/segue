<p align="center">
  <a href="https://segue-app.github.io/segue/"><img src="assets/readme/en/hero.webp" width="100%" alt="Segue: one player for all your music, on desktop and phone"></a>
</p>

<p align="center">
  <a href="https://github.com/segue-app/segue/releases/latest"><img src="https://img.shields.io/github/v/release/segue-app/segue?label=release&color=ff9a76" alt="Latest release"></a>
  <a href="https://github.com/segue-app/segue/releases"><img src="https://img.shields.io/github/downloads/segue-app/segue/total?color=7b5cff" alt="Downloads"></a>
  <a href="https://github.com/segue-app/segue/actions/workflows/ci.yml"><img src="https://github.com/segue-app/segue/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20Android%20Auto%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-2b2b33" alt="Platforms">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/segue-app/segue?color=2b2b33" alt="License: GPL-3.0"></a>
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#all-features">Features</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="https://segue-app.github.io/segue/">Website</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <a href="https://github.com/segue-app/segue/releases/latest/download/segue-android-arm64.apk"><img src="assets/readme/en/btn-android.webp" width="196" alt="Download for Android"></a>
  <a href="https://github.com/segue-app/segue/releases/latest/download/segue-windows-x64.zip"><img src="assets/readme/en/btn-windows.webp" width="196" alt="Download for Windows"></a>
  <a href="https://github.com/segue-app/segue/releases/latest/download/segue-macos.zip"><img src="assets/readme/en/btn-macos.webp" width="196" alt="Download for macOS"></a>
  <a href="https://github.com/segue-app/segue/releases/latest/download/segue-linux-x64.tar.gz"><img src="assets/readme/en/btn-linux.webp" width="196" alt="Download for Linux"></a>
</p>

<p align="center"><sub>Free · open source · no account, no ads · updates itself</sub></p>

## Highlights

<p align="center">
  <img src="assets/readme/en/wave.webp" width="49%" alt="My wave: a mix that learns from you">
  <img src="assets/readme/en/import.webp" width="49%" alt="Import from Spotify, Yandex Music, YouTube and SoundCloud">
</p>

<p align="center">
  <img src="assets/readme/en/lyrics.webp" width="49%" alt="Word-by-word karaoke lyrics with translation">
  <img src="assets/readme/en/devices.webp" width="49%" alt="Laptop and phone as one player, end-to-end encrypted">
</p>

<p align="center">
  <img src="assets/readme/en/sound.webp" width="49%" alt="Tempo-matched crossfades and an equalizer">
  <img src="assets/readme/en/auto.webp" width="49%" alt="Android Auto: wave, likes and playlists in the car">
</p>

## Why Segue

- **Everything in one place.** One search across YouTube and SoundCloud, and
  your playlists and likes from Spotify and Yandex Music.
- **Yours, not a service's.** No account, no subscription, no Segue server.
  Your library is a file on your device.
- **All your devices as one player.** Start on the laptop, continue on the
  phone at the same second, or use the phone as a remote.
- **In the car too.** Android Auto puts My wave, your likes and playlists
  on the car screen, with voice search.
- **In your language.** English and Russian, switched in Settings.
- **Light.** About 0.3% CPU when paused and no drawing at all while its window is
  hidden (measured on an Apple Silicon MacBook).

## Download

Get the latest build from **[Releases](https://github.com/segue-app/segue/releases/latest)**.
After the first install, Segue updates itself: **Settings → Update**.

| Platform | File | Notes |
| --- | --- | --- |
| **Android** | `segue-android-arm64.apk` | Most phones. Older ones: `-armv7`; emulators: `-x86_64`. Works with [Android Auto](#all-features) |
| **Windows** | `segue-windows-x64.zip` | Unzip anywhere and run `segue.exe` |
| **macOS** | `segue-macos.zip` | Unzip and move to Applications. The app isn't notarized: the first time, right-click → **Open** |
| **Linux** | `segue-linux-x64.tar.gz` | Needs libmpv: `sudo apt install libmpv2` |

iOS has no prebuilt app (it needs Apple signing); you can
[build it from source](#build-from-source).

## A closer look

<p align="center">
  <img src="docs/screenshots/en/lyrics.jpg" width="100%" alt="Synced lyrics next to the cover on a desktop">
</p>

<p align="center">
  <img src="docs/screenshots/en/phone-home.jpg" width="32%" alt="Home on a phone">
  <img src="docs/screenshots/en/phone-player.jpg" width="32%" alt="Now playing on a phone">
  <img src="docs/screenshots/en/phone-lyrics.jpg" width="32%" alt="Synced lyrics on a phone">
</p>

## All features

<details open>
<summary><b>Listen</b></summary>

- **One search** across YouTube and SoundCloud, with source filters
- Artist and album pages, charts by genre, similar artists
- **My wave**: an endless mix that learns from you. Songs you play to the
  end bring more of that artist, songs you skip bring less, and 👎 removes
  a song for good. Tune it by activity, mood, character and language
- **Radios** by genre and mood, and **smart playlists** that fill
  themselves: On repeat, Not heard in a while, This month's likes
- **Import** playlists by link from Spotify, Yandex Music, YouTube and
  SoundCloud, or your whole library (a Yandex Music profile, Spotify via
  Exportify or your data export). Imported songs are matched to the right
  version automatically, and you can pick another one by hand
- **Offline**: download what you want, and the songs you played recently are
  kept on the device by themselves (they start at once and play without
  internet)
- Your own music folders
- **Share a song** as a short link: it opens in Segue, or on a web page
  with the cover and a YouTube player for anyone without the app

</details>

<details>
<summary><b>Sound</b></summary>

- **Gapless playback**: live albums and mixes flow without a pause
- **DJ-style mixing**: overlapping crossfades with the next song brought to
  the current tempo, spoken intros and end skits of music videos skipped
- **Even loudness**: quiet and loud tracks play at the same level
- 10-band equalizer with presets, speed and pitch
- Trim any track to the part you want
- Sleep timer that fades out

</details>

<details>
<summary><b>Lyrics</b></summary>

- **Word-by-word** highlighting, karaoke style, when timing is available;
  line-by-line otherwise
- Line-by-line translation
- A 3D side-by-side layout on wide screens; animation, size and glow are
  adjustable

</details>

<details>
<summary><b>Your devices</b></summary>

- **Pair** with an 8-character code or a QR, on any network (Wi-Fi or
  mobile data)
- **Sync**: likes, playlists with their order, and history
- **Connect**: see what plays where, move the music with one tap and it
  continues at the same moment; the player on one device is the remote for
  another
- **Listen together**: share a code and friends hear the same song at the
  same second on their own devices, and add to the shared queue
- **Shared playlists**: invite friends to a playlist and everyone's edits
  appear for all
- **Backup**: save your whole library (likes, playlists, history,
  settings and what My wave learnt) to a file and restore it on any device

</details>

<details>
<summary><b>Desktop and home screen</b></summary>

- MacBook **living notch**: now playing around the camera; hover for
  controls, scroll for volume, swipe to skip
- Desktop now-playing card on macOS, home-screen widget on Android
- Keyboard shortcuts:

  | Key | Action |
  | --- | --- |
  | `Space` | Play / pause |
  | `←` `→` | Seek 5 seconds |
  | `⌘/Ctrl` + `←` `→` | Previous / next track |
  | `⌘/Ctrl` + `↑` `↓` | Volume |
  | `M` | Mute |
  | `L` | Like |
  | `⌘/Ctrl` + `F` | Search |

</details>

<details>
<summary><b>In the car (Android Auto)</b></summary>

- My wave, liked songs, playlists and recent plays on the car screen
- A song you pick plays with the rest of its list
- Search and voice: "play … on Segue" looks in your library first, then
  on YouTube; "play Segue" starts My wave

Android Auto shows apps from Google Play only, so allow Segue once: in
Android Auto's settings on the phone, tap **Version** 10 times, then
**⋮ → Developer settings → Unknown sources**.

</details>

<details>
<summary><b>Integrations</b></summary>

- Last.fm scrobbling (with your own API key)
- Discord "Listening to" status (Windows, Linux)
- In-app updates from GitHub releases

</details>

## Privacy

- **No account and no Segue server.** The app talks to the music services
  directly from your device.
- **No analytics, no ads, no tracking.**
- **Sync is end-to-end encrypted.** Across networks it goes through public
  MQTT brokers, which only see random topic names and AES-256-GCM
  ciphertext; the key exists only on your devices. On the same Wi-Fi the
  devices talk to each other directly.

## How it works

<p align="center">
  <img src="assets/readme/en/arch.webp" width="100%" alt="Diagram: music sources, the Segue app (player, matching, library) and sync with your other devices">
</p>

| Part | How |
| --- | --- |
| **Playback** | [media_kit](https://github.com/media-kit/media-kit) (libmpv) on every platform, so the equalizer and effects are the same FFmpeg filters everywhere. A loopback proxy keeps HLS streams on one connection and preloads the next track; the next song is queued inside mpv for gapless playback |
| **Sources** | YouTube through its player API, SoundCloud through its public web API. The catalogue, charts, waves and album covers come from Deezer's public API; those songs are matched on YouTube when they play |
| **Matching** | An imported song is found by title, artist and length, preferring the artist's own channel and rejecting covers, live versions and remixes. The chosen version travels with the song when playback moves to another device |
| **Lyrics** | Word timing from NetEase Cloud Music when it has the song, line timing from [LRCLIB](https://lrclib.net) otherwise; both are checked against title, artist and length |
| **Library** | SQLite on the device. Sync merges per item; the newest change wins |
| **Sync** | Bonjour/mDNS on the local network; across networks, two public MQTT brokers at once (HiveMQ and EMQX), so either can be down. Invite codes are stretched with PBKDF2 and expire after 10 minutes |
| **Performance** | Decorative motion runs on one shared 30 fps beat and stops when paused or out of sight; covers are cached on disk and fetched at the size shown |

```
lib/
  core/      sources, player, library, sync, catalog, lyrics, integrations
  ui/        screens, widgets, theme
test/                unit tests
integration_test/    real playback (muted) and screenshot runs on a desktop
```

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

<details>
<summary>Optional build settings</summary>

**Discord status** needs an application id from
[discord.com/developers](https://discord.com/developers/applications):

```sh
flutter build windows --release --dart-define=DISCORD_CLIENT_ID=<your id>
```

**Android signing.** Without a key the APK is signed with debug keys. For
your own permanent key, create `android/key.properties`:

```properties
storeFile=/path/to/your.jks
storePassword=...
keyAlias=...
keyPassword=...
```

</details>

## Tests

```sh
flutter test --exclude-tags live            # fast, offline
flutter test --tags live                    # talks to the real services
flutter test integration_test/playback_test.dart -d macos   # real playback, muted
```

## Contributing

Issues and pull requests are welcome. Before opening a pull request, please
run `flutter analyze` and `flutter test --exclude-tags live`; both must be
clean. For a bug, say which platform and version you're on and what you did
right before it happened.

## Disclaimer

Segue is a client for content that is publicly available on the services it
connects to. It does not host, store or redistribute any media. Respect the
terms of those services and the rights of artists in your country.

## License

[GPL-3.0](LICENSE)

<br>

<p align="center">
  <img src="assets/brand/segue_mark.svg" width="40" alt=""><br>
  <sub>Made with Flutter · <a href="https://segue-app.github.io/segue/">segue-app.github.io/segue</a></sub>
</p>
