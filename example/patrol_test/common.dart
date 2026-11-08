import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';
import 'package:permission_handler/permission_handler.dart';

/// `audios/test.ogg`: 31.12 s, mono Opus (checked with ffprobe).
const double assetDuration = 31.12;

Future<Uint8List> assetBytes() async {
  final ByteData data = await rootBundle.load('audios/test.ogg');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// A fresh path in a per-test directory; the file does not exist yet.
Future<String> freshPath(String name) async {
  final Directory temp = await getTemporaryDirectory();
  final Directory dir = Directory('${temp.path}/patrol_${DateTime.now().microsecondsSinceEpoch}');
  await dir.create(recursive: true);
  return '${dir.path}/$name';
}

Future<File> assetFile() async {
  final File file = File(await freshPath('asset.ogg'));
  await file.writeAsBytes(await assetBytes());
  return file;
}

/// Pumps a blank app, so the test runs inside a real, foreground Flutter activity.
Future<void> pumpHost(PatrolIntegrationTester $) => $.pumpWidget(const MaterialApp(home: Scaffold(body: Text('e2e'))));

/// Polls [condition] in real time; fails the test after [timeout] with [reason].
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String reason = 'condition',
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      fail('Timed out after $timeout waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> waitForState(OggOpusPlayer player, PlayerState state, {Duration timeout = const Duration(seconds: 5)}) =>
    waitUntil(() => player.state.value == state, timeout: timeout, reason: '$state (now ${player.state.value})');

/// Waits until the player left [PlayerState.idle], i.e. it was created or failed.
Future<PlayerState> settled(OggOpusPlayer player, {Duration timeout = const Duration(seconds: 10)}) async {
  await waitUntil(() => player.state.value != PlayerState.idle, timeout: timeout, reason: 'player creation');
  return player.state.value;
}

Future<void> delay(Duration duration) => Future<void>.delayed(duration);

/// Grants the microphone through the system dialog and prepares the iOS audio session for recording.
Future<void> grantMicrophone(PatrolIntegrationTester $) async {
  if (Platform.isAndroid) {
    final Future<PermissionStatus> request = Permission.microphone.request();
    if (await $.platform.mobile.isPermissionDialogVisible(timeout: const Duration(seconds: 5))) {
      await $.platform.mobile.grantPermissionWhenInUse();
    }
    expect(await request, PermissionStatus.granted);
    return;
  }
  final AudioSession session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    ),
  );
  // audio_session's permission request needs a compile-time macro on iOS, so let the first microphone
  // use raise the system dialog (as it does in an app) and answer it; the throwaway recording is discarded.
  final OggOpusRecorder probe = OggOpusRecorder(await freshPath('probe.ogg'));
  await probe.start();
  if (await $.platform.mobile.isPermissionDialogVisible(timeout: const Duration(seconds: 3))) {
    await $.platform.mobile.grantPermissionWhenInUse();
  }
  await probe.dispose();
}

/// Records [length] into a fresh file and returns the stopped recorder's results.
Future<Recording> record(String path, Duration length) async {
  final OggOpusRecorder recorder = OggOpusRecorder(path);
  try {
    await recorder.start();
    await delay(length);
    await recorder.stop();
    return Recording(await recorder.duration(), await recorder.getWaveformData());
  } finally {
    await recorder.dispose();
  }
}

final class Recording {
  const new(this.duration, this.waveform);

  final double duration;
  final List<int> waveform;
}

bool isOggFile(File file) {
  if (!file.existsSync() || file.lengthSync() < 4) {
    return false;
  }
  final List<int> head = file.openSync().readSync(4);
  return String.fromCharCodes(head) == 'OggS';
}

/// A loopback HTTP server inside the app, so URL playback is tested without the internet.
final class AudioServer {
  new _(this._server, this._audio);

  static Future<AudioServer> start(Uint8List audio) async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final AudioServer result = AudioServer._(server, audio);
    server.listen(result._handle);
    return result;
  }

  final HttpServer _server;
  final Uint8List _audio;
  final List<Completer<void>> _stalled = <Completer<void>>[];

  String url(String path) => 'http://127.0.0.1:${_server.port}/$path';

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    switch (request.uri.path) {
      case '/audio.ogg':
        response
          ..contentLength = _audio.length
          ..add(_audio);
      case '/chunked.ogg':
        // No Content-Length: the loader has to grow its buffer.
        for (int offset = 0; offset < _audio.length; offset += 4096) {
          response.add(_audio.sublist(offset, (offset + 4096).clamp(0, _audio.length)));
          await response.flush();
        }
      case '/text':
        response.write('<html>not audio</html>');
      case '/huge-declared.ogg':
        // Declares more than the 32 MiB cap but sends only the Ogg signature.
        response
          ..contentLength = 33 * 1024 * 1024
          ..add(_audio.sublist(0, 4096));
        await response.flush();
        await response.close().catchError((Object _) {});
        return;
      case '/huge-chunked.ogg':
        final Uint8List chunk = Uint8List(1024 * 1024)..setRange(0, 4, 'OggS'.codeUnits);
        try {
          for (int i = 0; i < 34; i++) {
            response.add(chunk);
            await response.flush();
          }
        } on Object {
          return; // The client gave up, as it should.
        }
      case '/stall.ogg':
        response
          ..contentLength = _audio.length
          ..add(_audio.sublist(0, 4));
        await response.flush();
        final Completer<void> stalled = Completer<void>();
        _stalled.add(stalled);
        await stalled.future;
        return;
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close().catchError((Object _) {});
  }

  Future<void> close() async {
    for (final Completer<void> stalled in _stalled) {
      stalled.complete();
    }
    await _server.close(force: true);
  }
}
