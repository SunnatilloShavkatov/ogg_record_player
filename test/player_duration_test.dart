import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/player_plugin_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getDuration returns null when player creation fails', () async {
    final OggOpusPlayer player = OggRecordPlayerPluginImpl(
      (_) async => throw const OggOpusPlayerException(
        code: OggOpusPlayerException.fileNotFound,
        message: 'Audio file does not exist',
      ),
    );
    addTearDown(player.dispose);

    expect(await player.getDuration(), isNull);
  });
}
