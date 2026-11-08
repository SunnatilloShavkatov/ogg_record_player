import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest('Android: start() without the microphone permission throws PERMISSION_DENIED', ($) async {
    await pumpHost($);
    final OggOpusRecorder recorder = OggOpusRecorder(await freshPath('denied.ogg'));
    addTearDown(recorder.dispose);
    await expectLater(
      recorder.start(),
      throwsA(isA<OggOpusRecorderException>().having((e) => e.code, 'code', OggOpusRecorderException.permissionDenied)),
    );
    expect(recorder.startError?.code, OggOpusRecorderException.permissionDenied);
    await recorder.stop(); // returns at once after a failed start
    expect(await recorder.duration(), 0.0);
  }, skip: !Platform.isAndroid);

  patrolTest('records a playable file with duration and waveform', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('voice.ogg');

    final Recording recording = await record(path, const Duration(seconds: 2));
    expect(recording.duration, closeTo(2, 0.4));
    expect(recording.waveform, isNotEmpty);
    expect(isOggFile(File(path)), isTrue);

    final OggOpusPlayer player = OggOpusPlayer.file(File(path));
    addTearDown(player.dispose);
    expect(await settled(player), PlayerState.paused);
    expect(await player.getDuration(), closeTo(recording.duration, 0.15));
    await player.play();
    await waitForState(player, PlayerState.playing);
    await waitForState(player, PlayerState.ended, timeout: const Duration(seconds: 6));
  });

  patrolTest('the same recorder records again and reports only the new recording', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('reuse.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);
    addTearDown(recorder.dispose);

    await recorder.start();
    await delay(const Duration(seconds: 1));
    await recorder.stop();
    expect(await recorder.duration(), closeTo(1, 0.4));

    await recorder.start();
    expect(await recorder.duration(), 0.0, reason: 'the previous result is cleared on start');
    await delay(const Duration(milliseconds: 2500));
    await recorder.stop();
    expect(await recorder.duration(), closeTo(2.5, 0.4));
    expect(await recorder.getWaveformData(), isNotEmpty);
    expect(isOggFile(File(path)), isTrue);

    final OggOpusPlayer player = OggOpusPlayer.file(File(path));
    addTearDown(player.dispose);
    expect(await player.getDuration(), closeTo(2.5, 0.4), reason: 'the file holds the second recording');
  });

  patrolTest('start() while stop() is still finishing waits for it', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('restart.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);
    addTearDown(recorder.dispose);

    await recorder.start();
    await delay(const Duration(seconds: 1));
    final Future<void> firstStop = recorder.stop();
    await recorder.start();
    await firstStop;
    await delay(const Duration(milliseconds: 1500));
    await recorder.stop();
    expect(await recorder.duration(), closeTo(1.5, 0.4));
    expect(isOggFile(File(path)), isTrue);
  });

  patrolTest('a recording shorter than 250 ms is canceled and leaves no file', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('short.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);
    addTearDown(recorder.dispose);

    await recorder.start();
    await delay(const Duration(milliseconds: 80));
    await recorder.stop();
    expect(await recorder.duration(), 0.0);
    expect(await recorder.getWaveformData(), isEmpty);
    expect(File(path).existsSync(), isFalse);

    // The recorder still works afterwards.
    await recorder.start();
    await delay(const Duration(seconds: 1));
    await recorder.stop();
    expect(await recorder.duration(), closeTo(1, 0.4));
  });

  patrolTest('dispose() during a recording cancels it and deletes the file', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('disposed.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);

    await recorder.start();
    await delay(const Duration(seconds: 1));
    await recorder.dispose();
    await waitUntil(() => !File(path).existsSync(), reason: 'file deletion');

    // A new recorder on the same path works.
    final Recording again = await record(path, const Duration(seconds: 1));
    expect(again.duration, closeTo(1, 0.4));
  });

  patrolTest('a recording pauses players and play() is ignored until it stops', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final OggOpusPlayer player = OggOpusPlayer.bytes(await assetBytes());
    addTearDown(player.dispose);
    await player.play();
    await waitForState(player, PlayerState.playing);

    final OggOpusRecorder recorder = OggOpusRecorder(await freshPath('pause.ogg'));
    addTearDown(recorder.dispose);
    await recorder.start();
    await waitForState(player, PlayerState.paused);

    await player.play();
    await delay(const Duration(seconds: 1));
    expect(player.state.value, PlayerState.paused, reason: 'play() is ignored while recording');

    await recorder.stop();
    expect(await recorder.duration(), closeTo(1, 0.4));
    await player.play();
    await waitForState(player, PlayerState.playing);
  });

  patrolTest('going to the background and back during a recording never hangs stop()', ($) async {
    await pumpHost($);
    await grantMicrophone($);
    final String path = await freshPath('background.ogg');
    final OggOpusRecorder recorder = OggOpusRecorder(path);
    addTearDown(recorder.dispose);

    await recorder.start();
    await delay(const Duration(seconds: 1));
    await $.platform.mobile.pressHome();
    await delay(const Duration(seconds: 2));
    await $.platform.mobile.openApp();
    await delay(const Duration(seconds: 1));
    // Either the OS kept the microphone (a file) or interrupted it (a cancel); stop() must answer either way.
    await recorder.stop();
    final double duration = await recorder.duration();
    if (duration > 0) {
      expect(isOggFile(File(path)), isTrue);
    } else {
      expect(File(path).existsSync(), isFalse);
    }
  });
}
