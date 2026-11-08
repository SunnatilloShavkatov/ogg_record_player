# ogg_record_player example

A small app that plays the bundled `audios/test.ogg` and records a voice message, then plays it back.

- [`lib/main.dart`](lib/main.dart): app setup and the optional `OggOpusPlayer.warmUp()`.
- [`lib/player_examples.dart`](lib/player_examples.dart), [`lib/player_controls.dart`](lib/player_controls.dart):
  play, pause, playback speed, position and errors.
- [`lib/recorder_example.dart`](lib/recorder_example.dart): microphone permission, the iOS audio session,
  recording, duration and waveform.

## Playback

```dart
final OggOpusPlayer player = OggOpusPlayer.file(File('/path/to/voice.ogg'));
// or OggOpusPlayer.url('https://example.com/voice.ogg'), OggOpusPlayer.bytes(bytes)

player.state.addListener(() {
  if (player.state.value == PlayerState.error) {
    print(player.error?.code); // e.g. NETWORK_ERROR, INVALID_FILE
  }
});

await player.play();
await player.setPlaybackRate(1.5);
print(await player.getDuration()); // seconds, or null when unknown
await player.pause();
await player.dispose();
```

## Recording

Request the microphone permission first (Android: `RECORD_AUDIO` at runtime; iOS:
`NSMicrophoneUsageDescription`), and on iOS configure the audio session with the `playAndRecord` category.

```dart
final OggOpusRecorder recorder = OggOpusRecorder('/path/to/new_voice.ogg');
try {
  await recorder.start();
} on OggOpusRecorderException catch (e) {
  print(e.code); // e.g. PERMISSION_DENIED
}

// ... later
await recorder.stop(); // completes once the file is written (or the recording was canceled)
final double seconds = await recorder.duration(); // 0.0 for a canceled recording
final List<int> waveform = await recorder.getWaveformData();
await recorder.dispose();
```

## Run

```shell
flutter run
```

On-device end-to-end tests live in `patrol_test/` and run with [Patrol](https://patrol.leancode.co):
`patrol test -d <device id>`.
