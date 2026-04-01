## Unreleased

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
