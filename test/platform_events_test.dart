import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/player.dart' show isRemoteAudioPath;

void main() {
  test('native state codes map to PlayerState', () {
    expect(playerStateFromRaw(0), PlayerState.idle);
    expect(playerStateFromRaw(1), PlayerState.playing);
    expect(playerStateFromRaw(2), PlayerState.paused);
    expect(playerStateFromRaw(3), PlayerState.ended);
    expect(playerStateFromRaw(4), PlayerState.error);
  });

  test('isRemoteAudioPath accepts only http and https', () {
    expect(isRemoteAudioPath('https://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('HTTP://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('/var/mobile/a.ogg'), isFalse);
    expect(isRemoteAudioPath('file:///var/mobile/a.ogg'), isFalse);
  });
}
