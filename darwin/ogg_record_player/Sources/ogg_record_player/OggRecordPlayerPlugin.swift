import Flutter

/// Only the engine lifecycle: Dart calls `OggRecordPlayerApi` through the Objective-C runtime, so there is no
/// method channel on Apple platforms either.
public class OggRecordPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Publishing keeps this instance alive so `detachFromEngine` runs. Dart looks `OggRecordPlayerApi` up by
    // name, so this reference is also what keeps its class out of the linker's dead-code stripping.
    _ = OggRecordPlayerApi.self
    registrar.publish(OggRecordPlayerPlugin())
  }

  /// Engine teardown (app closed or Flutter engine destroyed): free every native player and recorder.
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    OggRecordPlayerApi.detach()
  }
}
