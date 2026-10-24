## 2.5.0

### Added
- `OggOpusPlayer.warmUp()` pays the native playback setup ahead of the first player without activating the audio session: AudioQueue setup on iOS, the Opus decoder lookup on Android.

### Fixed
- **iOS:** Stop AudioQueue outside its callback queue and stop asynchronously on start failure to avoid blocking pending callbacks and freezing the UI.
- **iOS:** Stop every player and cancel every recorder when the Flutter engine detaches, matching Android.

### Changed
- URL playback downloads fresh audio into memory for every new player on Android and iOS. Removed the 7-day disk cache and shared downloads, and disabled HTTP caching for expiring signed URLs.
- Removed all plugin logging on Dart, iOS and Android, including Android's native `liblog` link.
- **Android:** No longer forces `useLegacyPackaging` on host apps; native libraries follow the app's own packaging setting.
- **Android:** Stripped debug info from the prebuilt opus/ogg static libraries (about 75% smaller package) and compile the JNI glue with `-Os`.

## 2.4.1

### Fixed
- Preserve fractional seconds in `getDuration()` on Android and iOS, and return `null` when the player was not created or duration is unavailable.

### Changed
- **Breaking:** `getDuration()` returns `Future<double?>` instead of `Future<int?>`. Update callers and platform implementations to use `double?`.

## 2.4.0

### Fixed
- Improved playback duration reporting and the example app's position and total duration display.
- **iOS:** Resume an interrupted player when iOS permits it, unless the user paused or disposed it during the interruption. Release the session synchronously to avoid a stale deactivation silencing resumed playback.
- **iOS:** Decode into fixed stereo buffers off the main thread, handle Ogg discontinuities without corrupting buffer offsets, and retain the last samples through completion. Remove a player callback retain cycle.
- **Android:** Keep the final playback position at completion and rewind only when replay is requested. Publish coherent state snapshots for buffering, audio focus and speed changes.

### Changed
- Removed unnecessary native playback and recording logs.
- Refreshed the example UI, moved the page into its own file, and removed the example's direct `path` dependency.
- **Android:** Use audio-only Media3 renderers and Ogg-only extraction for release code shrinking; discard unused native codec sections and exports. Arbitrate players within the plugin and release players/recorders on engine detach.
- **Darwin build scripts:** Omit debug information from future release codec builds, retaining LTO and optimized hot paths. Existing vendored archives are unchanged.

## 2.3.0

