import 'package:ogg_record_player/src/ogg_opus_exception.dart';

/// The duration a native `getDuration` answer stands for: null when the native side does not know it, so a real
/// zero-second duration stays distinct from missing metadata.
double? durationFromNative({required bool known, required double seconds}) => known ? seconds : null;

/// Checks the id `createRecorder` returned: a negative id means the native side rejected the path.
int recorderIdFromNative(int recorderId) {
  if (recorderId < 0) {
    throw const OggOpusRecorderException(
      code: OggOpusRecorderException.unknown,
      message: 'recorder path must be a non-empty string',
    );
  }
  return recorderId;
}
