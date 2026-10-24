/// Why an `OggOpusPlayer` could not be created; read it from `OggOpusPlayer.error` once `state` is
/// `PlayerState.error`. [code] is one of the constants below, identical on Android and iOS.
class OggOpusPlayerException implements Exception {
  const new({required this.code, required this.message, this.details});

  /// The path was empty.
  static const String invalidArgument = 'INVALID_ARGUMENT';

  /// The local file (or the cached download) does not exist.
  static const String fileNotFound = 'FILE_NOT_FOUND';

  /// The download failed: no connection, timeout, TLS or DNS failure.
  static const String networkError = 'NETWORK_ERROR';

  /// The server answered with a non-2xx status; [details] carries the status text.
  static const String httpError = 'HTTP_ERROR';

  /// The file is not a playable Ogg Opus stream.
  static const String invalidFile = 'INVALID_FILE';

  /// The download could not be written to the cache.
  static const String ioError = 'IO_ERROR';

  /// Anything else, including a missing native implementation.
  static const String unknown = 'UNKNOWN';

  final String code;
  final String message;
  final String? details;

  @override
  String toString() => 'OggOpusPlayerException(code: $code, message: $message, details: $details)';
}

/// Why an `OggOpusRecorder` failed to start or stop; thrown by `start()` and exposed as `startError`.
class OggOpusRecorderException implements Exception {
  const new({required this.code, required this.message, this.details});

  /// The microphone permission has not been granted (Android).
  static const String permissionDenied = 'PERMISSION_DENIED';

  /// The native recorder reported a failure after `start()` returned; [message] carries its reason.
  static const String startFailed = 'START_FAILED';

  /// Anything else, including a missing native implementation.
  static const String unknown = 'UNKNOWN';

  final String code;
  final String message;
  final String? details;

  @override
  String toString() => 'OggOpusRecorderException(code: $code, message: $message, details: $details)';
}
