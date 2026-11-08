import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ogg_record_player/src/ogg_opus_exception.dart';
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_event_router.dart';
import 'package:ogg_record_player/src/platform_events.dart';
import 'package:ogg_record_player/src/player.dart';

OggRecordPlayerPlatform get _platform => OggRecordPlayerPlatform.instance;

final class OggOpusRecorderPluginImpl extends OggOpusRecorder {
  new(this._path) : super.create() {
    subscribeToPlatformEventsIfNeeded();
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
          recorderEventHandlers[_id] = _onEvent;
        }
      } on Exception catch (error) {
        // The recorder stays unusable: start() throws this, and stop() returns early without an id.
        _startFailed = true;
        _startError = error is OggOpusRecorderException
            ? error
            : OggOpusRecorderException(code: OggOpusRecorderException.unknown, message: error.toString());
      }
      _createCompleter.complete();
    });
  }

  /// How long [stop] waits for the native recorder to report the finished file.
  @visibleForTesting
  static Duration stopTimeout = const Duration(seconds: 10);

  final String _path;
  int _id = -1;

  bool _disposed = false;
  bool _startFailed = false;
  OggOpusRecorderException? _startError;

  double? _duration;
  List<int>? _waveformData;

  final Completer<void> _createCompleter = Completer<void>();

  Completer<void>? _stopCompleter;

  /// The last [stop] call; a new recording writes the same file, so it starts only after this one finished.
  Future<void>? _pendingStop;

  @override
  Future<void> start() async {
    await _createCompleter.future;
    if (_disposed) {
      return;
    }
    if (_id <= 0) {
      final OggOpusRecorderException? createError = _startError;
      if (createError != null) {
        throw createError;
      }
      return;
    }
    final Future<void>? pendingStop = _pendingStop;
    if (pendingStop != null) {
      try {
        await pendingStop;
      } on OggOpusRecorderException {
        // Already thrown to the caller of stop(); the new recording does not depend on it.
      }
    }
    // A recorder can record again into the same path; the previous recording's results no longer apply.
    _stopCompleter = Completer<void>();
    _startFailed = false;
    _startError = null;
    _duration = null;
    _waveformData = null;
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
  Future<void> stop() => _pendingStop = _stop();

  Future<void> _stop() async {
    await _createCompleter.future;
    // Captured before the native call: a start() waiting on this stop must not swap in its own completer.
    final Completer<void>? completer = _stopCompleter;
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
    await completer?.future.timeout(
      stopTimeout,
      onTimeout: () => throw const OggOpusRecorderException(
        code: OggOpusRecorderException.stopTimeout,
        message: 'The native recorder did not finish in time',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _safeCompleteStop();
    await _createCompleter.future;
    if (_id > 0 && recorderEventHandlers.remove(_id) != null) {
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
