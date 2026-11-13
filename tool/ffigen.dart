// Regenerates lib/src/bindings/ogg_record_player_darwin.g.dart and the Objective-C wrapper
// darwin/ogg_record_player/Sources/ogg_record_player_c/ogg_record_player_darwin.m from ogg_record_player_api.h.
// Run from the package root: `dart run tool/ffigen.dart`.
import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final Uri packageRoot = Platform.script.resolve('../');
  final Uri cSources = packageRoot.resolve('darwin/ogg_record_player/Sources/ogg_record_player_c/');
  await FfiGenerator(
    output: Output(
      dart: DartOutput(path: packageRoot.resolve('lib/src/bindings/ogg_record_player_darwin.g.dart')),
      objectiveCFile: cSources.resolve('ogg_record_player_darwin.m'),
    ),
    objectiveC: const ObjectiveC(),
    input: Input(entryPoints: <Uri>[cSources.resolve('ogg_record_player_api.h')]),
    visitors: <Visitor>[
      Visitor(
        objCInterface: (node) {
          if (node.originalName == 'OggRecordPlayerApi') {
            node.isIncluded = true;
          }
        },
      ),
    ],
  ).generate();
}
