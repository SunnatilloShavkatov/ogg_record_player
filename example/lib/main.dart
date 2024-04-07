// ignore_for_file: discarded_futures

import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:ogg_opus_player/ogg_opus_player.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await getTemporaryDirectory();
  final String workDir = p.join(tempDir.path, "ogg_opus_player");
  debugPrint("workDir: $workDir");
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Plugin example app"),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _PlayAsset(directory: workDir),
            const SizedBox(height: 20),
            _RecorderExample(dir: workDir),
          ],
        ),
      ),
    ),
  );
}

class _PlayAsset extends StatefulWidget {
  const _PlayAsset({required this.directory});

  final String directory;

  @override
  _PlayAssetState createState() => _PlayAssetState();
}

class _PlayAssetState extends State<_PlayAsset> {
  bool _copyCompleted = false;

  String _path = "";

  @override
  void initState() {
    super.initState();
    _copyAssets();
  }

  Future<void> _copyAssets() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File dest = File(p.join(dir.path, "test.ogg"));
    _path = dest.path;
    if (await dest.exists()) {
      setState(() {
        _copyCompleted = true;
      });
      return;
    }

    final ByteData bytes = await rootBundle.load("audios/test.ogg");
    await dest.writeAsBytes(bytes.buffer.asUint8List());
    setState(() {
      _copyCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) => _copyCompleted
      ? _OpusOggPlayerWidget(
          path: _path,
          key: ValueKey<String>(_path),
        )
      : const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          ),
        );
}

class _OpusOggPlayerWidget extends StatefulWidget {
  const _OpusOggPlayerWidget({super.key, required this.path});

  final String path;

  @override
  State<_OpusOggPlayerWidget> createState() => _OpusOggPlayerWidgetState();
}

class _OpusOggPlayerWidgetState extends State<_OpusOggPlayerWidget> {
  late final OggOpusPlayer _player = OggOpusPlayer(widget.path);

  Timer? timer;

  double _playingPosition = 0;
  int _playingDuration = 0;
  PlayerState state = PlayerState.idle;

  static const List<double> _kPlaybackSpeedSteps = <double>[0.5, 1, 1.5, 2];

  int _speedIndex = 1;

  @override
  void initState() {
    super.initState();
    state = _player.state.value;
    getDuration();
    timer = Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
      setState(() {
        _playingPosition = _player.currentPosition;
      });
    });
  }

  Future<void> getDuration() async {
    final int? duration = await _player.getDuration();
    if (duration != null) {
      setState(() {
        _playingDuration = duration;
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlayerState>(
        valueListenable: _player.state,
        builder: (_, PlayerState state, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text("P: ${countToTime(_playingPosition)}"),
            const SizedBox(width: 8),
            Text("D: ${countToTime(_playingDuration)}"),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                if (state == PlayerState.playing) {
                  _player.pause();
                } else {
                  _player.play();
                }
              },
              icon: Icon(
                state != PlayerState.playing
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
              ),
            ),
            IconButton(
              onPressed: () {
                Share.shareXFiles(<XFile>[XFile(widget.path)]);
              },
              icon: const Icon(Icons.share),
            ),
            TextButton(
              onPressed: () {
                _speedIndex++;
                if (_speedIndex >= _kPlaybackSpeedSteps.length) {
                  _speedIndex = 0;
                }
                _player.setPlaybackRate(_kPlaybackSpeedSteps[_speedIndex]);
              },
              child: Text("X${_kPlaybackSpeedSteps[_speedIndex]}"),
            ),
          ],
        ),
      );
}

class _RecorderExample extends StatefulWidget {
  const _RecorderExample({
    required this.dir,
  });

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
    _recordedPath = p.join(widget.dir, "test_recorded.ogg");
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 8),
          if (_recorder == null)
            IconButton(
              onPressed: () {
                final File file = File(_recordedPath);
                if (file.existsSync()) {
                  File(_recordedPath).deleteSync();
                }
                File(_recordedPath).createSync(recursive: true);
                final OggOpusRecorder recorder = OggOpusRecorder(_recordedPath)
                  ..start();
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
                debugPrint("recording stopped");
                debugPrint("duration: ${await _recorder?.duration()}");
                debugPrint("waveform: ${await _recorder?.getWaveformData()}");
                _recorder?.dispose();
                setState(() {
                  _recorder = null;
                });
              },
              icon: const Icon(Icons.stop),
            ),
          const SizedBox(height: 8),
          if (_recorder == null && File(_recordedPath).existsSync())
            _OpusOggPlayerWidget(path: _recordedPath),
        ],
      );
}

String countToTime(num count) {
  final int minute = count ~/ 60;
  final int second = (count % 60).toInt();
  return "0$minute:${second < 10 ? "0$second" : second}";
}
