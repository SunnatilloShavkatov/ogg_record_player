import 'dart:developer' show log;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record -> write -> read -> play', (WidgetTester tester) async {
    final Directory dir = await getTemporaryDirectory();
    final String path = p.join(dir.path, 'itest.ogg');
    final File file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
    file.createSync(recursive: true);

    final OggOpusRecorder recorder = OggOpusRecorder(path);
    await recorder.start();
    await Future<void>.delayed(const Duration(seconds: 2));
    await recorder.stop();
    final double duration = await recorder.duration();
    final List<int> waveform = await recorder.getWaveformData();
    await recorder.dispose();

    log('ITEST bytes=${file.lengthSync()} duration=$duration waveform=${waveform.length}');
    expect(file.lengthSync(), greaterThan(0));
    expect(duration, greaterThan(0));

    final OggOpusPlayer player = OggOpusPlayer(path);
    await player.play();
    await Future<void>.delayed(const Duration(seconds: 1));
    final int? playDuration = await player.getDuration();
    log('ITEST play state=${player.state.value} pos=${player.currentPosition} dur=$playDuration');
    expect(player.state.value, PlayerState.playing);
    expect(playDuration, isNotNull);
    expect(playDuration, greaterThan(0));
    await player.dispose();
  });
}
