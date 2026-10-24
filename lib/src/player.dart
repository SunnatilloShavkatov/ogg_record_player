import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:ogg_record_player/src/player_state.dart';

abstract class OggOpusPlayer {
  /// Picks [OggOpusPlayer.url] for an `http`/`https` [path] and [OggOpusPlayer.file] otherwise. Prefer the
  /// explicit constructors when the source type is known.
  factory(String path) => isRemoteAudioPath(path) ? OggOpusPlayer.url(path) : OggOpusPlayer.file(File(path));

  /// Plays the local Ogg Opus [file].
  factory file(File file) {
    _ensureSupportedPlatform();
    assert(file.existsSync(), 'file not exists: ${file.path}');
    return OggRecordPlayerPluginImpl((OggRecordPlayerPlatform platform) => platform.createPlayerFromFile(file.path));
  }

  /// Plays an `http`/`https` [url]. Each new player downloads the audio into memory without caching it,
  /// the same way on Android and iOS; [play] waits for the download.
  factory url(String url) {
    _ensureSupportedPlatform();
    assert(isRemoteAudioPath(url), 'url must be http or https: $url');
    return OggRecordPlayerPluginImpl((OggRecordPlayerPlatform platform) => platform.createPlayerFromUrl(url));
  }

  /// Plays [bytes], a whole Ogg Opus stream (e.g. a backend response), straight from memory: nothing is written
  /// to disk and nothing is cached.
  factory bytes(Uint8List bytes) {
    _ensureSupportedPlatform();
    return OggRecordPlayerPluginImpl((OggRecordPlayerPlatform platform) => platform.createPlayerFromBytes(bytes));
  }

  new create();

  /// Pays the native audio stack's one-time setup before the first player is created, so that player starts
  /// without the cold-start delay (about 100 ms on iOS). Optional and cheap to repeat; call it e.g. when a
  /// screen with audio opens. It never activates the audio session, so other apps' audio keeps playing.
  static Future<void> warmUp() async {
    if (Platform.isIOS || Platform.isAndroid) {
      await OggRecordPlayerPlatform.instance.warmUp();
    }
  }

  Future<void> pause();

  Future<void> play();

  Future<void> dispose();

  ValueListenable<PlayerState> get state;

  /// Why the player could not be created, or `null`. Set when [state] becomes [PlayerState.error].
  OggOpusPlayerException? get error;

  /// Current playing position, in seconds.
  double get currentPosition;

  /// playing duration, in seconds.
  double get duration;

  /// Total playing duration in seconds, including fractional seconds, or `null` when unknown.
  Future<double?> getDuration();

  /// Set playback rate, in the range 0.5 through 2.0.
  /// 1.0 is normal speed (default).
  Future<void> setPlaybackRate(double speed);
}

abstract class OggOpusRecorder {
  factory(String path) {
    if (Platform.isIOS || Platform.isAndroid) {
      return OggOpusRecorderPluginImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  new create();

  /// Starts recording. Throws an [OggOpusRecorderException] if the platform rejects the request, e.g. with
  /// code [OggOpusRecorderException.permissionDenied] when the microphone permission has not been granted.
  Future<void> start();

  /// Stops recording. Returns immediately without a result when [start] failed;
  /// check [startError] to tell that case apart from an empty recording.
  Future<void> stop();

  Future<void> dispose();

  /// The reason [start] failed (the thrown exception, or [OggOpusRecorderException.startFailed] when the native
  /// recorder failed afterwards), or `null` if it has not failed.
  OggOpusRecorderException? get startError;

  /// get the recorded audio waveform data.
  /// must be called after [stop] is called.
  Future<List<int>> getWaveformData();

  /// get the recorded audio duration.
  /// must be called after [stop] is called.
  Future<double> duration();
}

void _ensureSupportedPlatform() {
  if (!(Platform.isIOS || Platform.isAndroid)) {
    throw UnsupportedError('Platform not supported');
  }
}

/// Whether [path] is an `http`/`https` URL.
@visibleForTesting
bool isRemoteAudioPath(String path) {
  final String scheme = Uri.tryParse(path)?.scheme.toLowerCase() ?? '';
  return scheme == 'https' || scheme == 'http';
}
