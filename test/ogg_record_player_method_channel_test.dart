import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:ogg_record_player/src/ogg_record_player_method_channel.dart';
import 'package:ogg_record_player/src/player.dart' show isRemoteAudioPath;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelOggRecordPlayer platform;
  final List<MethodCall> calls = <MethodCall>[];

  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(platform.methodChannel, (
      MethodCall call,
    ) {
      calls.add(call);
      return handler(call);
    });
  }

  Future<void> sendFromNative(String method, Object arguments) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'ogg_record_player',
      message,
      (_) {},
    );
  }

  setUp(() {
    platform = MethodChannelOggRecordPlayer();
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      platform.methodChannel,
      null,
    );
  });

  test('each source has its own native method', () async {
    mockNative((MethodCall call) async => 7);
    final Uint8List bytes = Uint8List.fromList('OggS'.codeUnits);

    expect(await platform.createPlayerFromFile('/tmp/a.ogg'), 7);
    expect(await platform.createPlayerFromUrl('https://example.com/a.ogg'), 7);
    expect(await platform.createPlayerFromBytes(bytes), 7);

    expect(calls.map((MethodCall call) => call.method), <String>['createFromFile', 'createFromUrl', 'createFromBytes']);
    expect(calls[0].arguments, '/tmp/a.ogg');
    expect(calls[1].arguments, 'https://example.com/a.ogg');
    expect(calls[2].arguments, bytes);
  });

  test('player creation maps native errors to OggOpusPlayerException', () async {
    mockNative(
      (MethodCall call) =>
          throw PlatformException(code: OggOpusPlayerException.httpError, message: 'rejected', details: '404'),
    );

    await expectLater(
      platform.createPlayerFromUrl('https://example.com/missing.ogg'),
      throwsA(
        isA<OggOpusPlayerException>()
            .having((OggOpusPlayerException e) => e.code, 'code', OggOpusPlayerException.httpError)
            .having((OggOpusPlayerException e) => e.details, 'details', '404'),
      ),
    );
  });

  test('startRecord maps native errors to OggOpusRecorderException', () async {
    mockNative(
      (MethodCall call) =>
          throw PlatformException(code: OggOpusRecorderException.permissionDenied, message: 'RECORD_AUDIO'),
    );

    await expectLater(
      platform.startRecord(1),
      throwsA(
        isA<OggOpusRecorderException>().having(
          (OggOpusRecorderException e) => e.code,
          'code',
          OggOpusRecorderException.permissionDenied,
        ),
      ),
    );
  });

  test('fire-and-forget calls swallow native errors', () async {
    mockNative((MethodCall call) async => throw PlatformException(code: 'UNKNOWN'));

    await expectLater(platform.play(1), completes);
    await expectLater(platform.disposePlayer(1), completes);
    expect(await platform.getDuration(1), isNull);
  });

  test('onPlayerStateChanged is delivered as a PlayerStateEvent', () async {
    final List<PlayerStateEvent> events = <PlayerStateEvent>[];
    platform.playerStateChanges.listen(events.add);

    await sendFromNative('onPlayerStateChanged', <String, Object>{
      'playerId': 3,
      'state': 1,
      'position': 4.6,
      'duration': 12.5,
      'speed': 1.5,
    });

    expect(events.single.playerId, 3);
    expect(events.single.state, PlayerState.playing);
    expect(events.single.position, 4.6);
    expect(events.single.duration, 12.5);
    expect(events.single.speed, 1.5);
  });

  test('a malformed callback is dropped without breaking later ones', () async {
    final List<RecorderEvent> events = <RecorderEvent>[];
    platform.recorderEvents.listen(events.add);

    await sendFromNative('onRecorderFinished', <String, Object>{'recorderId': 1});
    await sendFromNative('onRecorderFinished', <String, Object>{
      'recorderId': 1,
      'duration': 1500,
      'waveform': Uint8List.fromList(<int>[1, 2, 3]),
    });

    final RecorderFinishedEvent finished = events.single as RecorderFinishedEvent;
    expect(finished.duration, 1500);
    expect(finished.waveform, <int>[1, 2, 3]);
  });

  test('isRemoteAudioPath accepts only http and https', () {
    expect(isRemoteAudioPath('https://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('HTTP://example.com/a.ogg'), isTrue);
    expect(isRemoteAudioPath('/var/mobile/a.ogg'), isFalse);
    expect(isRemoteAudioPath('file:///var/mobile/a.ogg'), isFalse);
  });
}
