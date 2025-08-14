import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ogg_record_player/src/player.dart';
import 'package:ogg_record_player/src/player_state.dart';
import 'package:system_clock/system_clock.dart';

PlayerState _convertFromRawValue(int state) {
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

const MethodChannel _channel = MethodChannel('ogg_record_player');

final Map<int, OggOpusPlayerPluginImpl> _players = <int, OggOpusPlayerPluginImpl>{};
final Map<int, OggOpusRecorderPluginImpl> _recorders = <int, OggOpusRecorderPluginImpl>{};

bool _initialized = false;

void _initChannelIfNeeded() {
  if (_initialized) {
    return;
  }
  _initialized = true;
  _channel.setMethodCallHandler((MethodCall call) async {
    try {
      return await _handleMethodCall(call);
    } on Exception catch (error, stacktrace) {
      debugPrint('_handleMethodCall: $error $stacktrace');
    }
  });
}

Future<dynamic> _handleMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'onPlayerStateChanged':
      final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
      final int state = args['state'] as int;
      final num position = args['position'] as num;
      final num? duration = args['duration'] as num?;
      final int playerId = args['playerId'] as int;
      final int updateTime = args['updateTime'] as int;
      final double? speed = args['speed'] as double?;
      final OggOpusPlayerPluginImpl? player = _players[playerId];
      if (player == null) {
        return;
      }
      player._playerState.value = _convertFromRawValue(state);
      player
        .._lastUpdateTimeStamp = updateTime
        .._position = position.toInt()
        .._duration = (duration ?? 1).toInt()
        .._playbackRate = speed ?? 1.0;
    case 'onRecorderCanceled':
      final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
      final int recorderId = args['recorderId'] as int;
      final OggOpusRecorderPluginImpl? recorder = _recorders[recorderId];
      final int reason = args['reason'] as int;
      if (recorder == null) {
        return;
      }
      recorder.onCanceled(reason);
    case 'onRecorderStartFailed':
      final int recorderId = call.arguments['recorderId'] as int;
      final OggOpusRecorderPluginImpl? recorder = _recorders[recorderId];
      if (recorder == null) {
        return;
      }
      final String reason = call.arguments['error'] as String;
      debugPrint('onRecorderStartFailed: $reason');
    case 'onRecorderFinished':
      final int recorderId = call.arguments['recorderId'] as int;
      final OggOpusRecorderPluginImpl? recorder = _recorders[recorderId];
      if (recorder == null) {
        return;
      }
      final int duration = call.arguments['duration'] as int;
      final List<int> waveform = (call.arguments['waveform'] as List).cast<int>();
      recorder.onFinished(duration, waveform);
    default:
      break;
  }
}

class OggOpusPlayerPluginImpl extends OggOpusPlayer {
  OggOpusPlayerPluginImpl(this._path) : super.create() {
    _initChannelIfNeeded();
    
    // Validate path
    if (_path.isEmpty) {
      throw ArgumentError('Path cannot be empty');
    }
    if (!File(_path).existsSync()) {
      throw ArgumentError('File does not exist: $_path');
    }

    scheduleMicrotask(() async {
      try {
        _playerId = await _channel.invokeMethod('create', _path) as int;
        _players[_playerId] = this;
        _playerState.value = PlayerState.paused;
      } on Exception catch (error, stacktrace) {
        debugPrint('create play failed. error: $error $stacktrace');
        _playerState.value = PlayerState.error;
      }
      _createCompleter.complete();
    });
  }

  final String _path;

  int _playerId = -1;

  final Completer<void> _createCompleter = Completer<void>();

  final ValueNotifier<PlayerState> _playerState = ValueNotifier<PlayerState>(PlayerState.idle);
  int _position = 0;

  // [_position] updated timestamp, in milliseconds.
  int _lastUpdateTimeStamp = -1;

  double _playbackRate = 1;

  int _duration = 1;

  @override
  int get duration => _duration;

  @override
  int get currentPosition {
    if (_lastUpdateTimeStamp == -1) {
      return 0;
    }
    if (state.value != PlayerState.playing) {
      return _position;
    }
    final int offset = SystemClock.uptime().inMilliseconds - _lastUpdateTimeStamp;
    if (offset < 0) {
      return _position;
    }

    final int calculatedPosition = (_position + (offset / 1000.0) * _playbackRate).toInt();
    return calculatedPosition.clamp(0, _duration);
  }

  @override
  ValueListenable<PlayerState> get state => _playerState;

  @override
  Future<void> play({bool waitCreate = true}) async {
    try {
      if (waitCreate) {
        await _createCompleter.future;
      }
      if (_playerId <= 0) {
        return;
      }
      await _channel.invokeMethod('play', _playerId);
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _playerState.value = PlayerState.error;
    }
  }

  @override
  Future<void> pause() async {
    try {
      if (_playerId <= 0) {
        return;
      }
      await _channel.invokeMethod('pause', _playerId);
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  @override
  Future<void> setPlaybackRate(double speed) async {
    try {
      await _createCompleter.future;
      if (_playerId <= 0) {
        return;
      }
      if (speed < 0.5 || speed > 2.0) {
        throw ArgumentError('Speed must be between 0.5 and 2.0');
      }
      await _channel.invokeMethod('setPlaybackSpeed', <String, num>{'playerId': _playerId, 'speed': speed});
    } catch (e) {
      debugPrint('Error setting playback rate: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_playerId > 0) {
        await _channel.invokeMethod('stop', _playerId);
        _players.remove(_playerId);
      }
      _playerState.dispose();
    } catch (e) {
      debugPrint('Error disposing player: $e');
    }
  }

  @override
  Future<int?> getDuration() async {
    await _createCompleter.future;
    if (_playerId <= 0) {
      return 0;
    }
    final int? duration = await _channel.invokeMethod('getDuration', _playerId);
    return duration;
  }
}

class OggOpusRecorderPluginImpl extends OggOpusRecorder {
  OggOpusRecorderPluginImpl(this._path) : super.create() {
    _initChannelIfNeeded();
    
    // Validate path
    if (_path.isEmpty) {
      throw ArgumentError('Path cannot be empty');
    }
    
    scheduleMicrotask(() async {
      try {
        _id = await _channel.invokeMethod('createRecorder', _path) as int;
        _recorders[_id] = this;
      } on Exception catch (e) {
        debugPrint('create recorder failed. error: $e');
      }
      _createCompleter.complete();
    });
  }

  final String _path;
  int _id = -1;

  double? _duration;
  List<int>? _waveformData;

  final Completer<void> _createCompleter = Completer<void>();

  final Completer<void> _stopCompleter = Completer<void>();

  @override
  Future<void> start() async {
    try {
      await _createCompleter.future;
      if (_id <= 0) {
        return;
      }
      await _channel.invokeMethod('startRecord', _id);
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _createCompleter.future;
      if (_id <= 0) {
        return;
      }
      await _channel.invokeMethod('stopRecord', _id);
      await _stopCompleter.future;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_id > 0) {
        await _channel.invokeMethod('destroyRecorder', _id);
        _recorders.remove(_id);
      }
    } catch (e) {
      debugPrint('Error disposing recorder: $e');
    }
  }

  @override
  Future<double> duration() async => _duration ?? 0.0;

  @override
  Future<List<int>> getWaveformData() async => _waveformData ?? <int>[];

  void onCanceled(int reason) {
    _stopCompleter.complete();
  }

  void onFinished(int duration, List<int> waveform) {
    _duration = duration / 1000;
    _waveformData = waveform;
    _stopCompleter.complete();
  }
}
