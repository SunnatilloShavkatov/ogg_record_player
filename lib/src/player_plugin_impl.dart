import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_event_router.dart';
import 'package:ogg_record_player/src/platform_events.dart';
import 'package:ogg_record_player/src/player.dart';
import 'package:ogg_record_player/src/player_state.dart';

export 'package:ogg_record_player/src/recorder_plugin_impl.dart';

OggRecordPlayerPlatform get _platform => OggRecordPlayerPlatform.instance;

final class OggRecordPlayerPluginImpl extends OggOpusPlayer {
  /// [_create] opens the source on the native side and returns the player id.
  new(this._create) : super.create() {
    subscribeToPlatformEventsIfNeeded();
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
          playerEventHandlers[_playerId] = _onStateChanged;
          _playerState.value = PlayerState.paused;
        }
      } on OggOpusPlayerException catch (error) {
        _fail(error);
      } on Exception catch (error) {
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
  double _position = 0;

  // Monotonic time elapsed since [_position] was last updated by native.
  final Stopwatch _positionStopwatch = Stopwatch();

  double _playbackRate = 1;

  double _duration = 0;

  @override
  OggOpusPlayerException? get error => _error;

  @override
  double get duration => _duration;

  @override
  double get currentPosition {
    if (state.value != PlayerState.playing) {
      return _position;
    }
    final double elapsedSeconds = _positionStopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    return _position + elapsedSeconds * _playbackRate;
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
    if (_playerId > 0 && playerEventHandlers.remove(_playerId) != null) {
      await _platform.disposePlayer(_playerId);
    }
  }

  @override
  Future<double?> getDuration() async {
    await _createCompleter.future;
    if (_playerId <= 0) {
      return null;
    }
    return _platform.getDuration(_playerId);
  }

  void _fail(OggOpusPlayerException error) {
    _error = error;
    _playerState.value = PlayerState.error;
  }

  void _onStateChanged(PlayerStateEvent event) {
    _position = event.position;
    _duration = event.duration;
    _playbackRate = event.speed;
    if (event.state == PlayerState.error) {
      _error = OggOpusPlayerException(
        code: event.errorCode ?? OggOpusPlayerException.unknown,
        message: 'Playback failed',
      );
    }
    _positionStopwatch
      ..reset()
      ..start();
    // Notify after the fields above so listeners read the fresh position.
    _playerState.value = event.state;
  }
}
