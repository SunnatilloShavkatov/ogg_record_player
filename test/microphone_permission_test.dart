import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_record_player/ogg_record_player.dart';

void main() {
  group('MicrophonePermission.fromRaw', () {
    test('maps the shared native codes', () {
      expect(MicrophonePermission.fromRaw(0), MicrophonePermission.granted);
      expect(MicrophonePermission.fromRaw(1), MicrophonePermission.denied);
      expect(MicrophonePermission.fromRaw(2), MicrophonePermission.permanentlyDenied);
      expect(MicrophonePermission.fromRaw(3), MicrophonePermission.undetermined);
    });

    test('treats unknown codes as denied', () {
      expect(MicrophonePermission.fromRaw(-1), MicrophonePermission.denied);
      expect(MicrophonePermission.fromRaw(42), MicrophonePermission.denied);
    });
  });

  test('canRequest is true only while the prompt can still show', () {
    expect(MicrophonePermission.undetermined.canRequest, isTrue);
    expect(MicrophonePermission.denied.canRequest, isTrue);
    expect(MicrophonePermission.permanentlyDenied.canRequest, isFalse);
    expect(MicrophonePermission.granted.canRequest, isFalse);
    expect(MicrophonePermission.granted.isGranted, isTrue);
  });
}
