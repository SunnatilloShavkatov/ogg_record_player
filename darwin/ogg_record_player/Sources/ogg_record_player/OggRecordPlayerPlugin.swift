import Flutter

/// Only the engine lifecycle: Dart calls `OggRecordPlayerApi` through the Objective-C runtime, so there is no
/// method channel on Apple platforms either.
public class OggRecordPlayerPlugin: NSObject, FlutterPlugin {
  private let engineKey: Int64
  private let scope: EngineScope

  private init(engineKey: Int64, scope: EngineScope) {
    self.engineKey = engineKey
    self.scope = scope
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Each engine registers its own instance and gets its own players and recorders. Publishing keeps this
    // instance alive so `detachFromEngine` runs. Dart looks `OggRecordPlayerApi` up by name, so this reference is
    // also what keeps its class out of the linker's dead-code stripping.
    let key = OggRecordPlayerApi.engineKey(of: registrar)
    registrar.publish(OggRecordPlayerPlugin(engineKey: key, scope: OggRecordPlayerApi.attach(engine: key)))
  }

  /// Engine teardown (app closed or Flutter engine destroyed): free this engine's native players and recorders.
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    OggRecordPlayerApi.detach(engine: engineKey, scope: scope)
  }
}
