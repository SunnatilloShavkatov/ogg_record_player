# AGENTS.md

## What this repo is
- Flutter federated plugin for **playback + recording** of Ogg Opus audio on **Android/iOS/macOS**.
- Public API is tiny: `OggOpusPlayer`, `OggOpusRecorder`, `PlayerState` in `lib/src/player.dart` and `lib/src/player_state.dart`.
- Dart side is a MethodChannel adapter, native platforms implement the actual audio stack.

## Architecture (read in this order)
1. `lib/src/player.dart` (factory selection and API contract)
2. `lib/src/player_plugin_impl.dart` (channel protocol, id maps, event handling)
3. `android/src/main/kotlin/uz/plugin/ogg_opus_player/OggOpusPlayerPlugin.kt`
4. `darwin/ogg_record_player/Sources/ogg_record_player/SwiftOggOpusPlayerPlugin.swift`
5. `example/lib/main.dart` (real usage patterns for session setup + lifecycle)

## Cross-platform channel contract
- Channel name is fixed: `MethodChannel('ogg_record_player')`.
- Dart → native methods: `create`, `play`, `pause`, `stop`, `getDuration`, `setPlaybackSpeed`, `createRecorder`, `startRecord`, `stopRecord`, `destroyRecorder`.
- Native → Dart callbacks: `onPlayerStateChanged`, `onRecorderCanceled`, `onRecorderStartFailed`, `onRecorderFinished`.
- Player/recorder instances are tracked by generated integer IDs on all sides (`_players`, `_recorders`, `playerDictionary`, `players`).

## Platform implementation boundaries
- Android playback uses Media3 ExoPlayer (`AudioPlayer.kt`); recording uses `AudioRecord` + JNI (`OpusAudioRecorder.kt` + `android/src/main/cpp/audio.c`).
- iOS/macOS playback uses `AudioQueue` + `OggOpusReader` (`OggOpusPlayer.swift`, `OggOpusReader.swift`).
- iOS/macOS recording uses `AudioUnit` (RemoteIO on iOS, HALOutput on macOS) + `OggOpusWriter` + custom `AudioSession` arbitration on iOS (`OggOpusRecorder.swift`, `darwin/ogg_record_player/Sources/ogg_record_player/AudioSession/*`).
- Apple platforms use a unified `darwin/` directory with `sharedDarwinSource: true` in `pubspec.yaml`, supporting both CocoaPods (`darwin/ogg_record_player.podspec`) and Swift Package Manager (`darwin/ogg_record_player/Package.swift`).
- Apple platforms ship prebuilt universal multi-platform xcframeworks (`libogg`, `libopus`, `libopusenc`, `libopusfile`) with slices for iOS device (arm64), iOS simulator (arm64 + x86_64), and macOS (arm64 + x86_64). Android links static opus/ogg libs through CMake (`android/src/main/cpp/CMakeLists.txt`).

## Critical behavior to preserve
- Dart player creation is async via `scheduleMicrotask`; state transitions depend on native callbacks (`lib/src/player_plugin_impl.dart`).
- `currentPosition` is computed from last callback timestamp + playback rate (`SystemClock.uptime`) rather than polling native every frame.
- Recorder `stop()` waits for `onRecorderFinished` / `onRecorderCanceled` (`_stopCompleter`) before data is readable.
- Waveform shape differs by platform: Android returns packed 5-bit data from C (`getWaveform2`), iOS/macOS returns 100 intensity bytes from Swift.
- `getDuration` returns duration in seconds matching Android/iOS/macOS.

## Developer workflows
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

