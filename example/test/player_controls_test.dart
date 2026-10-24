import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:ogg_record_player_example/player_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final _TestPlatform platform = _TestPlatform();
  OggRecordPlayerPlatform.instance = platform;
  int nextId = 0;
  tearDownAll(platform.close);

  Future<void> sendState(
    int id, {
    required PlayerState state,
    required double position,
    required double duration,
  }) async {
    platform.states.add(PlayerStateEvent(playerId: id, state: state, position: position, duration: duration, speed: 1));
  }

  Future<OggOpusPlayer> mountPlayer(WidgetTester tester) async {
    final OggOpusPlayer player = OggRecordPlayerPluginImpl((_) async => ++nextId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControls(player: player, onPlay: player.play),
        ),
      ),
    );
    await tester.pump();
    return player;
  }

  Future<void> unmountPlayer(WidgetTester tester, OggOpusPlayer player) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final Future<void> disposed = player.dispose();
    await tester.pump();
    await disposed;
  }

  testWidgets('shows full duration before playback starts', (WidgetTester tester) async {
    final OggOpusPlayer player = await mountPlayer(tester);

    expect(find.text('p: 00:00'), findsOneWidget);
    expect(find.text('d: 02:05'), findsOneWidget);
    await unmountPlayer(tester, player);
  });

  testWidgets('refreshes position and total duration on pause and end', (WidgetTester tester) async {
    final OggOpusPlayer player = await mountPlayer(tester);
    await sendState(nextId, state: PlayerState.paused, position: 61, duration: 125.8);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('p: 01:01'), findsOneWidget);
    expect(find.text('d: 02:05'), findsOneWidget);

    await sendState(nextId, state: PlayerState.ended, position: 125.8, duration: 125.8);
    await tester.pump();
    expect(find.text('p: 02:05'), findsOneWidget);
    expect(find.text('d: 02:05'), findsOneWidget);
    expect(find.byTooltip('Replay'), findsOneWidget);
    await unmountPlayer(tester, player);
  });

  testWidgets('handles metadata arriving while paused and clamps extrapolated position', (WidgetTester tester) async {
    final OggOpusPlayer player = await mountPlayer(tester);
    await sendState(nextId, state: PlayerState.paused, position: 0, duration: 180);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('d: 03:00'), findsOneWidget);

    await sendState(nextId, state: PlayerState.playing, position: 185, duration: 180);
    await tester.pump();
    expect(find.text('p: 03:00'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 1);
    await unmountPlayer(tester, player);
  });

  testWidgets('controls fit a narrow phone screen', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final OggOpusPlayer player = await mountPlayer(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('d: 02:05'), findsOneWidget);
    await unmountPlayer(tester, player);
  });
}

class _TestPlatform extends OggRecordPlayerPlatform {
  final StreamController<PlayerStateEvent> states = StreamController<PlayerStateEvent>.broadcast(sync: true);

  Future<void> close() => states.close();

  @override
  Stream<PlayerStateEvent> get playerStateChanges => states.stream;

  @override
  Stream<RecorderEvent> get recorderEvents => const Stream<RecorderEvent>.empty();

  @override
  Future<int?> getDuration(int playerId) async => 125;

  @override
  Future<void> disposePlayer(int playerId) async {}
}
