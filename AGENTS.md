# AGENTS.md

## What this repo is
- Flutter federated plugin for **playback + recording** of Ogg Opus audio on **Android/iOS**.
- Public API is tiny: `OggOpusPlayer`, `OggOpusRecorder`, `PlayerState` in `lib/src/player.dart` and `lib/src/player_state.dart`.
- Dart side is a platform adapter with **no method channel**: Android calls Kotlin through JNI (jnigen), iOS calls the Swift `@objc` API through the Objective-C runtime (ffigen + `package:objective_c`). Native platforms implement the actual audio stack.

## Architecture (read in this order)
1. `lib/src/player.dart` (factory selection and API contract)
2. `lib/src/player_plugin_impl.dart`, `lib/src/recorder_plugin_impl.dart`, `lib/src/platform_event_router.dart` (id handler maps, event handling)
3. `android/src/main/kotlin/uz/plugin/ogg_record_player/OggRecordPlayerPlugin.kt`
4. `darwin/ogg_record_player/Sources/ogg_record_player/OggRecordPlayerPlugin.swift`
5. `example/lib/main.dart` (real usage patterns for session setup + lifecycle)

## Native API (JNI on Android, Objective-C on iOS)
- Android: `OggRecordPlayerApi.java` (`android/src/main/java/...`) is the only surface Dart sees: static methods plus callback interfaces (`PlayerListener`, `RecorderListener`, `CreateCallback`, `DurationCallback`, `DoneCallback`), primitives/`String`/`byte[]` only so jnigen reads it from source. It forwards to `OggRecordPlayerHost.kt` (per-engine players/recorders); `OggRecordPlayerPlugin.kt` is lifecycle only. Regenerate `lib/src/bindings/ogg_record_player_api.g.dart` with `dart run tool/jnigen.dart`; `consumer-rules.pro` keeps the facade through R8.
- iOS: `OggRecordPlayerApi.swift` (`@objc(OggRecordPlayerApi)` class methods + blocks) is the surface; `OggRecordPlayerPlugin.swift` is lifecycle only. `darwin/ogg_record_player/Sources/ogg_record_player_c/ogg_record_player_api.h` is a hand-written ObjC view of it and **must match the Swift signatures exactly** (selectors, types, block signatures; a mismatch crashes at runtime). It stays out of `include/`. `dart run tool/ffigen.dart` generates `lib/src/bindings/ogg_record_player_darwin.g.dart` and the block wrapper `ogg_record_player_darwin.m` (compiled by the pod / the `ogg_record_player_c` SPM target).
- Generated files are exempt from the 300-line rule; commit them after regenerating.
- `lib/src/ogg_record_player_android.dart` / `ogg_record_player_darwin.dart` implement `OggRecordPlayerPlatform`; `OggRecordPlayerPlatform.instance` picks by platform. Listener callbacks are async so native never blocks on Dart. Host tests cannot load the native bindings: tests install a fake platform.
- Failures are reported through `createFrom*` callbacks as `(code, message, details)`; Android `startRecord` returns the error code (`PERMISSION_DENIED`) instead of throwing.

