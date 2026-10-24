import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ogg_record_player/ogg_record_player.dart';

/// Playback controls shared by bundled audio, remote audio and recordings.
class PlayerControls extends StatefulWidget {
  const new({super.key, required this.player, required this.onPlay});

  final OggOpusPlayer player;
  final Future<void> Function() onPlay;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const List<double> _speeds = <double>[0.5, 1, 1.5, 2];
  Timer? _timer;
  double _position = 0;
  double _duration = 0;
  int _speedIndex = 1;
  PlayerState? _lastState;

  @override
  void initState() {
    super.initState();
    widget.player.state.addListener(_syncPlayer);
    unawaited(_loadDuration());
    // Also read metadata while paused: Android may finish preparing after creation.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _syncPlayer());
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.state.removeListener(_syncPlayer);
      widget.player.state.addListener(_syncPlayer);
      _position = 0;
      _duration = 0;
      _speedIndex = 1;
      _lastState = null;
      unawaited(_loadDuration());
    }
  }

  Future<void> _loadDuration() async {
    final OggOpusPlayer player = widget.player;
    // iOS already knows the file length before the first playback callback.
    final double? seconds = await player.getDuration();
    if (!mounted || widget.player != player) {
      return;
    }
    setState(() {
      _duration = player.duration > 0 ? player.duration : (seconds ?? 0.0);
      _position = player.currentPosition;
    });
  }

  void _syncPlayer() {
    if (!mounted) {
      return;
    }
    final double position = widget.player.currentPosition;
    final double duration = widget.player.duration > 0 ? widget.player.duration : _duration;
    final PlayerState state = widget.player.state.value;
    if (position == _position && duration == _duration && state == _lastState) {
      return;
    }
    setState(() {
      _position = position;
      _duration = duration;
      _lastState = state;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.player.state.removeListener(_syncPlayer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState state = widget.player.state.value;
    final bool playing = state == PlayerState.playing;
    final double position = _duration > 0 ? _position.clamp(0, _duration) : 0;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _duration > 0 ? position / _duration : 0,
            minHeight: 6,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
        Row(
          spacing: 8,
          children: <Widget>[
            IconButton.filled(
              tooltip: playing ? 'Pause' : (state == PlayerState.ended ? 'Replay' : 'Play'),
              onPressed: state == PlayerState.idle || state == PlayerState.error
                  ? null
                  : () async {
                      if (playing) {
                        await widget.player.pause();
                      } else {
                        await widget.onPlay();
                      }
                    },
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              iconSize: 26,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Text(switch (state) {
                    PlayerState.idle => 'Loading audio…',
                    PlayerState.playing => 'Playing',
                    PlayerState.paused => position > 0 ? 'Paused' : 'Ready to play',
                    PlayerState.ended => 'Finished',
                    PlayerState.error => 'Unable to open audio',
                  }, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  DefaultTextStyle(
                    style: Theme.of(context).textTheme.labelSmall!
                        .copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
                    child: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        Text(
                          'p: ${formatAudioTime(position)}',
                          semanticsLabel: 'Position ${formatAudioTime(position)}',
                        ),
                        Text(
                          'd: ${_duration > 0 ? formatAudioTime(_duration) : '--:--'}',
                          semanticsLabel: 'Total duration ${_duration > 0 ? formatAudioTime(_duration) : 'loading'}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: state == PlayerState.idle || state == PlayerState.error
                  ? null
                  : () async {
                      final int next = (_speedIndex + 1) % _speeds.length;
                      final OggOpusPlayer player = widget.player;
                      await player.setPlaybackRate(_speeds[next]);
                      if (mounted && widget.player == player) {
                        setState(() => _speedIndex = next);
                      }
                    },
              child: Text('${_speeds[_speedIndex]}×'),
            ),
          ],
        ),
        if (widget.player.error case final OggOpusPlayerException error)
          Text(error.message, style: TextStyle(color: colors.error)),
      ],
    );
  }
}

String formatAudioTime(double seconds) {
  final int total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final String minutes = (total ~/ 60).toString().padLeft(2, '0');
  final String remainder = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
