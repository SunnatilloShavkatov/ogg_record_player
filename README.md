# ogg_record_player

A Flutter plugin for **playing** and **recording** Ogg Opus audio on Android, iOS and macOS.

- `OggOpusPlayer` — play and pause `.ogg` Opus files, with playback-rate control.
- `OggOpusRecorder` — record the microphone straight into an `.ogg` Opus file, with duration and
  waveform data for voice-message UIs.

| Platform | Supported | Minimum version |
|----------|-----------|-----------------|
| Android  | ✅        | minSdk 26       |
| iOS      | ✅        | 15.0            |
| macOS    | ✅        | 11.0            |

Other platforms throw `UnsupportedError`.

## Installation

```yaml
dependencies:
  ogg_record_player:
    git:
      url: https://github.com/SunnatilloShavkatov/ogg_record_player.git
      ref: 2.2.0
```

## Platform setup

### Android

`RECORD_AUDIO` is declared by the plugin, but it is a runtime permission: **your app must request it
before calling `OggOpusRecorder.start()`** (for example with `permission_handler`).
Without it `start()` throws a `PlatformException` with code `PERMISSION_DENIED`.

### iOS / macOS

Add `NSMicrophoneUsageDescription` to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses your microphone to record voice messages.</string>
```

On macOS also enable the microphone in `DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.device.microphone</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

On iOS, configure the audio session (for example with `audio_session`) with the `playAndRecord`
category before recording. See [`example/lib/main.dart`](example/lib/main.dart).

## Usage

### Playback

```dart
import 'package:ogg_record_player/ogg_record_player.dart';

final player = OggOpusPlayer('/path/to/voice.ogg');

player.state.addListener(() {
  // PlayerState: error, idle, playing, paused, ended
  print(player.state.value);
});

await player.play();
await player.setPlaybackRate(1.5); // 0.5 – 2.0
await player.pause();

print(player.currentPosition); // seconds
print(await player.getDuration()); // seconds

await player.dispose();
```

The file must exist when the player is created (asserted in debug builds).

Playback manages the platform's audio session itself, so no audio session package is needed to play:

- **Android:** the player takes audio focus when playback starts, which pauses other apps' audio, and gives it up when
  it pauses or ends. If another app (or another player) takes the focus for good, the player pauses and `state`
  becomes `paused`. During a short loss, such as a call, `state` is `paused` and playback resumes by itself.
- **iOS:** the player activates the audio session (`playback` category, `spokenAudio` mode) when playback starts and
  deactivates it when it pauses or ends, so other apps can resume. A phone call, a recording or another player
  starting pauses it. `play()` does nothing while a recording owns the session.
- **macOS:** there is no audio session, so nothing changes.

### Recording

```dart
final recorder = OggOpusRecorder('/path/to/new_voice.ogg');

try {
  await recorder.start();
} on Exception catch (e) {
  // e.g. PlatformException(PERMISSION_DENIED) when the microphone permission is missing.
  await recorder.dispose();
  return;
}

// ... later
await recorder.stop(); // completes once the file is finalized

final seconds = await recorder.duration();
final waveform = await recorder.getWaveformData();

await recorder.dispose();
```

Notes:

- `stop()` waits for the native side to finish writing; read `duration()` and `getWaveformData()`
  only after it completes.
- If `start()` failed, `stop()` returns immediately and `duration()` is `0.0` with an empty waveform.
  `recorder.startError` holds the reason, so a failed start can be told apart from an empty recording.
- `dispose()` while a recording is in progress cancels it and deletes the file on Android.
- Waveform format differs per platform: Android returns 5-bit packed data, iOS/macOS return 100
  intensity bytes.

## How it works

|             | Playback                       | Recording                                                          |
|-------------|--------------------------------|--------------------------------------------------------------------|
| Android     | Media3 ExoPlayer               | `AudioRecord` → JNI → libopusenc (16 kHz mono, 16 kbps, max 3 min) |
| iOS / macOS | `AudioQueue` + Ogg Opus reader | `AudioUnit` → libopusenc                                           |

Android links prebuilt static `libogg`, `libopus` and `libopusenc` from
`android/src/main/cpp/opus/lib/<abi>/`. `libopusenc` is built from 0.2.1 with `-DNDEBUG`, because a
failing internal `assert` in `ope_encoder_drain` would otherwise abort the whole app process.
Native libraries are linked with 16 KB page alignment.

Apple platforms ship prebuilt xcframeworks and support both CocoaPods and Swift Package Manager.

## Example

```shell
cd example
flutter run
```

## License

See [LICENSE](LICENSE).
