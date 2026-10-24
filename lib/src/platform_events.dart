import 'dart:typed_data';

import 'package:ogg_record_player/src/player_state.dart';

/// A native player reported a new state (`onPlayerStateChanged`).
final class PlayerStateEvent {
  const new({
    required this.playerId,
    required this.state,
    required this.position,
    required this.duration,
    required this.speed,
  });

  final int playerId;
  final PlayerState state;

  /// Seconds.
  final double position;

  /// Seconds.
  final double duration;
  final double speed;
}

/// A native recorder finished, was cancelled or failed to start.
sealed class RecorderEvent {
  const new({required this.recorderId});

  final int recorderId;
}

/// `onRecorderCanceled`.
final class RecorderCanceledEvent extends RecorderEvent {
  const new({required super.recorderId, required this.reason});

  final int reason;
}

/// `onRecorderStartFailed`.
final class RecorderStartFailedEvent extends RecorderEvent {
  const new({required super.recorderId, required this.error});

  final String error;
}

/// `onRecorderFinished`.
final class RecorderFinishedEvent extends RecorderEvent {
  const new({required super.recorderId, required this.duration, required this.waveform});

  /// Milliseconds.
  final int duration;
  final Uint8List waveform;
}
