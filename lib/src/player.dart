import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:ogg_record_player/src/player_state.dart';

abstract class OggOpusPlayer {
  factory(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusPlayerPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  new create();

  Future<void> pause();

  Future<void> play();

  Future<void> dispose();

  ValueListenable<PlayerState> get state;

  /// Current playing position, in seconds.
  int get currentPosition;

  /// playing duration, in seconds.
  int get duration;

  /// Current playing position, in seconds.
  Future<int?> getDuration();

  /// Set playback rate, in the range 0.5 through 2.0.
  /// 1.0 is normal speed (default).
  Future<void> setPlaybackRate(double speed);
}

abstract class OggOpusRecorder {
  factory(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusRecorderPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  new create();

  /// Starts recording. Throws if the platform rejects the request, e.g. a
  /// `PlatformException` with code `PERMISSION_DENIED` when the microphone
  /// permission has not been granted.
  Future<void> start();

  /// Stops recording. Returns immediately without a result when [start] failed;
  /// check [startError] to tell that case apart from an empty recording.
  Future<void> stop();

  Future<void> dispose();

  /// The reason [start] failed (the thrown exception or the native failure
  /// message), or `null` if it has not failed.
  Object? get startError;

  /// get the recorded audio waveform data.
  /// must be called after [stop] is called.
  Future<List<int>> getWaveformData();

  /// get the recorded audio duration.
  /// must be called after [stop] is called.
  Future<double> duration();
}
