# ogg_record_player

A Flutter plugin for **playing** and **recording** Ogg Opus audio on Android and iOS.

- `OggOpusPlayer` — play and pause `.ogg` Opus files, with playback-rate control.
- `OggOpusRecorder` — record the microphone straight into an `.ogg` Opus file, with duration and
  waveform data for voice-message UIs.

| Platform | Supported | Minimum version |
|----------|-----------|-----------------|
| Android  | ✅        | minSdk 26       |
| iOS      | ✅        | 15.0            |

Other platforms throw `UnsupportedError`.

## Installation

```yaml
dependencies:
  ogg_record_player:
    git:
      url: https://github.com/SunnatilloShavkatov/ogg_record_player.git
      ref: 2.6.0
```

## Platform setup

### Android

`RECORD_AUDIO` is declared by the plugin, but it is a runtime permission: **your app must request it
before calling `OggOpusRecorder.start()`** (for example with `permission_handler`).
Without it `start()` throws an `OggOpusRecorderException` with code `PERMISSION_DENIED`.

### iOS

Add `NSMicrophoneUsageDescription` to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses your microphone to record voice messages.</string>
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
print(await player.getDuration()); // double? seconds, including fractional seconds

await player.dispose();
```

The file must exist when the player is created (asserted in debug builds).

### Audio sources

Each source has its own constructor:

```dart
final fromFile = OggOpusPlayer.file(File('/path/to/voice.ogg'));
final fromUrl = OggOpusPlayer.url('https://example.com/voice.ogg');
final fromBytes = OggOpusPlayer.bytes(response.bodyBytes); // Uint8List of a whole .ogg stream
await fromUrl.play(); // waits until the audio is ready
```

`OggOpusPlayer(path)` still works and picks `url` or `file` from the scheme.

### Warm-up

The first player in a process pays a one-time native setup (about 100 ms on iOS). Call `warmUp()` ahead of
time, e.g. when a screen with audio opens, so the first `play()` starts without that delay:

```dart
unawaited(OggOpusPlayer.warmUp());
```

It is optional and cheap to repeat. It never activates the audio session or requests audio focus, so other
apps' audio keeps playing.

`OggOpusPlayer.bytes` plays straight from memory: nothing is written to disk or cached. Use it when the
backend returns the audio as binary.

For `OggOpusPlayer.url`, Android and iOS download the audio into memory for each new player and play it
without writing a file. Downloads are never cached or shared between players, and HTTP caching is disabled.
Pass the current URL when creating a player, including a fresh signed URL when the previous one expires.
Replaying an existing player uses its already loaded audio. The full encoded audio stays in memory until
the player is disposed.

The plugin declares the Android `INTERNET` permission. Plain `http://` needs cleartext traffic allowed by
your app (Android network security config, iOS App Transport Security).

### Errors

When a player cannot be created, `state` becomes `PlayerState.error` and `error` holds an
`OggOpusPlayerException` whose `code` is the same on every platform:

| Code              | Meaning                                                      |
|-------------------|--------------------------------------------------------------|
| `INVALID_ARGUMENT`| Empty path or bytes, or a URL that is not http/https         |
| `FILE_NOT_FOUND`  | The local file does not exist                                |
| `NETWORK_ERROR`   | No connection, timeout, TLS or DNS failure                   |
| `HTTP_ERROR`      | The server answered with a non-2xx status                    |
| `INVALID_FILE`    | File, download or bytes are not an Ogg Opus stream           |
| `IO_ERROR`        | Audio data could not be read because of an I/O error         |
| `UNKNOWN`         | Anything else                                                |

```dart
player.state.addListener(() {
  if (player.state.value == PlayerState.error) {
    final OggOpusPlayerException? error = player.error;
    if (error?.code == OggOpusPlayerException.networkError) {
      // show "no connection"
    }
  }
});
```

`OggOpusRecorder.start()` throws an `OggOpusRecorderException` (for example with code
`PERMISSION_DENIED`), and `startError` holds the same exception type.

Playback manages the platform's audio session itself, so no audio session package is needed to play:

- **Android:** the player takes audio focus when playback starts, which pauses other apps' audio, and gives it up when
  it pauses or ends. If another app (or another player) takes the focus for good, the player pauses and `state`
  becomes `paused`. During a short loss, such as a call, `state` is `paused` and playback resumes by itself.
- **iOS:** the player activates the audio session (`playback` category, `spokenAudio` mode) when playback starts and
  deactivates it when it pauses or ends, so other apps can resume. A phone call pauses playback; it resumes when
  the interruption ends and iOS supplies `shouldResume`. Manually pausing or disposing during the interruption
  cancels that resumption. A recording or another player taking the session pauses the previous player without
  automatic resumption. `play()` does nothing while a recording owns the session or a system interruption is active.

Both platforms select the audio output natively, including Bluetooth. The plugin does not add automatic pause
on headphone/Bluetooth disconnection. Only one of this plugin's players plays at a time, and starting a recording
pauses its players. All focus/interruption handling is native; no Dart interruption listener is required.

### Native library size

Android instantiates only audio renderers and Ogg extractors so R8 can remove unrelated Media3 code. Enable
shrinking in the consuming app's release configuration to benefit; other plugins may still require those parts.
The native linker also discards unused codec sections and hides static codec exports while retaining JNI entry points.

The iOS xcframeworks contain both device and simulator slices; their repository size is larger than the code
linked into a device app. Keep dead code stripping enabled for release builds. The vendored codec archives
contain optimized machine code without debug information (no LTO bitcode), so they link with any supported Xcode.

Measure changes using matching release builds, architectures and app dependencies. Device checks are listed in
[`doc/native-audio-verification.md`](doc/native-audio-verification.md).

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
- Waveform format differs per platform: Android returns 5-bit packed data, iOS returns 100
  intensity bytes.

## How it works

|             | Playback                       | Recording                                                          |
|-------------|--------------------------------|--------------------------------------------------------------------|
| Android     | Media3 ExoPlayer               | `AudioRecord` → JNI → libopusenc (16 kHz mono, 16 kbps, max 3 min) |
| iOS         | `AudioQueue` + Ogg Opus reader | `AudioUnit` → libopusenc                                           |

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