## Cross-platform contract (historical channel names; the native API mirrors them)
- Dart → native methods: `createFromFile` (path), `createFromUrl` (http/https string), `createFromBytes` (`Uint8List`), `play`, `pause`, `stop`, `getDuration`, `setPlaybackSpeed`, `warmUp`, `createRecorder`, `startRecord`, `stopRecord`, `destroyRecorder`.
- Native → Dart callbacks: `onPlayerStateChanged`, `onRecorderCanceled`, `onRecorderStartFailed`, `onRecorderFinished`.
- `onPlayerStateChanged` state `4` means the player failed after creation (Android only for now); the payload then carries `errorCode`, one of the `createFrom*` codes. Both platforms send `onRecorderStartFailed` when a recorder cannot start after `startRecord` returned.
- `onRecorderCanceled` `reason` values are shared (`OggOpusRecorder.CancelledReason` / `OpusAudioRecorder.CANCEL_*`): `0` interruption (iOS session, Android audio-focus loss), `1` route lost its input (iOS), `2` microphone stopped delivering audio, `3` user/destroy, `4` unusable file (shorter than `MIN_DRAIN_SAMPLES` = 250 ms at 16 kHz, or an encoder write error). A canceled recording's file is deleted; a successful one is never reported with a file that was not drained.
- A Dart recorder id is reusable: every `startRecord` starts a fresh native session into the same path (Android `RecorderSlot.session`, iOS resets its counters in `record(for:)`), a `startRecord` during a recording is ignored, and only `destroyRecorder` removes the id. Dart's `start()` waits for a pending `stop()` so two sessions never share the file.
- Recordings stop by themselves after 3 minutes on both sides (`MAX_RECORD_DURATION` / `maxRecordingDuration`). Keep them equal.
- Android recording holds `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` instead of listening to the phone state: no `READ_PHONE_STATE` or other extra permission. `play` is ignored while a recording is active, on both platforms.
- The plugin has no logging on any side (no `debugPrint`, `developer.log`, `NSLog`, `Log.*` or `__android_log_*`); don't add it back. Failures surface only as exceptions/error states.
- Player/recorder instances are tracked by generated integer IDs on all sides (`playerEventHandlers`, `recorderEventHandlers`, `playerDictionary`, `players`, Android `RecorderRegistry`).

