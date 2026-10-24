import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player_example/player_controls.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ExamplePage extends StatelessWidget {
  const new({super.key, required this.workDir, required this.session});

  final Directory workDir;
  final AudioSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ogg Opus'), backgroundColor: const Color(0xFFF5F4F8), centerTitle: false),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: <Widget>[
                const _ExampleCard(
                  icon: Icons.audio_file_outlined,
                  title: 'Sample audio',
                  subtitle: 'Play the bundled Ogg Opus file.',
                  child: _PlayAssetExample(),
                ),
                const _ExampleCard(
                  icon: Icons.link_rounded,
                  title: 'Remote audio',
                  subtitle: 'FFmpeg · testvector02.ogg (Opus)',
                  child: _OpusOggPlayerWidget(path: 'https://samples.ffmpeg.org/A-codecs/opus/testvector02.ogg'),
                ),
                _ExampleCard(
                  icon: Icons.mic_none_rounded,
                  title: 'Voice recorder',
                  subtitle: 'Record a voice note and listen back.',
                  child: _RecorderExample(dir: workDir, session: session),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExampleCard extends StatelessWidget {
  const new({required this.icon, required this.title, required this.subtitle, required this.child});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: <Widget>[
            Row(
              spacing: 10,
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(icon),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _PlayAssetExample extends StatefulWidget {
  const new();

  @override
  _PlayAssetExampleState createState() => _PlayAssetExampleState();
}

class _PlayAssetExampleState extends State<_PlayAssetExample> {
  bool _copyCompleted = false;

  String _path = '';

  @override
  void initState() {
    super.initState();
    unawaited(_copyAssets());
  }

  Future<void> _copyAssets() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File dest = File.fromUri(dir.uri.resolve('test.ogg'));
    _path = dest.path;
    if (!mounted) {
      return;
    }
    if (dest.existsSync()) {
      setState(() {
        _copyCompleted = true;
      });
      return;
    }

    final ByteData bytes = await rootBundle.load('audios/test.ogg');
    await dest.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    if (!mounted) {
      return;
    }
    setState(() {
      _copyCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) => _copyCompleted
      ? _OpusOggPlayerWidget(path: _path, key: ValueKey<String>(_path))
      : const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()));
}

class _OpusOggPlayerWidget extends StatefulWidget {
  const new({super.key, required this.path});

  final String path;

  @override
  State<_OpusOggPlayerWidget> createState() => _OpusOggPlayerWidgetState();
}

class _OpusOggPlayerWidgetState extends State<_OpusOggPlayerWidget> {
  late final OggOpusPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = OggOpusPlayer(widget.path);
  }

  @override
  void dispose() {
    _player.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlayerControls(player: _player, onPlay: _player.play);
}

class _RecorderExample extends StatefulWidget {
  const new({required this.dir, required this.session});

  final Directory dir;
  final AudioSession session;

  @override
  State<_RecorderExample> createState() => _RecorderExampleState();
}

class _RecorderExampleState extends State<_RecorderExample> {
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
          _OpusOggPlayerWidget(path: _recordedPath!, key: ValueKey<String>(_recordedPath!)),
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
