import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest('bytes: duration before play, play, pause, resume, speed', ($) async {
    await pumpHost($);
    final OggOpusPlayer player = OggOpusPlayer.bytes(await assetBytes());
    addTearDown(player.dispose);

    expect(await settled(player), PlayerState.paused);
    expect(await player.getDuration(), closeTo(assetDuration, 0.05));

    await player.play();
    await waitForState(player, PlayerState.playing);
    await delay(const Duration(milliseconds: 1500));
    final double atNormalSpeed = player.currentPosition;
    expect(atNormalSpeed, inInclusiveRange(0.8, 2.5));

    await player.setPlaybackRate(2);
    await delay(const Duration(seconds: 1));
    // One second at 2x adds about two seconds.
    expect(player.currentPosition - atNormalSpeed, inInclusiveRange(1.4, 3.2));

    await player.pause();
    await waitForState(player, PlayerState.paused);
    final double pausedAt = player.currentPosition;
    await delay(const Duration(milliseconds: 700));
    expect(player.currentPosition, closeTo(pausedAt, 0.05));

    await player.play();
    await waitForState(player, PlayerState.playing);
    await delay(const Duration(milliseconds: 500));
    expect(player.currentPosition, greaterThan(pausedAt), reason: 'resumes where it paused');
  });

  patrolTest('file: plays to the end, then replays from the start', ($) async {
    await pumpHost($);
    final OggOpusPlayer player = OggOpusPlayer.file(await assetFile());
    addTearDown(player.dispose);

    expect(await settled(player), PlayerState.paused);
    expect(await player.getDuration(), closeTo(assetDuration, 0.05));
    await player.setPlaybackRate(2);
    await player.play();
    await waitForState(player, PlayerState.playing);
    await waitForState(player, PlayerState.ended, timeout: const Duration(seconds: 25));
    expect(player.currentPosition, closeTo(assetDuration, 0.6));

    await player.play();
    await waitForState(player, PlayerState.playing);
    await delay(const Duration(milliseconds: 500));
    expect(player.currentPosition, lessThan(3), reason: 'replay after the end starts over');
  });

  patrolTest('only one player plays at a time', ($) async {
    await pumpHost($);
    final Uint8List bytes = await assetBytes();
    final OggOpusPlayer first = OggOpusPlayer.bytes(bytes);
    final OggOpusPlayer second = OggOpusPlayer.bytes(bytes);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await first.play();
    await waitForState(first, PlayerState.playing);
    await second.play();
    await waitForState(second, PlayerState.playing);
    await waitForState(first, PlayerState.paused);
  });

  patrolTest('invalid sources fail with the shared error codes and never crash', ($) async {
    await pumpHost($);
    final Uint8List valid = await assetBytes();

    Future<String?> errorOf(OggOpusPlayer player) async {
      final PlayerState state = await settled(player);
      await player.play(); // must be a no-op on a failed player
      await player.dispose();
      return state == PlayerState.error ? player.error?.code : 'no error, state $state';
    }

    expect(await errorOf(OggOpusPlayer.bytes(Uint8List(0))), OggOpusPlayerException.invalidArgument);
    expect(
      await errorOf(OggOpusPlayer.bytes(Uint8List.fromList('not an ogg file'.codeUnits))),
      OggOpusPlayerException.invalidFile,
    );
    // The Ogg signature followed by garbage.
    final Uint8List garbage = Uint8List(4096)..setRange(0, 4, 'OggS'.codeUnits);
    final OggOpusPlayer broken = OggOpusPlayer.bytes(garbage);
    final PlayerState brokenState = await settled(broken);
    if (brokenState != PlayerState.error) {
      await broken.play();
      await waitForState(broken, PlayerState.error);
    }
    await broken.dispose();

    // A truncated stream plays what it has and then ends or fails; it must not hang or crash.
    final OggOpusPlayer truncated = OggOpusPlayer.bytes(Uint8List.sublistView(valid, 0, 10000));
    if (await settled(truncated) == PlayerState.paused) {
      await truncated.setPlaybackRate(2);
      await truncated.play();
      await waitUntil(
        () => truncated.state.value == PlayerState.ended || truncated.state.value == PlayerState.error,
        timeout: const Duration(seconds: 15),
        reason: 'truncated stream to finish',
      );
    }
    await truncated.dispose();
  });

  patrolTest('url: downloads, plays and maps every failure', ($) async {
    await pumpHost($);
    final AudioServer server = await AudioServer.start(await assetBytes());
    addTearDown(server.close);

    for (final String path in <String>['audio.ogg', 'chunked.ogg']) {
      final OggOpusPlayer player = OggOpusPlayer.url(server.url(path));
      expect(await settled(player), PlayerState.paused, reason: path);
      expect(await player.getDuration(), closeTo(assetDuration, 0.05), reason: path);
      await player.play();
      await waitForState(player, PlayerState.playing);
      await player.dispose();
    }

    Future<String?> errorOf(String url, {Duration timeout = const Duration(seconds: 10)}) async {
      final OggOpusPlayer player = OggOpusPlayer.url(url);
      final PlayerState state = await settled(player, timeout: timeout);
      await player.dispose();
      return state == PlayerState.error ? player.error?.code : 'no error, state $state';
    }

    expect(await errorOf(server.url('missing.ogg')), OggOpusPlayerException.httpError);
    expect(await errorOf(server.url('text')), OggOpusPlayerException.invalidFile);
    expect(await errorOf(server.url('huge-declared.ogg')), OggOpusPlayerException.ioError);
    expect(
      await errorOf(server.url('huge-chunked.ogg'), timeout: const Duration(seconds: 30)),
      OggOpusPlayerException.ioError,
    );
    // Nothing listens on port 9 of the loopback interface.
    expect(await errorOf('http://127.0.0.1:9/audio.ogg'), OggOpusPlayerException.networkError);
  });

  patrolTest('url: a server that stops sending fails with NETWORK_ERROR after the 30 s read timeout', ($) async {
    await pumpHost($);
    final AudioServer server = await AudioServer.start(await assetBytes());
    addTearDown(server.close);

    final Stopwatch watch = Stopwatch()..start();
    final OggOpusPlayer player = OggOpusPlayer.url(server.url('stall.ogg'));
    addTearDown(player.dispose);
    expect(await settled(player, timeout: const Duration(seconds: 50)), PlayerState.error);
    expect(player.error?.code, OggOpusPlayerException.networkError);
    expect(watch.elapsed, greaterThan(const Duration(seconds: 25)));
  }, timeout: const Timeout(Duration(minutes: 2)));

  patrolTest('many players: create, play, dispose in any order without leaks or crashes', ($) async {
    await pumpHost($);
    final Uint8List bytes = await assetBytes();
    final File file = await assetFile();

    // Dispose before creation finished.
    for (int i = 0; i < 20; i++) {
      await OggOpusPlayer.bytes(bytes).dispose();
    }

    final List<OggOpusPlayer> players = <OggOpusPlayer>[
      for (int i = 0; i < 30; i++)
        if (i.isEven) OggOpusPlayer.bytes(bytes) else OggOpusPlayer.file(file),
    ];
    for (final OggOpusPlayer player in players) {
      expect(await settled(player), PlayerState.paused);
    }
    // Every duration is known without starting a decoder per player.
    for (final OggOpusPlayer player in players) {
      expect(await player.getDuration(), closeTo(assetDuration, 0.05));
    }
    for (final OggOpusPlayer player in players.take(5)) {
      await player.play();
      await waitForState(player, PlayerState.playing);
    }
    for (final OggOpusPlayer player in players) {
      await player.dispose();
    }
    // Calls after dispose are ignored.
    await players.first.play();
    await players.first.pause();
    expect(await players.first.getDuration(), anyOf(isNull, isA<double>()));
  });
}
