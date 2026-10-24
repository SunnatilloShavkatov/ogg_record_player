import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;

void logMessage(String message, {StackTrace? stackTrace, Object? error}) {
  if (kDebugMode) {
    developer.log('[ogg_record_player] $message', stackTrace: stackTrace, error: error);
  }
}
