# Dart reaches these classes only through JNI (lib/src/bindings), so R8 must keep their names and members.
# OggRecordPlayerApi is a Kotlin object: its @JvmStatic methods are the static entry points JNI looks up.
-keep class uz.plugin.ogg_record_player.OggRecordPlayerApi { *; }
-keep interface uz.plugin.ogg_record_player.OggRecordPlayerApi$* { *; }