## Remote playback and errors
- `createFromUrl` uses one flow on every platform: `RemoteAudioLoader` (`RemoteAudioLoader.swift` / `RemoteAudioLoader.kt`) downloads fresh bytes for each new player, checks the `OggS` signature and plays from memory through the same path as `createFromBytes`. Never cache downloads on disk, reuse them across players or enable HTTP caching; URLs can be expiring S3 signed URLs. Keep the two implementations in sync.
- `createFromBytes` never touches disk: Darwin decodes with `op_open_memory` (`OggOpusReader(data:)`), Android plays through Media3 `ByteArrayDataSource` (`bytesMediaSource`). Both reject input without the `OggS` signature as `INVALID_FILE`.
- Downloads are capped at 32 MiB on both sides (`RemoteAudioLoader.MAX_BYTES` / `RemoteAudioLoader.maxBytes`) and fail as `IO_ERROR`. Keep the limits equal.
- Downloads time out after 30 s without data and 120 s in total (`TOTAL_TIMEOUT_MS` / `timeoutIntervalForResource`), failing as `NETWORK_ERROR`. Keep them equal.
- `createFrom*` failures use the same codes on both sides (`PlayerError` in Swift and Kotlin): `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `NETWORK_ERROR`, `HTTP_ERROR`, `INVALID_FILE`, `IO_ERROR`, `UNKNOWN`. Dart maps them to `OggOpusPlayerException`; recorder failures map to `OggOpusRecorderException`.
- Dart layering: `OggRecordPlayerPlatform` (platform interface) → `AndroidOggRecordPlayer` / `DarwinOggRecordPlayer` (the only places touching the native bindings, convert native failures to exceptions) → `player_plugin_impl.dart` / `recorder_plugin_impl.dart` (public classes) with `platform_event_router.dart` (one event subscription routed by id).

## Platform implementation boundaries
- Android playback uses Media3 ExoPlayer (`AudioPlayer.kt`), created lazily on the first `play` (or on `getDuration` when `OggOpusDuration` cannot read the duration from the container); don't create it eagerly per player again. Recording uses `AudioRecord` + JNI (`OpusAudioRecorder.kt` + `android/src/main/cpp/audio.c`; JNI externals must stay in that class, helpers are `RecorderAudioFocus`, `RecorderQueues`, `WaveformSampler`, `RecorderRegistry`).
- iOS playback uses `AudioQueue` + `OggOpusReader` (`OggOpusPlayer.swift`, `OggOpusReader.swift`).
- `OggOpusPlayback` buffer state stays on `processingQueue`, but synchronous `AudioQueueStop`/`AudioQueueDispose` must run outside that callback queue. Stops from inside the callback queue must be asynchronous to avoid blocking callbacks and freezing the UI.
- iOS recording uses `AudioUnit` (RemoteIO) + `OggOpusWriter` + custom `AudioSession` arbitration on iOS (`OggOpusRecorder.swift`, `darwin/ogg_record_player/Sources/ogg_record_player/AudioSession/*`).
- Apple platforms use a unified `darwin/` directory with `sharedDarwinSource: true` in `pubspec.yaml`, supporting both CocoaPods (`darwin/ogg_record_player.podspec`) and Swift Package Manager (`darwin/ogg_record_player/Package.swift`).
- Apple platforms ship prebuilt universal multi-platform xcframeworks (`libogg`, `libopus`, `libopusenc`, `libopusfile`) with slices for iOS device (arm64), iOS simulator (arm64 + x86_64). Android links static opus/ogg libs through CMake (`android/src/main/cpp/CMakeLists.txt`).

## Critical behavior to preserve
- Source files stay at 300 lines or fewer (Dart, Swift, Kotlin); split by responsibility before a file grows past that.
- Dart player creation is async via `scheduleMicrotask`; state transitions depend on native callbacks (`lib/src/player_plugin_impl.dart`).
- `currentPosition` is extrapolated from the last callback's position + playback rate, timed with a Dart `Stopwatch` reset on each `onPlayerStateChanged`, rather than polling native every frame.
- Recorder `stop()` waits for `onRecorderFinished` / `onRecorderCanceled` (`_stopCompleter`) before data is readable.
- Waveform shape differs by platform: Android returns packed 5-bit data from C (`getWaveform2`), iOS returns 100 intensity bytes from Swift.
- Audio durations and playback positions exposed through the public API or native playback contract must use `double` seconds (Kotlin `Double`, Swift `Double`/`Float64`), preserving fractional seconds on both Android and iOS. `getDuration()` must return `Future<double?>` throughout Dart's public API, platform interface and both platform adapters; never truncate it to `int`/`Int` or round it. Recorder finish metadata remains integer milliseconds internally and is converted to `double` seconds for the public recorder API.
- `getDuration()` must return `null` when the player was not created or its duration is unavailable. Never substitute `0`/`0.0` for an unknown duration: callers must be able to distinguish missing metadata from a real zero-second duration.

## Developer workflows
- **Do not build iOS/Android** (`flutter build ...`, `xcodebuild`, Gradle, `flutter run`) to verify changes. The maintainer builds and tests on devices themselves; stop after `flutter analyze` and report what still needs device testing.
- Main local smoke test: run example app (`example/lib/main.dart`) and verify play, pause, speed toggle, record/stop.
- On-device e2e tests use Patrol (`example/patrol_test/`, `patrol_cli` 4.x): `cd example && patrol test -d <device id>`, or `-t patrol_test/<file>.dart` for one file. They build the app, so run them only when the maintainer asks. On iOS the `RunnerUITests` target hosts them.
- Useful commands from repo root:
  - `flutter analyze`
  - `flutter test`
  - `cd example && flutter run`
- Rebuild Apple vendored audio libs with `darwin/build-all.sh` (calls `build-libogg.sh`, `build-libopus*.sh`).

## Project-specific conventions / watch-outs
- Lints come from `analysis_lints` (`analysis_options.yaml`), so keep code style aligned with those rules.
- Version is mirrored across `pubspec.yaml`, Android `build.gradle.kts`, and Darwin podspec.
- README and Gradle (`android/build.gradle.kts`) both say Android `minSdk 26`; change them together.
- Prefer following existing method names and callback payload keys exactly; Dart/native parsing is string-key and brittle to renames.

