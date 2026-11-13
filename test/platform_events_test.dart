import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/native_results.dart';
import 'package:ogg_record_player/src/player.dart' show isRemoteAudioPath;

void main() {
  test('native state codes map to PlayerState', () {
    expect(playerStateFromRaw(0), PlayerState.idle);
    expect(playerStateFromRaw(1), PlayerState.playing);
    expect(playerStateFromRaw(2), PlayerState.paused);
    expect(playerStateFromRaw(3), PlayerState.ended);
    expect(playerStateFromRaw(4), PlayerState.error);
  });

  test('an unknown native duration is null, never 0', () {
    expect(durationFromNative(known: false, seconds: 0), isNull);
    expect(durationFromNative(known: true, seconds: 0), 0.0);
    expect(durationFromNative(known: true, seconds: 2.5), 2.5);
  });

  test('a negative recorder id is rejected as unknown, any other id passes through', () {
    expect(recorderIdFromNative(3), 3);
    expect(
      () => recorderIdFromNative(-1),
      throwsA(isA<OggOpusRecorderException>().having((e) => e.code, 'code', OggOpusRecorderException.unknown)),
    );
  });

  test('isRemoteAudioPath accepts only http and https', () {
    expect(isRemoteAudioPath('https://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('HTTP://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('/var/mobile/a.ogg'), isFalse);
    expect(isRemoteAudioPath('file:///var/mobile/a.ogg'), isFalse);
  });
}
