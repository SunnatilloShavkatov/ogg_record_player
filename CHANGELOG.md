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
