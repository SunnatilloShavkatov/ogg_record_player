import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Ids are never reused: the plugin keeps its player and recorder maps for the whole test file.
int _nextId = 1;

final class _FakePlatform extends OggRecordPlayerPlatform with MockPlatformInterfaceMixin {
  final StreamController<PlayerStateEvent> _playerEvents = StreamController<PlayerStateEvent>.broadcast(sync: true);
  final StreamController<RecorderEvent> _recorderEvents = StreamController<RecorderEvent>.broadcast(sync: true);

  Exception? createRecorderError;
  double? duration;

  /// Runs after `stopRecord`; a real recorder answers with a finished or canceled event.
  void Function(int recorderId)? onStopRecord;

  void reset() {
    createRecorderError = null;
    duration = null;
    onStopRecord = null;
  }

  void emit(PlayerStateEvent event) => _playerEvents.add(event);

  void emitRecorder(RecorderEvent event) => _recorderEvents.add(event);

  @override
  Stream<PlayerStateEvent> get playerStateChanges => _playerEvents.stream;

  @override
  Stream<RecorderEvent> get recorderEvents => _recorderEvents.stream;

  @override
  Future<int> createPlayerFromBytes(Uint8List bytes) async => _nextId++;

  @override
  Future<double?> getDuration(int playerId) async => duration;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> disposePlayer(int playerId) async {}

  @override
  Future<int> createRecorder(String path) async {
    final Exception? error = createRecorderError;
    if (error != null) {
      throw error;
    }
    return _nextId++;
  }

  @override
  Future<void> startRecord(int recorderId) async {}

  @override
  Future<void> stopRecord(int recorderId) async => onStopRecord?.call(recorderId);

  @override
  Future<void> destroyRecorder(int recorderId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One instance for the whole file: the plugin subscribes to the platform's streams once, on first use.
  final _FakePlatform platform = _FakePlatform();
  OggRecordPlayerPlatform.instance = platform;

  setUp(platform.reset);

  OggRecordPlayerPluginImpl createPlayer() {
    final OggRecordPlayerPluginImpl player = OggRecordPlayerPluginImpl(
      (OggRecordPlayerPlatform platform) => platform.createPlayerFromBytes(Uint8List(0)),
    );
    addTearDown(player.dispose);
    return player;
  }

  OggOpusRecorderPluginImpl createRecorder() {
    final OggOpusRecorderPluginImpl recorder = OggOpusRecorderPluginImpl('/tmp/a.ogg');
    addTearDown(recorder.dispose);
    return recorder;
  }

  group('getDuration', () {
    test('returns null when the native player does not know the duration', () async {
      platform.duration = null;

      expect(await createPlayer().getDuration(), isNull);
    });

    test('keeps a real zero-second duration apart from an unknown one', () async {
      platform.duration = 0;

      expect(await createPlayer().getDuration(), 0.0);
    });

    test('preserves fractional seconds', () async {
      platform.duration = 12.5;

      expect(await createPlayer().getDuration(), 12.5);
    });
  });

  group('player errors', () {
    test('a native playback failure sets the error state and its code', () async {
      final OggRecordPlayerPluginImpl player = createPlayer();
      await player.getDuration();
      expect(player.state.value, PlayerState.paused);

      platform.emit(
        PlayerStateEvent(
          playerId: _nextId - 1,
          state: PlayerState.error,
          position: 0,
          duration: 0,
          speed: 1,
          errorCode: OggOpusPlayerException.invalidFile,
        ),
      );

      expect(player.state.value, PlayerState.error);
      expect(player.error?.code, OggOpusPlayerException.invalidFile);
    });
  });

  group('recorder', () {
    test('start throws and startError is set when the native recorder cannot be created', () async {
      platform.createRecorderError = const OggOpusRecorderException(
        code: OggOpusRecorderException.unknown,
        message: 'no recorder',
      );
      final OggOpusRecorder recorder = createRecorder();

      await expectLater(
        recorder.start(),
        throwsA(isA<OggOpusRecorderException>().having((OggOpusRecorderException e) => e.message, 'message', 'no recorder')),
      );
      expect(recorder.startError?.message, 'no recorder');
      await expectLater(recorder.stop(), completes);
    });

    test('a start failure reported after start() is exposed as startError and ends stop()', () async {
      final OggOpusRecorderPluginImpl recorder = createRecorder();
      await recorder.start();
      final int recorderId = _nextId - 1;

      platform.emitRecorder(RecorderStartFailedEvent(recorderId: recorderId, error: 'microphone busy'));

      expect(recorder.startError?.code, OggOpusRecorderException.startFailed);
      expect(recorder.startError?.message, 'microphone busy');
      await expectLater(recorder.stop(), completes);
    });

    test('stop waits for the finished event and exposes the recording', () async {
      final OggOpusRecorderPluginImpl recorder = createRecorder();
      platform.onStopRecord = (int recorderId) => scheduleMicrotask(
        () => platform.emitRecorder(
          RecorderFinishedEvent(recorderId: recorderId, duration: 1500, waveform: Uint8List.fromList(<int>[1, 2])),
        ),
      );
      await recorder.start();

      await recorder.stop();

      expect(await recorder.duration(), 1.5);
      expect(await recorder.getWaveformData(), <int>[1, 2]);
    });

    test('a canceled recording ends stop() instead of leaving it waiting', () async {
      final OggOpusRecorderPluginImpl recorder = createRecorder();
      platform.onStopRecord = (int recorderId) =>
          scheduleMicrotask(() => platform.emitRecorder(RecorderCanceledEvent(recorderId: recorderId, reason: 0)));
      await recorder.start();

      await expectLater(recorder.stop(), completes);
    });

    test('stop throws stopTimeout when the native recorder never answers', () async {
      final Duration original = OggOpusRecorderPluginImpl.stopTimeout;
      OggOpusRecorderPluginImpl.stopTimeout = const Duration(milliseconds: 50);
      addTearDown(() => OggOpusRecorderPluginImpl.stopTimeout = original);
      final OggOpusRecorderPluginImpl recorder = createRecorder();
      await recorder.start();

      await expectLater(
        recorder.stop(),
        throwsA(
          isA<OggOpusRecorderException>().having(
            (OggOpusRecorderException e) => e.code,
            'code',
            OggOpusRecorderException.stopTimeout,
          ),
        ),
      );
    });
  });
}
