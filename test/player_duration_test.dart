import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/player_plugin_impl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Host tests cannot load the native bindings, so the platform is a stand-in with no events.
final class _IdlePlatform extends OggRecordPlayerPlatform with MockPlatformInterfaceMixin {
  @override
  Stream<PlayerStateEvent> get playerStateChanges => const Stream<PlayerStateEvent>.empty();

  @override
  Stream<RecorderEvent> get recorderEvents => const Stream<RecorderEvent>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => OggRecordPlayerPlatform.instance = _IdlePlatform());

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
