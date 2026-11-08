import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

/// Once `stop()` or `dispose()` completes, the recorder has let go of the audio session, so a player started
/// right after it plays instead of being refused as if the recording were still running.
void main() {
  Future<OggOpusPlayer> pausedPlayer() async {
    final OggOpusPlayer player = OggOpusPlayer.bytes(await assetBytes());
    addTearDown(player.dispose);
    expect(await settled(player), PlayerState.paused);
    return player;
  }

  patrolTest('a player plays right after a recording is disposed', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final OggOpusPlayer player = await pausedPlayer();

    final OggOpusRecorder recorder = OggOpusRecorder(await freshPath('dispose.ogg'));
    await recorder.start();
    await delay(const Duration(seconds: 1));
    await recorder.dispose();
    await player.play();
    await waitForState(player, PlayerState.playing);
  });

  patrolTest('a player plays right after a recording is stopped', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final OggOpusPlayer player = await pausedPlayer();

    final OggOpusRecorder recorder = OggOpusRecorder(await freshPath('stop.ogg'));
    addTearDown(recorder.dispose);
    await recorder.start();
    await delay(const Duration(seconds: 1));
    await recorder.stop();
    await player.play();
    await waitForState(player, PlayerState.playing);
  });
}
