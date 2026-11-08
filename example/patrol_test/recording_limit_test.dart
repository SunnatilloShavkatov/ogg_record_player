import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest('a recording finishes by itself at 3 minutes', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('limit.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);
    addTearDown(recorder.dispose);

    await recorder.start();
    await delay(const Duration(seconds: 190));
    await recorder.stop(); // the native side already finished; this only collects the result
    expect(await recorder.duration(), closeTo(180, 1.5));
    expect(isOggFile(File(path)), isTrue);

    final OggOpusPlayer player = OggOpusPlayer.file(File(path));
    addTearDown(player.dispose);
    expect(await player.getDuration(), closeTo(180, 1.5));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
