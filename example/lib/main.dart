// ignore_for_file: unawaited_futures, discarded_futures

import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

late AudioSession session;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await getTemporaryDirectory();
  final String workDir = p.join(tempDir.path, 'ogg_record_player');
  debugPrint('workDir: $workDir');
  session = await AudioSession.instance;
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Column(
          spacing: 20,
          children: <Widget>[
            _PlayAssetExample(directory: workDir),
            _RecorderExample(dir: workDir),
          ],
        ),
      ),
    ),
  );
}

class _PlayAssetExample extends StatefulWidget {
  const _PlayAssetExample({required this.directory});

  final String directory;

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
    final File dest = File(p.join(dir.path, 'test.ogg'));
    _path = dest.path;
    if (dest.existsSync()) {
      setState(() {
        _copyCompleted = true;
      });
      return;
    }

    final ByteData bytes = await rootBundle.load('audios/test.ogg');
    await dest.writeAsBytes(bytes.buffer.asUint8List());
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
  const _OpusOggPlayerWidget({super.key, required this.path});

  final String path;

  @override
  State<_OpusOggPlayerWidget> createState() => _OpusOggPlayerWidgetState();
}

class _OpusOggPlayerWidgetState extends State<_OpusOggPlayerWidget> {
  late OggOpusPlayer? _player;

  Timer? timer;

  int _playingPosition = 0;
  int _playingDuration = 0;

  static const List<double> _kPlaybackSpeedSteps = <double>[0.5, 1, 1.5, 2];

  int _speedIndex = 1;

  @override
  void initState() {
    super.initState();
    unawaited(initPlayer());
    timer = Timer.periodic(const Duration(milliseconds: 500), (Timer timer) {
      final PlayerState state = _player?.state.value ?? PlayerState.idle;
      if (state == PlayerState.playing) {
        setState(() {
          _playingPosition = _player?.currentPosition ?? 0;
          _playingDuration = _player?.duration ?? 0;
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> initPlayer() async {
    _speedIndex = 1;
    _player = OggOpusPlayer(widget.path);
    await session.configure(const AudioSessionConfiguration.music());
    final bool active = await session.setActive(true);
    debugPrint('active: $active');
    _player?.state.addListener(() async {
      if (mounted) {
        setState(() {});
        if (_player?.state.value == PlayerState.ended) {
          _player?.dispose();
          _player = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlayerState state = _player?.state.value ?? PlayerState.idle;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('p: ${_playingPosition.toStringAsFixed(2)} / d: ${_playingDuration.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          if (state == PlayerState.playing)
            IconButton(
              onPressed: () {
                _player?.pause();
              },
              icon: const Icon(Icons.pause),
            )
          else
            IconButton(
              onPressed: () async {
                if (state == PlayerState.paused) {
                  _player?.play();
                  return;
                } else {
                  await initPlayer();
                  _player?.play();
                }
              },
              icon: const Icon(Icons.play_arrow),
            ),
          TextButton(
            onPressed: () {
              _speedIndex++;
              if (_speedIndex >= _kPlaybackSpeedSteps.length) {
                _speedIndex = 0;
              }
              _player?.setPlaybackRate(_kPlaybackSpeedSteps[_speedIndex]);
            },
            child: Text('X${_kPlaybackSpeedSteps[_speedIndex]}'),
          ),
        ],
      ),
    );
  }
}

class _RecorderExample extends StatefulWidget {
  const _RecorderExample({required this.dir});

  final String dir;

  @override
  State<_RecorderExample> createState() => _RecorderExampleState();
}

class _RecorderExampleState extends State<_RecorderExample> {
  late String _recordedPath;

  OggOpusRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    _recordedPath = p.join(widget.dir, 'test_recorded.ogg');
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const SizedBox(height: 8),
      if (_recorder == null)
        IconButton(
          onPressed: () async {
            final File file = File(_recordedPath);
            if (file.existsSync()) {
              File(_recordedPath).deleteSync();
            }
            File(_recordedPath).createSync(recursive: true);
            await session.configure(
              const AudioSessionConfiguration(
                avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
                avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
                avAudioSessionMode: AVAudioSessionMode.spokenAudio,
              ),
            );
            await session.setActive(true);
            final OggOpusRecorder recorder = OggOpusRecorder(_recordedPath)..start();
            setState(() {
              _recorder = recorder;
            });
          },
          icon: const Icon(Icons.keyboard_voice_outlined),
        )
      else
        IconButton(
          onPressed: () async {
            await _recorder?.stop();
            debugPrint('recording stopped');
            debugPrint('duration: ${await _recorder?.duration()}');
            debugPrint('waveform: ${await _recorder?.getWaveformData()}');
            _recorder?.dispose();
            setState(() {
              _recorder = null;
              unawaited(
                session.setActive(
                  false,
                  avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
                ),
              );
            });
          },
          icon: const Icon(Icons.stop),
        ),
      const SizedBox(height: 8),
      if (_recorder == null && File(_recordedPath).existsSync()) _OpusOggPlayerWidget(path: _recordedPath),
    ],
  );
}
