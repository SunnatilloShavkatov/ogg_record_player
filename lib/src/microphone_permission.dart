/// The microphone permission recording needs, as reported by `OggOpusRecorder.permissionStatus` and
/// `OggOpusRecorder.requestPermission`. The raw values are shared with the native sides.
enum MicrophonePermission {
  /// Recording may start.
  granted,

  /// Refused, but the system prompt can still be shown again (Android only).
  denied,

  /// Refused and the prompt will not be shown again: only the app's settings page can grant it
  /// (`OggOpusRecorder.openAppSettings`). On iOS every refusal is permanent.
  permanentlyDenied,

  /// Never asked: requesting shows the system prompt.
  undetermined;

  /// The status a native code stands for; an unknown code counts as [denied].
  static MicrophonePermission fromRaw(int raw) => raw >= 0 && raw < values.length ? values[raw] : denied;

  bool get isGranted => this == granted;

  /// Whether a request can still show the system prompt.
  bool get canRequest => this == denied || this == undetermined;
}
