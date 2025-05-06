import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:ogg_record_player/src/player_state.dart';

abstract class OggOpusPlayer {
  factory OggOpusPlayer(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusPlayerPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  OggOpusPlayer.create();

  void pause();

  void play();

  void dispose();

  ValueListenable<PlayerState> get state;

  /// Current playing position, in seconds.
  int get currentPosition;

  /// playing duration, in seconds.
  int get duration;

  /// Current playing position, in seconds.
  Future<int?> getDuration();

  /// Set playback rate, in the range 0.5 through 2.0.
  /// 1.0 is normal speed (default).
  void setPlaybackRate(double speed);
}

abstract class OggOpusRecorder {
  factory OggOpusRecorder(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusRecorderPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  OggOpusRecorder.create();

  void start();

  Future<void> stop();

  void dispose();

  /// get the recorded audio waveform data.
  /// must be called after [stop] is called.
  Future<List<int>> getWaveformData();

  /// get the recorded audio duration.
  /// must be called after [stop] is called.
  Future<double> duration();
}
