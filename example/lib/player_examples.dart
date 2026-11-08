import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player_example/player_controls.dart';
import 'package:path_provider/path_provider.dart';

class PlayAssetExample extends StatefulWidget {
  const new({super.key});

  @override
  State<PlayAssetExample> createState() => _PlayAssetExampleState();
}

class _PlayAssetExampleState extends State<PlayAssetExample> {
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
      ? OpusOggPlayerWidget(path: _path, key: ValueKey<String>(_path))
      : const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()));
}

class OpusOggPlayerWidget extends StatefulWidget {
  const new({super.key, required this.path});

  final String path;

  @override
  State<OpusOggPlayerWidget> createState() => _OpusOggPlayerWidgetState();
}

class _OpusOggPlayerWidgetState extends State<OpusOggPlayerWidget> {
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
