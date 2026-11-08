import 'package:ogg_record_player/src/ogg_record_player_platform_interface.dart';
import 'package:ogg_record_player/src/platform_events.dart';

/// Event handlers of the live players and recorders, by native id.
final Map<int, void Function(PlayerStateEvent event)> playerEventHandlers = <int, void Function(PlayerStateEvent)>{};
final Map<int, void Function(RecorderEvent event)> recorderEventHandlers = <int, void Function(RecorderEvent)>{};

bool _isSubscribed = false;

/// One subscription for all instances: each event is routed by id, so the cost doesn't grow with the player count.
void subscribeToPlatformEventsIfNeeded() {
  if (_isSubscribed) {
    return;
  }
  _isSubscribed = true;
  final OggRecordPlayerPlatform platform = OggRecordPlayerPlatform.instance;
  platform.playerStateChanges.listen((PlayerStateEvent event) => playerEventHandlers[event.playerId]?.call(event));
  platform.recorderEvents.listen((RecorderEvent event) => recorderEventHandlers[event.recorderId]?.call(event));
}
