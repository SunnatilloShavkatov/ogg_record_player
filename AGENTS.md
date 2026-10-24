# AGENTS.md

## What this repo is
- Flutter federated plugin for **playback + recording** of Ogg Opus audio on **Android/iOS/macOS**.
- Public API is tiny: `OggOpusPlayer`, `OggOpusRecorder`, `PlayerState` in `lib/src/player.dart` and `lib/src/player_state.dart`.
- Dart side is a MethodChannel adapter, native platforms implement the actual audio stack.

## Architecture (read in this order)
1. `lib/src/player.dart` (factory selection and API contract)
2. `lib/src/player_plugin_impl.dart` (channel protocol, id maps, event handling)
3. `android/src/main/kotlin/uz/plugin/ogg_opus_player/OggOpusPlayerPlugin.kt`
4. `darwin/ogg_record_player/Sources/ogg_record_player/OggOpusPlayerPlugin.swift`
5. `example/lib/main.dart` (real usage patterns for session setup + lifecycle)

## Cross-platform channel contract
- Channel name is fixed: `MethodChannel('ogg_record_player')`.
- Dart → native methods: `createFromFile` (path), `createFromUrl` (http/https string), `createFromBytes` (`Uint8List`), `play`, `pause`, `stop`, `getDuration`, `setPlaybackSpeed`, `createRecorder`, `startRecord`, `stopRecord`, `destroyRecorder`.
- Native → Dart callbacks: `onPlayerStateChanged`, `onRecorderCanceled`, `onRecorderStartFailed`, `onRecorderFinished`.
- Player/recorder instances are tracked by generated integer IDs on all sides (`_players`, `_recorders`, `playerDictionary`, `players`).

## Remote playback and errors
- `createFromUrl` uses one flow on every platform: `RemoteAudioCache` (`RemoteAudioCache.swift` / `RemoteAudioCache.kt`) downloads to `<caches>/ogg_record_player/<sha256(url)>.ogg`, checks the `OggS` signature, reuses the file for 7 days and purges expired files when the plugin registers. Keep the two implementations in sync.
- `createFromBytes` never touches disk: Darwin decodes with `op_open_memory` (`OggOpusReader(data:)`), Android plays through Media3 `ByteArrayDataSource` (`bytesMediaSource`). Both reject input without the `OggS` signature as `INVALID_FILE`.
- `createFrom*` failures use the same codes on both sides (`PlayerError` in Swift and Kotlin): `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `NETWORK_ERROR`, `HTTP_ERROR`, `INVALID_FILE`, `IO_ERROR`, `UNKNOWN`. Dart maps them to `OggOpusPlayerException`; recorder failures map to `OggOpusRecorderException`.
- Dart layering: `OggRecordPlayerPlatform` (platform interface) → `MethodChannelOggRecordPlayer` (only place touching the channel, converts `PlatformException`) → `player_plugin_impl.dart` (public classes, one event subscription routed by id).

## Platform implementation boundaries
- Android playback uses Media3 ExoPlayer (`AudioPlayer.kt`); recording uses `AudioRecord` + JNI (`OpusAudioRecorder.kt` + `android/src/main/cpp/audio.c`).
- iOS/macOS playback uses `AudioQueue` + `OggOpusReader` (`OggOpusPlayer.swift`, `OggOpusReader.swift`).
- iOS/macOS recording uses `AudioUnit` (RemoteIO on iOS, HALOutput on macOS) + `OggOpusWriter` + custom `AudioSession` arbitration on iOS (`OggOpusRecorder.swift`, `darwin/ogg_record_player/Sources/ogg_record_player/AudioSession/*`).
- Apple platforms use a unified `darwin/` directory with `sharedDarwinSource: true` in `pubspec.yaml`, supporting both CocoaPods (`darwin/ogg_record_player.podspec`) and Swift Package Manager (`darwin/ogg_record_player/Package.swift`).
- Apple platforms ship prebuilt universal multi-platform xcframeworks (`libogg`, `libopus`, `libopusenc`, `libopusfile`) with slices for iOS device (arm64), iOS simulator (arm64 + x86_64), and macOS (arm64 + x86_64). Android links static opus/ogg libs through CMake (`android/src/main/cpp/CMakeLists.txt`).

## Critical behavior to preserve
- Dart player creation is async via `scheduleMicrotask`; state transitions depend on native callbacks (`lib/src/player_plugin_impl.dart`).
- `currentPosition` is extrapolated from the last callback's position + playback rate, timed with a Dart `Stopwatch` reset on each `onPlayerStateChanged`, rather than polling native every frame.
- Recorder `stop()` waits for `onRecorderFinished` / `onRecorderCanceled` (`_stopCompleter`) before data is readable.
- Waveform shape differs by platform: Android returns packed 5-bit data from C (`getWaveform2`), iOS/macOS returns 100 intensity bytes from Swift.
- `getDuration` returns duration in seconds matching Android/iOS/macOS.

## Developer workflows
- **Do not build iOS/Android/macOS** (`flutter build ...`, `xcodebuild`, Gradle, `flutter run`) to verify changes. The maintainer builds and tests on devices themselves; stop after `flutter analyze` and report what still needs device testing.
- Main local smoke test: run example app (`example/lib/main.dart`) and verify play, pause, speed toggle, record/stop.
- Useful commands from repo root:
  - `flutter analyze`
  - `flutter test`
  - `cd example && flutter run` (or `flutter run -d macos`)
- Rebuild Apple vendored audio libs with `darwin/build-all.sh` (calls `build-libogg.sh`, `build-libopus*.sh`).

## Project-specific conventions / watch-outs
- Lints come from `analysis_lints` (`analysis_options.yaml`), so keep code style aligned with those rules.
- Version is mirrored across `pubspec.yaml`, Android `build.gradle.kts`, and Darwin podspec.
- README says Android `minSdk 24`, but Gradle config currently sets `minSdk = 26`; check both when changing platform requirements.
- Prefer following existing method names and callback payload keys exactly; Dart/native parsing is string-key and brittle to renames.

