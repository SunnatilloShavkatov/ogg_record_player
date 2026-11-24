import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:objective_c/objective_c.dart' as objc;
import 'package:ogg_record_player/src/bindings/ogg_record_player_darwin.g.dart';
import 'package:ogg_record_player/src/microphone_permission.dart';
import 'package:ogg_record_player/src/native_results.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_events.dart';

/// [OggRecordPlayerPlatform] over the Objective-C runtime: Dart calls `OggRecordPlayerApi` (Swift, `@objc`)
/// directly, with no method channel. Results and events are listener blocks, which may fire on any thread and
/// are delivered to this isolate.
class DarwinOggRecordPlayer extends OggRecordPlayerPlatform {
  // Synchronous, so a state change reaches its player in the same task the native callback arrived in.
  final StreamController<PlayerStateEvent> _playerStateChanges = StreamController<PlayerStateEvent>.broadcast(
    sync: true,
  );
  final StreamController<RecorderEvent> _recorderEvents = StreamController<RecorderEvent>.broadcast(sync: true);

  bool _hasListeners = false;

  /// Routes calls that create players, recorders or listeners to this engine's native scope; calls by id need not.
  int get _engineId => engineIdForNative(PlatformDispatcher.instance.engineId);

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
    (CreateBlock callback) =>
        OggRecordPlayerApi.createFromFileForEngine(_engineId, path: path.toNSString(), callback: callback),
  );

  @override
  Future<int> createPlayerFromUrl(String url) => _createPlayer(
    (CreateBlock callback) =>
        OggRecordPlayerApi.createFromUrlForEngine(_engineId, url: url.toNSString(), callback: callback),
  );

  @override
  Future<int> createPlayerFromBytes(Uint8List bytes) => _createPlayer(
    (CreateBlock callback) =>
        OggRecordPlayerApi.createFromBytesForEngine(_engineId, bytes: bytes.toNSData(), callback: callback),
  );

  @override
  Future<void> warmUp() {
    final Completer<void> completer = Completer<void>();
    try {
      OggRecordPlayerApi.warmUp(
        ObjCBlock_ffiVoid.listener(() {
          if (!completer.isCompleted) {
            completer.complete();
          }
        }),
      );
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
      OggRecordPlayerApi.getDuration(
        playerId,
        callback: ObjCBlock_ffiVoid_bool_ffiDouble.listener((bool known, double seconds) {
          if (!completer.isCompleted) {
            completer.complete(durationFromNative(known: known, seconds: seconds));
          }
        }),
      );
    } on Object {
      return Future<double?>.value();
    }
    return completer.future;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _run(() => OggRecordPlayerApi.setPlaybackSpeed(playerId, speed: speed));

  @override
  Future<int> createRecorder(String path) async {
    _registerListeners();
    final int nativeId;
    try {
      nativeId = OggRecordPlayerApi.createRecorderForEngine(_engineId, path: path.toNSString());
    } on Object catch (e) {
      throw OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: '$e');
    }
    return recorderIdFromNative(nativeId);
  }

  @override
  Future<void> startRecord(int recorderId) async {
    final String? code;
    try {
      code = OggRecordPlayerApi.startRecord(recorderId)?.toDartString();
    } on Object catch (e) {
      throw OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: '$e');
    }
    if (code != null) {
      throw OggOpusRecorderException(code: code, message: code);
    }
  }

  @override
  Future<void> stopRecord(int recorderId) => _run(() => OggRecordPlayerApi.stopRecord(recorderId));

  /// Completes once the native recording released the audio session, so a `play` right after is not refused.
  @override
  Future<void> destroyRecorder(int recorderId) {
    final Completer<void> completer = Completer<void>();
    try {
      OggRecordPlayerApi.destroyRecorder(
        recorderId,
        callback: ObjCBlock_ffiVoid.listener(() {
          if (!completer.isCompleted) {
            completer.complete();
          }
        }),
      );
    } on Object {
      return Future<void>.value();
    }
    return completer.future;
  }

  @override
  Future<MicrophonePermission> microphonePermission() async =>
      MicrophonePermission.fromRaw(OggRecordPlayerApi.microphonePermission());

  @override
  Future<MicrophonePermission> requestMicrophonePermission() {
    final Completer<MicrophonePermission> completer = Completer<MicrophonePermission>();
    OggRecordPlayerApi.requestMicrophonePermission(
      ObjCBlock_ffiVoid_NSInteger.listener((int status) {
        if (!completer.isCompleted) {
          completer.complete(MicrophonePermission.fromRaw(status));
        }
      }),
    );
    return completer.future;
  }

  @override
  Future<bool> openAppSettings() async => OggRecordPlayerApi.openAppSettings();

  Future<int> _createPlayer(void Function(CreateBlock callback) start) {
    _registerListeners();
    final Completer<int> completer = Completer<int>();
    try {
      start(
        ObjCBlock_ffiVoid_NSInteger_NSString_NSString_NSString.listener((
          int playerId,
          objc.NSString? code,
          objc.NSString? message,
          objc.NSString? details,
        ) {
          if (completer.isCompleted) {
            return;
          }
          if (code == null) {
            completer.complete(playerId);
          } else {
            completer.completeError(
              OggOpusPlayerException(
                code: code.toDartString(),
                message: message?.toDartString() ?? '',
                details: details?.toDartString(),
              ),
            );
          }
        }),
      );
    } on Object catch (e) {
      return Future<int>.error(OggOpusPlayerException(code: OggOpusPlayerException.unknown, message: '$e'));
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
    OggRecordPlayerApi.setPlayerListenerForEngine(
      _engineId,
      listener: ObjCBlock_ffiVoid_NSInteger_NSInteger_ffiDouble_ffiDouble_ffiDouble_NSString.listener((
        int playerId,
        int state,
        double position,
        double duration,
        double speed,
        objc.NSString? errorCode,
      ) {
        // A malformed payload drops that one callback instead of failing the native side.
        try {
          _playerStateChanges.add(
            PlayerStateEvent(
              playerId: playerId,
              state: playerStateFromRaw(state),
              position: position,
              duration: duration,
              speed: speed,
              errorCode: errorCode?.toDartString(),
            ),
          );
        } on Object {
          // Dropped.
        }
      }),
    );
    OggRecordPlayerApi.setRecorderListenersForEngine(
      _engineId,
      canceled: ObjCBlock_ffiVoid_NSInteger_NSInteger.listener(
        (int recorderId, int reason) =>
            _recorderEvents.add(RecorderCanceledEvent(recorderId: recorderId, reason: reason)),
      ),
      startFailed: ObjCBlock_ffiVoid_NSInteger_NSString.listener(
        (int recorderId, objc.NSString error) =>
            _recorderEvents.add(RecorderStartFailedEvent(recorderId: recorderId, error: error.toDartString())),
      ),
      finished: ObjCBlock_ffiVoid_NSInteger_NSInteger_NSData.listener(
        (int recorderId, int durationMillis, objc.NSData waveform) => _recorderEvents.add(
          RecorderFinishedEvent(recorderId: recorderId, duration: durationMillis, waveform: waveform.toList()),
        ),
      ),
    );
  }
}

/// The block every `createFrom*` call answers through: a null code means success.
typedef CreateBlock = objc.ObjCBlock<ffi.Void Function(ffi.Long, objc.NSString?, objc.NSString?, objc.NSString?)>;
