import 'dart:async';
import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:ogg_record_player/src/bindings/ogg_record_player_api.g.dart';
import 'package:ogg_record_player/src/native_results.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_events.dart';

/// [OggRecordPlayerPlatform] over JNI: Dart calls `OggRecordPlayerApi` directly, with no method channel. Callbacks
/// are asynchronous listeners, so Kotlin never blocks on Dart, and arrive as events on the two streams.
class AndroidOggRecordPlayer extends OggRecordPlayerPlatform {
  // Synchronous, so a state change reaches its player in the same task the native callback arrived in.
  final StreamController<PlayerStateEvent> _playerStateChanges = StreamController<PlayerStateEvent>.broadcast(
    sync: true,
  );
  final StreamController<RecorderEvent> _recorderEvents = StreamController<RecorderEvent>.broadcast(sync: true);

  bool _hasListeners = false;

  @override
  Stream<PlayerStateEvent> get playerStateChanges {
    _registerListeners();
    return _playerStateChanges.stream;
  }

  @override
  Stream<RecorderEvent> get recorderEvents {
    _registerListeners();
    return _recorderEvents.stream;
  }

  @override
  Future<int> createPlayerFromFile(String path) => _createPlayer(
    (OggRecordPlayerApi$CreateCallback callback) =>
        using((Arena arena) => OggRecordPlayerApi.createFromFile(path.toJString()..releasedBy(arena), callback)),
  );

  @override
  Future<int> createPlayerFromUrl(String url) => _createPlayer(
    (OggRecordPlayerApi$CreateCallback callback) =>
        using((Arena arena) => OggRecordPlayerApi.createFromUrl(url.toJString()..releasedBy(arena), callback)),
  );

  @override
  Future<int> createPlayerFromBytes(Uint8List bytes) => _createPlayer(
    (OggRecordPlayerApi$CreateCallback callback) => using(
      (Arena arena) => OggRecordPlayerApi.createFromBytes(
        (JByteArray(bytes.length)
            ..setRange(0, bytes.length, bytes.buffer.asInt8List(bytes.offsetInBytes, bytes.length)))
          ..releasedBy(arena),
        callback,
      ),
    ),
  );

  @override
  Future<void> warmUp() {
    final Completer<void> completer = Completer<void>();
    try {
      final OggRecordPlayerApi$DoneCallback callback = OggRecordPlayerApi$DoneCallback.implement(
        $OggRecordPlayerApi$DoneCallback(
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onDone$async: true,
        ),
      );
      OggRecordPlayerApi.warmUp(callback);
    } on Object {
      // Warming up is an optimisation; nothing to recover.
      return Future<void>.value();
    }
    return completer.future;
  }

  @override
  Future<void> play(int playerId) => _run(() => OggRecordPlayerApi.play(playerId));

  @override
  Future<void> pause(int playerId) => _run(() => OggRecordPlayerApi.pause(playerId));

  @override
  Future<void> disposePlayer(int playerId) => _run(() => OggRecordPlayerApi.stop(playerId));

  @override
  Future<double?> getDuration(int playerId) {
    final Completer<double?> completer = Completer<double?>();
    try {
      final OggRecordPlayerApi$DurationCallback callback = OggRecordPlayerApi$DurationCallback.implement(
        $OggRecordPlayerApi$DurationCallback(
          onDuration: (bool known, double seconds) {
            if (!completer.isCompleted) {
              completer.complete(durationFromNative(known: known, seconds: seconds));
            }
          },
          onDuration$async: true,
        ),
      );
      OggRecordPlayerApi.getDuration(playerId, callback);
    } on Object {
      return Future<double?>.value();
    }
    return completer.future;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _run(() => OggRecordPlayerApi.setPlaybackSpeed(playerId, speed));

  @override
  Future<int> createRecorder(String path) async {
    _registerListeners();
    final JString jPath = path.toJString();
    try {
      return recorderIdFromNative(OggRecordPlayerApi.createRecorder(jPath));
    } on JThrowable catch (e) {
      throw OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: e.toString());
    } finally {
      jPath.release();
    }
  }

