// Regenerates lib/src/bindings/ogg_record_player_api.g.dart from the Java facade. Run from the package root:
// `dart run tool/jnigen.dart`. It reads the Java source only, so the app is not built.
import 'dart:io';

import 'package:jnigen/jnigen.dart';

Future<void> main() async {
  final Uri packageRoot = Platform.script.resolve('../');
  await JniGenerator(
    input: Input(
      sourcePath: <Uri>[packageRoot.resolve('android/src/main/java/')],
      classes: <String>['uz.plugin.ogg_record_player.OggRecordPlayerApi'],
      backend: SummarizerBackend.doclet,
    ),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/src/bindings/ogg_record_player_api.g.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
  ).generate();
}
