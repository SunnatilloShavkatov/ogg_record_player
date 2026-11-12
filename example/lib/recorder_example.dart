import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player_example/player_controls.dart';
import 'package:ogg_record_player_example/player_examples.dart';
import 'package:permission_handler/permission_handler.dart';

class RecorderExample extends StatefulWidget {
  const new({super.key, required this.dir, required this.session});

  final Directory dir;
  final AudioSession session;

  @override
  State<RecorderExample> createState() => _RecorderExampleState();
}

class _RecorderExampleState extends State<RecorderExample> {
  OggOpusRecorder? _recorder;
  String? _recordedPath;
  bool _busy = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deactivateSession() async {
    await widget.session.setActive(
      false,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  }

  Future<void> _startRecording() async {
    setState(() => _busy = true);
    OggOpusRecorder? recorder;
    try {
      if (Platform.isAndroid && !await Permission.microphone.request().isGranted) {
        _showError('Microphone permission denied');
        return;
      }
      if (!mounted) {
        return;
      }
      // Unmount the old player before recording to a fresh file.
      setState(() => _recordedPath = null);
      final String path = File.fromUri(widget.dir.uri.resolve('recording_${DateTime.now().microsecondsSinceEpoch}.ogg'))
          .path;
      await File(path).create(recursive: true);
      await widget.session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        ),
      );
      if (!await widget.session.setActive(true)) {
        throw StateError('Audio session could not be activated');
      }
      recorder = OggOpusRecorder(path);
      await recorder.start();
      if (!mounted) {
        await recorder.dispose();
        await _deactivateSession();
        return;
      }
      _stopwatch
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      setState(() {
        _recorder = recorder;
        _recordedPath = path;
      });
    } on Object catch (error) {
      await recorder?.dispose();
      await _deactivateSession();
      _showError('Recording failed to start: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopRecording() async {
    final OggOpusRecorder? recorder = _recorder;
    if (recorder == null) {
      return;
    }
    setState(() => _busy = true);
    _timer?.cancel();
    _stopwatch.stop();
    bool finished = false;
    try {
      await recorder.stop();
      if (recorder.startError case final OggOpusRecorderException error) {
        throw error;
      }
      finished = await recorder.duration() > 0;
      if (!finished) {
        _showError('No audio was recorded. Try recording a little longer.');
      }
    } on Object catch (error) {
      _showError('Recording failed: $error');
    } finally {
      await recorder.dispose();
      await _deactivateSession();
      if (mounted) {
        setState(() {
          _recorder = null;
          _busy = false;
          if (!finished) {
            _recordedPath = null;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    _recorder?.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool recording = _recorder != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: <Widget>[
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: recording ? Theme.of(context).colorScheme.error : null,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          ),
          onPressed: _busy ? null : (recording ? _stopRecording : _startRecording),
          icon: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(
            _busy
                ? 'Please wait…'
                : recording
                ? 'Stop recording · ${formatAudioTime(_stopwatch.elapsedMilliseconds / 1000)}'
                : 'Start recording',
          ),
        ),
        if (!recording && _recordedPath != null && !_busy) ...<Widget>[
          const Divider(height: 1),
          OpusOggPlayerWidget(path: _recordedPath!, key: ValueKey<String>(_recordedPath!)),
        ] else if (!recording && !_busy)
          Text(
            'Your recording will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
