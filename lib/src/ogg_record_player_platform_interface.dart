import 'dart:typed_data';

import 'package:ogg_record_player/src/ogg_record_player_method_channel.dart';
import 'package:ogg_record_player/src/platform_events.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The native side of `OggOpusPlayer` and `OggOpusRecorder`: one integer id per native instance, and the
/// callbacks for every instance on two streams.
abstract class OggRecordPlayerPlatform extends PlatformInterface {
  /// Constructs an OggRecordPlayerPlatform.
  new() : super(token: _token);

  static final Object _token = Object();

  static OggRecordPlayerPlatform _instance = MethodChannelOggRecordPlayer();

  /// The default instance to use; [MethodChannelOggRecordPlayer] unless replaced, e.g. by a test.
  static OggRecordPlayerPlatform get instance => _instance;

  static set instance(OggRecordPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// State changes of every native player.
  Stream<PlayerStateEvent> get playerStateChanges {
    throw UnimplementedError('playerStateChanges has not been implemented.');
  }

  /// Finish, cancel and start-failure callbacks of every native recorder.
  Stream<RecorderEvent> get recorderEvents {
    throw UnimplementedError('recorderEvents has not been implemented.');
  }

  /// Opens the local file at [path] and returns the player id. Throws `OggOpusPlayerException`.
  Future<int> createPlayerFromFile(String path) {
    throw UnimplementedError('createPlayerFromFile() has not been implemented.');
  }

  /// Downloads [url] (`http`/`https`) into memory without caching or reusing earlier downloads and returns
  /// the player id. Throws `OggOpusPlayerException`.
  Future<int> createPlayerFromUrl(String url) {
    throw UnimplementedError('createPlayerFromUrl() has not been implemented.');
  }

  /// Plays [bytes], a whole Ogg Opus stream, from memory without writing a file, and returns the player id.
  /// Throws `OggOpusPlayerException`.
  Future<int> createPlayerFromBytes(Uint8List bytes) {
    throw UnimplementedError('createPlayerFromBytes() has not been implemented.');
  }

  /// Prepares the native playback stack without creating a player or activating the audio session.
  Future<void> warmUp() {
    throw UnimplementedError('warmUp() has not been implemented.');
  }

  Future<void> play(int playerId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Stops and releases the native player; [playerId] is invalid afterwards.
  Future<void> disposePlayer(int playerId) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }

  /// Seconds, including fractional seconds, or `null` when unknown.
  Future<double?> getDuration(int playerId) {
    throw UnimplementedError('getDuration() has not been implemented.');
  }

  Future<void> setPlaybackSpeed(int playerId, double speed) {
    throw UnimplementedError('setPlaybackSpeed() has not been implemented.');
  }

  /// Returns the recorder id. Throws `OggOpusRecorderException`.
  Future<int> createRecorder(String path) {
    throw UnimplementedError('createRecorder() has not been implemented.');
  }

  /// Throws `OggOpusRecorderException`, e.g. with code `PERMISSION_DENIED`.
  Future<void> startRecord(int recorderId) {
    throw UnimplementedError('startRecord() has not been implemented.');
  }

  /// Throws `OggOpusRecorderException`.
  Future<void> stopRecord(int recorderId) {
    throw UnimplementedError('stopRecord() has not been implemented.');
  }

  Future<void> destroyRecorder(int recorderId) {
    throw UnimplementedError('destroyRecorder() has not been implemented.');
  }
}
