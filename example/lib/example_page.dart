import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ogg_record_player_example/player_examples.dart';
import 'package:ogg_record_player_example/recorder_example.dart';

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
                  child: PlayAssetExample(),
                ),
                const _ExampleCard(
                  icon: Icons.link_rounded,
                  title: 'Remote audio',
                  subtitle: 'FFmpeg · testvector02.ogg (Opus)',
                  child: OpusOggPlayerWidget(path: 'https://samples.ffmpeg.org/A-codecs/opus/testvector02.ogg'),
                ),
                _ExampleCard(
                  icon: Icons.mic_none_rounded,
                  title: 'Voice recorder',
                  subtitle: 'Record a voice note and listen back.',
                  child: RecorderExample(dir: workDir, session: session),
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
