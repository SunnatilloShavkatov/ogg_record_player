import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ogg_record_player/src/log_message.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_events.dart';
import 'package:ogg_record_player/src/player.dart';
import 'package:ogg_record_player/src/player_state.dart';

final Map<int, OggOpusPlayerPluginImpl> _players = <int, OggOpusPlayerPluginImpl>{};
final Map<int, OggOpusRecorderPluginImpl> _recorders = <int, OggOpusRecorderPluginImpl>{};

OggRecordPlayerPlatform get _platform => OggRecordPlayerPlatform.instance;

bool _isSubscribed = false;

// One subscription for all instances: each event is routed by id, so the cost doesn't grow with the player count.
void _subscribeIfNeeded() {
  if (_isSubscribed) {
    return;
  }
  _isSubscribed = true;
  _platform.playerStateChanges.listen((PlayerStateEvent event) => _players[event.playerId]?._onStateChanged(event));
  _platform.recorderEvents.listen((RecorderEvent event) => _recorders[event.recorderId]?._onEvent(event));
}

final class OggOpusPlayerPluginImpl extends OggOpusPlayer {
  /// [_create] opens the source on the native side and returns the player id.
  new(this._create) : super.create() {
    _subscribeIfNeeded();
    scheduleMicrotask(() async {
      if (_disposed) {
        _createCompleter.complete();
        return;
      }
      try {
        _playerId = await _create(_platform);
        if (_disposed) {
          // dispose() was called while we were creating - cleanup native side
          await _platform.disposePlayer(_playerId);
        } else {
          _players[_playerId] = this;
          _playerState.value = PlayerState.paused;
        }
      } on OggOpusPlayerException catch (error) {
        _fail(error);
      } on Exception catch (error, stacktrace) {
        logMessage('create player failed:', error: error, stackTrace: stacktrace);
        _fail(OggOpusPlayerException(code: OggOpusPlayerException.unknown, message: error.toString()));
      }
      _createCompleter.complete();
    });
  }

  final Future<int> Function(OggRecordPlayerPlatform platform) _create;

  int _playerId = -1;

  bool _disposed = false;

  OggOpusPlayerException? _error;

  final Completer<void> _createCompleter = Completer<void>();

  final ValueNotifier<PlayerState> _playerState = ValueNotifier<PlayerState>(PlayerState.idle);
  int _position = 0;

  // Monotonic time elapsed since [_position] was last updated by native.
  final Stopwatch _positionStopwatch = Stopwatch();

  double _playbackRate = 1;

  int _duration = 1;

  @override
  OggOpusPlayerException? get error => _error;

  @override
  int get duration => _duration;

  @override
  int get currentPosition {
    if (state.value != PlayerState.playing) {
      return _position;
    }
    final double elapsedSeconds = _positionStopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    return (_position + elapsedSeconds * _playbackRate).toInt();
  }

  @override
  ValueListenable<PlayerState> get state => _playerState;

  @override
  Future<void> play({bool waitCreate = true}) async {
    if (waitCreate) {
      await _createCompleter.future;
    }
    if (_playerId <= 0 || _disposed) {
      return;
    }
    await _platform.play(_playerId);
  }

  @override
  Future<void> pause() async {
    if (_playerId <= 0 || _disposed) {
      return;
    }
    await _platform.pause(_playerId);
  }

  @override
  Future<void> setPlaybackRate(double speed) async {
    await _createCompleter.future;
    if (_playerId <= 0 || _disposed) {
      return;
    }
    await _platform.setPlaybackSpeed(_playerId, speed);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _createCompleter.future;
    if (_playerId > 0 && _players.remove(_playerId) != null) {
      await _platform.disposePlayer(_playerId);
    }
  }

  @override
  Future<int?> getDuration() async {
    await _createCompleter.future;
    if (_playerId <= 0) {
      return 0;
    }
    return _platform.getDuration(_playerId);
  }

  void _fail(OggOpusPlayerException error) {
    logMessage('create player failed:', error: error);
    _error = error;
    _playerState.value = PlayerState.error;
  }

  void _onStateChanged(PlayerStateEvent event) {
    _position = event.position;
    _duration = event.duration;
    _playbackRate = event.speed;
    _positionStopwatch
      ..reset()
      ..start();
    // Notify after the fields above so listeners read the fresh position.
    _playerState.value = event.state;
  }
}

final class OggOpusRecorderPluginImpl extends OggOpusRecorder {
  new(this._path) : super.create() {
    _subscribeIfNeeded();
    scheduleMicrotask(() async {
      if (_disposed) {
        _createCompleter.complete();
        return;
      }
      try {
        _id = await _platform.createRecorder(_path);
        if (_disposed) {
          // dispose() was called while we were creating - cleanup native side
          await _platform.destroyRecorder(_id);
        } else {
          _recorders[_id] = this;
        }
      } on Exception catch (e, s) {
        logMessage('create recorder failed:', error: e, stackTrace: s);
      }
      _createCompleter.complete();
    });
  }

  final String _path;
  int _id = -1;

  bool _disposed = false;
  bool _startFailed = false;
  OggOpusRecorderException? _startError;

  double? _duration;
  List<int>? _waveformData;

  final Completer<void> _createCompleter = Completer<void>();

  Completer<void>? _stopCompleter;

  @override
  Future<void> start() async {
    await _createCompleter.future;
    if (_id <= 0 || _disposed) {
      return;
    }
    _stopCompleter = Completer<void>();
    _startFailed = false;
    _startError = null;
    try {
      await _platform.startRecord(_id);
    } on OggOpusRecorderException catch (e) {
      _startFailed = true;
      _startError = e;
      _safeCompleteStop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    await _createCompleter.future;
    if (_id <= 0 || _disposed) {
      return;
    }
    // If start failed, don't wait for callback
    if (_startFailed) {
      return;
    }
    try {
      await _platform.stopRecord(_id);
    } on OggOpusRecorderException {
      // No finish callback follows a failed stop; don't leave the completer pending.
      _safeCompleteStop();
      rethrow;
    }
    await _stopCompleter?.future;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _safeCompleteStop();
    await _createCompleter.future;
    if (_id > 0 && _recorders.remove(_id) != null) {
      await _platform.destroyRecorder(_id);
    }
  }

  @override
  OggOpusRecorderException? get startError => _startError;

  @override
  Future<double> duration() async => _duration ?? 0.0;

  @override
  Future<List<int>> getWaveformData() async => _waveformData ?? <int>[];

  void _onEvent(RecorderEvent event) {
    switch (event) {
      case RecorderStartFailedEvent(:final String error):
        logMessage('recorder start failed: $error');
        _startFailed = true;
        _startError = OggOpusRecorderException(code: OggOpusRecorderException.startFailed, message: error);
      case RecorderCanceledEvent():
        break;
      case RecorderFinishedEvent(:final int duration, :final Uint8List waveform):
        _duration = duration / 1000;
        _waveformData = waveform;
    }
    _safeCompleteStop();
  }

  void _safeCompleteStop() {
    final Completer<void>? completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
