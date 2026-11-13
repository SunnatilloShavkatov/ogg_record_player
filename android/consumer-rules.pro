# Dart reaches these classes only through JNI (lib/src/bindings), so R8 must keep their names and members.
-keep class uz.plugin.ogg_record_player.OggRecordPlayerApi { *; }
-keep interface uz.plugin.ogg_record_player.OggRecordPlayerApi$* { *; }