  @override
  Future<void> startRecord(int recorderId) async {
    try {
      final JString? code = OggRecordPlayerApi.startRecord(recorderId);
      if (code != null) {
        final String errorCode = code.toDartString(releaseOriginal: true);
        throw OggOpusRecorderException(code: errorCode, message: errorCode);
      }
    } on JThrowable catch (e) {
      throw OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: e.toString());
    }
  }

  @override
  Future<void> stopRecord(int recorderId) => _run(() => OggRecordPlayerApi.stopRecord(recorderId));

  @override
  Future<void> destroyRecorder(int recorderId) => _run(() => OggRecordPlayerApi.destroyRecorder(recorderId));

  Future<int> _createPlayer(void Function(OggRecordPlayerApi$CreateCallback callback) start) {
    _registerListeners();
    final Completer<int> completer = Completer<int>();
    try {
      final OggRecordPlayerApi$CreateCallback callback = OggRecordPlayerApi$CreateCallback.implement(
        $OggRecordPlayerApi$CreateCallback(
          onCreated: (int playerId) {
            if (!completer.isCompleted) {
              completer.complete(playerId);
            }
          },
          onCreated$async: true,
          onFailed: (JString? code, JString? message, JString? details) {
            if (!completer.isCompleted) {
              completer.completeError(
                OggOpusPlayerException(
                  code: code?.toDartString(releaseOriginal: true) ?? OggOpusPlayerException.unknown,
                  message: message?.toDartString(releaseOriginal: true) ?? '',
                  details: details?.toDartString(releaseOriginal: true),
                ),
              );
            }
          },
          onFailed$async: true,
        ),
      );
      start(callback);
    } on JThrowable catch (e) {
      return Future<int>.error(OggOpusPlayerException(code: OggOpusPlayerException.unknown, message: e.toString()));
    }
    return completer.future;
  }

  /// For calls whose failure leaves nothing to recover: ignored, never thrown.
  Future<void> _run(void Function() call) async {
    try {
      call();
    } on Object {
      // Nothing to recover.
    }
  }

  void _registerListeners() {
    if (_hasListeners) {
      return;
    }
    _hasListeners = true;
    final OggRecordPlayerApi$PlayerListener playerListener = OggRecordPlayerApi$PlayerListener.implement(
      $OggRecordPlayerApi$PlayerListener(
        onStateChanged: (int playerId, int state, double position, double duration, double speed, JString? errorCode) {
          // A malformed payload drops that one callback instead of failing the native side.
          try {
            _playerStateChanges.add(
              PlayerStateEvent(
                playerId: playerId,
                state: playerStateFromRaw(state),
                position: position,
                duration: duration,
                speed: speed,
                errorCode: errorCode?.toDartString(releaseOriginal: true),
              ),
            );
          } on Object {
            // Dropped.
          }
        },
        onStateChanged$async: true,
      ),
    );
    final OggRecordPlayerApi$RecorderListener recorderListener = OggRecordPlayerApi$RecorderListener.implement(
      $OggRecordPlayerApi$RecorderListener(
        onCanceled: (int recorderId, int reason) =>
            _recorderEvents.add(RecorderCanceledEvent(recorderId: recorderId, reason: reason)),
        onCanceled$async: true,
        onStartFailed: (int recorderId, JString? error) => _recorderEvents.add(
          RecorderStartFailedEvent(recorderId: recorderId, error: error?.toDartString(releaseOriginal: true) ?? ''),
        ),
        onStartFailed$async: true,
        onFinished: (int recorderId, int durationMillis, JByteArray? waveform) {
          // Released even when copying the waveform fails, so the JNI reference never outlives the event.
          try {
            final Int8List raw = waveform == null ? Int8List(0) : waveform.getRange(0, waveform.length);
            _recorderEvents.add(
              RecorderFinishedEvent(
                recorderId: recorderId,
                duration: durationMillis,
                waveform: raw.buffer.asUint8List(raw.offsetInBytes, raw.length),
              ),
            );
          } finally {
            waveform?.release();
          }
        },
        onFinished$async: true,
      ),
    );
    OggRecordPlayerApi.setListeners(playerListener, recorderListener);
  }
}