### Added
- `OggOpusPlayer.file(File)`, `OggOpusPlayer.url(url)` and `OggOpusPlayer.bytes(bytes)`, backed by separate native methods (`createFromFile`, `createFromUrl`, `createFromBytes`; the old `create` is gone). `OggOpusPlayer(path)` picks `url` or `file` from the scheme.
- `OggOpusPlayer.bytes` plays a whole Ogg Opus stream from memory, without a temporary file: `op_open_memory` on iOS, Media3 `ByteArrayDataSource` on Android.
- `OggOpusPlayer.url` downloads `http`/`https` URLs with the same flow on Android and iOS: the file is downloaded once into the cache directory (`ogg_record_player/<sha256 of the URL>.ogg`), played from disk and reused for 7 days, then deleted and downloaded again. Expired files are purged in the background when the plugin starts; concurrent players for the same URL share one download. Downloads that are not Ogg streams are rejected.
- `OggOpusPlayer.error`: an `OggOpusPlayerException` with a platform-independent `code` (`INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `NETWORK_ERROR`, `HTTP_ERROR`, `INVALID_FILE`, `IO_ERROR`, `UNKNOWN`) when the player could not be created.
- `OggRecordPlayerPlatform` (a `PlatformInterface`) with the default `MethodChannelOggRecordPlayer`; `OggOpusPlayer` and `OggOpusRecorder` no longer talk to the method channel directly.
- **Android**: the plugin declares the `INTERNET` permission. A missing local file now fails `create` with `FILE_NOT_FOUND` instead of producing an idle player.
- **Android**: Playback now takes audio focus (`USAGE_MEDIA`, speech content) instead of ignoring it. Starting a voice message pauses other apps' audio, and the player pauses when it loses the focus. A transient loss (for example a call) reports `PlayerState.paused` until playback resumes, so `currentPosition` no longer keeps advancing while the player is silent.
- **iOS**: Playback activates the shared `AVAudioSession` itself (`playback` category, `spokenAudio` mode) when it starts and deactivates it, notifying other apps, when it pauses, stops or ends. An interruption, a recording or another player taking the session pauses it, and `play()` does nothing while a recording owns the session. Apps no longer need `audio_session` (or their own `setActive`) before playing.

### Changed
- **Breaking**: `OggOpusRecorder.start()` throws `OggOpusRecorderException` instead of `PlatformException`, and `startError` is typed `OggOpusRecorderException?` (a native start failure is reported with code `START_FAILED`).

### Removed
- **Breaking**: macOS is no longer supported. The macOS platform, its xcframework slices, `example/macos` and the `AppKit` code paths are gone.

## 2.1.0

### Changed
- **macOS**: Minimum deployment target raised from 10.15 to 11.0 (podspec, `Package.swift`, and the default for `darwin/build-all.sh`).
- Removed the `system_clock` dependency (and its transitive `ffi` dependency). `OggOpusPlayer.currentPosition` is now extrapolated with a Dart `Stopwatch` reset on each native state callback, instead of comparing native and Dart uptime clocks over FFI.
- The native `onPlayerStateChanged` payload no longer includes `updateTime` (Android and iOS/macOS).

### Fixed
- `state` listeners now read the updated `currentPosition` and `duration`; previously the state was notified before the new position was stored.

## 2.0.2

### Fixed
- **Android**: Fixed native abort in `ope_encoder_drain` (`assert(enc->streams == NULL)`) by rebuilding the prebuilt `libopusenc.a` (all ABIs) from libopusenc 0.2.1 with `-DNDEBUG`, and by skipping `ope_encoder_drain` for recordings shorter than 0.25 s or after an encoder write error.

### Added
- `OggOpusRecorder.startError` exposes why `start()` failed (e.g. `PERMISSION_DENIED`), so a failed start can be told apart from an empty recording.
- Example app now requests the microphone permission on Android and surfaces start failures instead of ignoring them.

## 2.0.1

### Fixed
- **Android**: Fixed native crash in `silk_resampler_private_down_FIR` by replacing process-wide global encoder state in C with thread-safe, per-instance native handles (`OpusRecorderContext` with mutex synchronization).
- **Android**: Fixed use-after-free and race conditions occurring during rapid start/stop/cancel recording cycles.
- **Android**: Prevented thread leaks by terminating background `Looper` worker threads (`recordQueue` and `fileEncodingQueue`) upon recorder disposal.
- **Android**: Fixed potential unaligned memory writes in waveform packing and guarded against `Int16.min` integer overflow in `getWaveform2`.

## 2.0.0

### Added
- **macOS**: Added full macOS playback and recording support (`OggOpusPlayer` and `OggOpusRecorder`).
- **macOS**: Configured AudioUnit (`HALOutput`) to capture audio from the system default input device and encode to Opus at 48 kHz.
- **Darwin / SPM**: Migrated from `ios/` to a unified `darwin/` directory (`sharedDarwinSource: true`), enabling Swift Package Manager (SPM) and CocoaPods support for both iOS and macOS from a single package configuration.
- **Darwin**: Rebuilt universal multi-platform xcframeworks (`libogg`, `libopus`, `libopusenc`, `libopusfile`) including iOS (device + simulator) and macOS (`arm64` + `x86_64`) slices.
- **Example**: Added macOS platform runner with audio input entitlements to `example/`.

### Changed
- **BREAKING (Android)**: Migrated to Flutter's built-in Kotlin. The plugin no longer applies the Kotlin Gradle Plugin (`org.jetbrains.kotlin.android`), which removes the "plugins that apply Kotlin Gradle Plugin (KGP)" build warning. Consuming apps must set `android.builtInKotlin=true` in `android/gradle.properties`; otherwise the plugin's Kotlin sources are not compiled. Requires AGP 8.13+ (AGP 9+ recommended).

## 1.5.0

### Added
- **iOS**: Swift Package Manager support (`ios/ogg_record_player/Package.swift`); CocoaPods integration kept working.

### Changed
- **iOS**: Removed duplicate `ios/Frameworks` and stale `ios/Headers`; xcframeworks now live only in `ios/ogg_record_player/Frameworks` (build scripts output there).
- **iOS**: Rebuilt the vendored xcframeworks with libopus 1.5.2 (was 1.3.1) and a 15.0 minimum deployment target.
- **iOS (example)**: Deintegrated CocoaPods from `example/ios` (removed `Podfile`); the example app now builds via Swift Package Manager only, which is what Flutter recommends when every plugin supports SwiftPM. The `ogg_record_player.podspec` itself still ships and is validated with `pod lib lint` — CocoaPods consumers are unaffected.

### Fixed
- **iOS**: `getDuration` is implemented instead of always returning `null`; it reports the file duration in seconds via `op_pcm_total`, matching Android.
- **iOS**: `build-lib*.sh` no longer hardcode the iOS SDK version (resolved via `xcrun`) and build arm64 with `--host=aarch64-apple-darwin`, which fixes the ARMv7 GNU assembly build failure in libopus.
- **iOS**: Replaced the deprecated `AVAudioSession.CategoryOptions.allowBluetooth` with `allowBluetoothHFP` on Swift 6.2+ toolchains.

## 1.4.3

### Fixed
- **Android**: Fixed memory leaks in `PhoneStateListener`, `OggOpusPlayerPlugin` recorders map, and native C encoder on cancel path.
- **Android**: Fixed waveform sampling divisor calculation bug.

## 1.4.2

### Changed
- Package renamed from `one.mixin.oggOpusPlayer` to `uz.plugin.ogg_opus_player`.

## 1.4.1

### Fixed
- **iOS (example)**: Fixed `pod install` error by removing the non-existent `RunnerTests` target from the Podfile.

## 1.4.0


### Changed
- **iOS**: Migrated from CocoaPods to Swift Package Manager (SPM).
- **iOS**: Unified source structure — `Classes/` removed, sources consolidated under `ios/ogg_record_player/Sources/`.
- **iOS**: Replaced direct `import libopus/libopusfile/libopusenc` with `ogg_record_player_c` module (conditional import, compatible with both SPM and CocoaPods).
- **iOS**: Added `opusfile_wrapper.h` — minimal `libopusfile` C interface without `ogg/ogg.h` dependency.
- **iOS (example)**: Removed CocoaPods integration from example app.

## 1.3.0

### Fixed
- **Android**: Fixed native memory leaks in JNI waveform generation (`getWaveform2`) - `bytes` buffer was not freed.
- **Android**: Fixed JNI string leak in `startRecord` - `pathStr` was not released after use.
- **Android**: Fixed ExoPlayer resource leak - added `player.release()` in `destroy()` method.
- **Android**: Made player/recorder maps thread-safe using `Collections.synchronizedMap()`.
- **Android**: Made `generatePlayerId()` thread-safe with `@Synchronized` annotation.
- **Dart**: Fixed player/recorder instances not being removed from global maps on `dispose()`.
- **Dart**: Fixed create-dispose race condition - added `_disposed` flag to prevent zombie objects.
- **Dart/Android**: Prevented `OggOpusRecorder.stop()` from hanging after `startRecord` method-channel failures (for example, permission denial on Android).
- **Dart**: Fixed potential `StateError` from double-completing `_stopCompleter` - added `isCompleted` guard.
- **iOS**: `destroyRecorder` now cancels an active recording before removing it from the plugin dictionary, matching Android cleanup semantics more closely.
- **iOS**: Recorder cancellation now deactivates the shared audio session during cleanup.

### Improved
- Player and recorder lifecycle management is now more robust and prevents memory leaks.
- Better error handling for recorder start failures.

## 1.2.0

- Fixed an iOS recorder crash caused by waveform sample overflow on `Int16.min`.
- Improved waveform generation for empty and constant-amplitude recordings.
- Updated package SDK constraints and development tooling.

## 1.1.0

Ogg voice record package.
