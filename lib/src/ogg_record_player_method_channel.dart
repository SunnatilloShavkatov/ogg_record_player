import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:ogg_record_player/src/log_message.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_events.dart';
import 'package:ogg_record_player/src/player_state.dart';

/// An implementation of [OggRecordPlayerPlatform] over the `ogg_record_player` method channel.
class MethodChannelOggRecordPlayer extends OggRecordPlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('ogg_record_player');

  // Synchronous, so a state change reaches its player in the same task the native callback arrived in.
  final StreamController<PlayerStateEvent> _playerStateChanges = StreamController<PlayerStateEvent>.broadcast(
    sync: true,
  );
  final StreamController<RecorderEvent> _recorderEvents = StreamController<RecorderEvent>.broadcast(sync: true);

  bool _isHandlerSet = false;

  @override
  Stream<PlayerStateEvent> get playerStateChanges {
    _setHandlerIfNeeded();
    return _playerStateChanges.stream;
  }

  @override
  Stream<RecorderEvent> get recorderEvents {
    _setHandlerIfNeeded();
    return _recorderEvents.stream;
  }

  @override
  Future<int> createPlayerFromFile(String path) => _createPlayer('createFromFile', path);

  @override
  Future<int> createPlayerFromUrl(String url) => _createPlayer('createFromUrl', url);

  @override
  Future<int> createPlayerFromBytes(Uint8List bytes) => _createPlayer('createFromBytes', bytes);

  @override
  Future<void> play(int playerId) => _invoke('play', playerId);

  @override
  Future<void> pause(int playerId) => _invoke('pause', playerId);

  @override
  Future<void> disposePlayer(int playerId) => _invoke('stop', playerId);

  @override
  Future<int?> getDuration(int playerId) async {
    try {
      return await methodChannel.invokeMethod<int>('getDuration', playerId);
    } catch (e, s) {
      logMessage('getDuration failed:', error: e, stackTrace: s);
      return null;
    }
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _invoke('setPlaybackSpeed', <String, num>{'playerId': playerId, 'speed': speed});

  @override
  Future<int> createRecorder(String path) async {
    final int? recorderId = await _invokeRecorder<int>('createRecorder', path);
    if (recorderId == null) {
      throw const OggOpusRecorderException(
        code: OggOpusRecorderException.unknown,
        message: 'createRecorder returned no id',
      );
    }
    return recorderId;
  }

  @override
  Future<void> startRecord(int recorderId) => _invokeRecorder<void>('startRecord', recorderId);

  @override
  Future<void> stopRecord(int recorderId) => _invokeRecorder<void>('stopRecord', recorderId);

  @override
  Future<void> destroyRecorder(int recorderId) => _invoke('destroyRecorder', recorderId);

  Future<int> _createPlayer(String method, Object source) async {
    try {
      final int? playerId = await methodChannel.invokeMethod<int>(method, source);
      if (playerId == null) {
        throw OggOpusPlayerException(code: OggOpusPlayerException.unknown, message: '$method returned no id');
      }
      return playerId;
    } on PlatformException catch (e) {
      throw OggOpusPlayerException(code: e.code, message: e.message ?? '', details: e.details?.toString());
    } on MissingPluginException catch (e) {
      throw OggOpusPlayerException(code: OggOpusPlayerException.unknown, message: e.message ?? 'missing plugin');
    }
  }

  /// For calls whose failure leaves nothing to recover: logged, never thrown.
  Future<void> _invoke(String method, Object arguments) async {
    try {
      await methodChannel.invokeMethod<void>(method, arguments);
    } catch (e, s) {
      logMessage('$method failed:', error: e, stackTrace: s);
    }
  }

  Future<T?> _invokeRecorder<T>(String method, Object arguments) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw OggOpusRecorderException(code: e.code, message: e.message ?? '', details: e.details?.toString());
    } on MissingPluginException catch (e) {
      throw OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: e.message ?? 'missing plugin');
    }
  }

  void _setHandlerIfNeeded() {
    if (_isHandlerSet) {
      return;
    }
    _isHandlerSet = true;
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    // A malformed payload drops that one callback instead of failing the native invokeMethod.
    try {
      final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      switch (call.method) {
        case 'onPlayerStateChanged':
          _playerStateChanges.add(
            PlayerStateEvent(
              playerId: args['playerId'] as int,
              state: _playerStateFromRaw(args['state'] as int),
              position: (args['position'] as num).toInt(),
              duration: (args['duration'] as num? ?? 1).toInt(),
              speed: (args['speed'] as num? ?? 1).toDouble(),
            ),
          );
        case 'onRecorderCanceled':
          _recorderEvents.add(
            RecorderCanceledEvent(recorderId: args['recorderId'] as int, reason: args['reason'] as int),
          );
        case 'onRecorderStartFailed':
          _recorderEvents.add(
            RecorderStartFailedEvent(recorderId: args['recorderId'] as int, error: args['error'] as String),
          );
        case 'onRecorderFinished':
          final Object? waveform = args['waveform'];
          _recorderEvents.add(
            RecorderFinishedEvent(
              recorderId: args['recorderId'] as int,
              duration: (args['duration'] as num).toInt(),
              waveform: waveform is Uint8List ? waveform : Uint8List.fromList((waveform! as List<dynamic>).cast<int>()),
            ),
          );
        default:
          break;
      }
    } catch (e, s) {
      logMessage('${call.method} payload could not be read:', error: e, stackTrace: s);
    }
  }
}

PlayerState _playerStateFromRaw(int state) {
  switch (state) {
    case 0:
      return PlayerState.idle;
    case 1:
      return PlayerState.playing;
    case 2:
      return PlayerState.paused;
    case 3:
      return PlayerState.ended;
    default:
      assert(false, 'unknown state: $state');
      return PlayerState.error;
  }
}
