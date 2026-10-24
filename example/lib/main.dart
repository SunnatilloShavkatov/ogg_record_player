import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player_example/example_page.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await getTemporaryDirectory();
  final Directory workDir = Directory.fromUri(tempDir.uri.resolve('ogg_record_player/'));
  await workDir.create(recursive: true);
  final AudioSession session = await AudioSession.instance;
  unawaited(OggOpusPlayer.warmUp());
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        scaffoldBackgroundColor: const Color(0xFFF5F4F8),
        useMaterial3: true,
      ),
      home: ExamplePage(workDir: workDir, session: session),
    ),
  );
}
