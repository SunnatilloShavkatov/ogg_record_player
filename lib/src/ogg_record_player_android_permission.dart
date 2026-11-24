import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:ogg_record_player/src/bindings/ogg_record_player_api.g.dart';
import 'package:ogg_record_player/src/microphone_permission.dart';
import 'package:ogg_record_player/src/native_results.dart';
import 'package:ogg_record_player/src/ogg_record_player_android.dart' show handOver;
import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';

/// The microphone permission over JNI. The prompt needs the calling engine's activity, so calls carry its id.
mixin AndroidMicrophonePermission on OggRecordPlayerPlatform {
  int get _permissionEngineId => engineIdForNative(PlatformDispatcher.instance.engineId);

  @override
  Future<MicrophonePermission> microphonePermission() async =>
      MicrophonePermission.fromRaw(OggRecordPlayerApi.microphonePermission(_permissionEngineId));

  @override
  Future<MicrophonePermission> requestMicrophonePermission() {
    final Completer<MicrophonePermission> completer = Completer<MicrophonePermission>();
    final OggRecordPlayerApi$PermissionCallback callback = OggRecordPlayerApi$PermissionCallback.implement(
      $OggRecordPlayerApi$PermissionCallback(
        onResult: (int status) {
          if (!completer.isCompleted) {
            completer.complete(MicrophonePermission.fromRaw(status));
          }
        },
        onResult$async: true,
      ),
    );
    final int engineId = _permissionEngineId;
    handOver(callback, (OggRecordPlayerApi$PermissionCallback proxy) {
      OggRecordPlayerApi.requestMicrophonePermission(engineId, proxy);
    });
    return completer.future;
  }

  @override
  Future<bool> openAppSettings() async => OggRecordPlayerApi.openAppSettings(_permissionEngineId);
}
