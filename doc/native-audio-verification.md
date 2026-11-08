# Native audio verification

The repository workflow prohibits local iOS/Android builds by the coding agent.
Flutter tests cover the Dart channel/UI only; they do not exercise AudioQueue,
MediaCodec, audio focus, phone calls or physical Bluetooth routes.

Run these checks on a real iPhone and Android device before every release.
Use the example app, local files, remote URLs and in-memory bytes.

The Patrol suite in `example/patrol_test/` automates part of this table: play/pause/resume/speed, one player
at a time, replay after the end, truncated and invalid streams, URL success and every URL error code (served
from a loopback server inside the app), many players with dispose during creation, recording and playing it
back, recorder reuse and start-during-stop, short recordings, dispose during recording, `play()` while
recording, background and back, the 3-minute cap and Android's `PERMISSION_DENIED`. Run it with
`cd example && patrol test -d <device id>`. Calls, other apps taking audio focus, Bluetooth/wired routes,
stereo/chained streams and a full disk still need the manual checks below.

| Scenario                                                                       | Expected result                                                                                                |
|--------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| Other app is playing media, then start an Ogg player                           | Native nonmixing session/audio focus requests silence from the other media; Ogg plays alone.                   |
| Start another Ogg player                                                       | Previous Ogg player pauses; its position stops advancing.                                                      |
| Pause, resume, change speed between 0.5 and 2                                  | Audio resumes at the same position, speed changes without pitch changes, duration remains the source duration. |
| Rapid play/pause/replay and dispose during startup                             | Last user command wins; no stale callback starts audio, no crash or orphan player.                             |
| Incoming call while playing, then end/reject the call                          | Position freezes while interrupted; resumes from that position when the OS restores focus/permits resumption.  |
| Manually pause/dispose while a call is active                                  | No automatic resumption when the call ends.                                                                    |
| Other app permanently takes audio focus                                        | Ogg pauses and waits for an explicit play request.                                                             |
| Wired headphones, Bluetooth A2DP and route changes                             | System route is used; no plugin-specific automatic pause is added on disconnection.                            |
| Short clip under 120 ms; pause near the end of a longer clip                   | Full final samples play, exactly one end transition, final position equals duration.                           |
| Replay after completion on the same native player                              | Starts at zero and plays the whole clip again.                                                                 |
| Mono/stereo and chained Ogg Opus with differing channels                       | Correct speed/duration and stereo output; no buffer overrun or distorted channel interleaving.                 |
| Ogg page discontinuity/truncated payload                                       | Bounded decode failure/stop, no invalid buffer offsets, infinite retry or crash.                               |
| Start/stop a recording, then play it                                           | Existing permission/recording lifecycle remains valid; recording pauses any plugin playback.                   |
| Create/dispose players repeatedly, detach Flutter engine                       | Audio stops; native queues, decoders and audio focus are released.                                             |
| Create new players with the same URL, sequentially and concurrently            | Each player makes its own download; no plugin audio cache files are created or reused.                         |
| Replace a signed S3 URL after it expires                                       | The new player fetches the supplied URL; expired URLs return `HTTP_ERROR` instead of cached audio.             |
| URL returns non-Ogg bytes with HTTP 200, or HTTP 403/404                       | Creation reports `INVALID_FILE` or `HTTP_ERROR`, respectively, on both platforms.                              |
| Dispose while a URL is downloading, then create another player                 | Completed downloads do not leak a native player or prevent the next download.                                  |
| iOS: immediately dispose on completion and advance to the next clip repeatedly | UI stays responsive while the final AudioQueue callbacks drain.                                                |
| iOS: exercise an AudioQueue start failure                                      | Failure returns without synchronously waiting on the callback queue.                                           |
| Android: open a screen with many voice messages, play none                     | No ExoPlayer/decoder is created; durations still show (read from the Ogg container).                           |
| Android: first `play()` of a message                                           | Starts promptly after the lazy prepare; duration equals the one shown before playing.                          |
| Record about 100–200 ms, then stop                                             | `onRecorderCanceled` reason `4`; no file is left; `stop()` completes; `duration()` is `0.0`.                   |
| Record normally, stop, play the file                                           | `onRecorderFinished`; file plays fully; duration and waveform match the recording.                             |
| Record, stop, record again with the same recorder                              | Second recording replaces the file; `duration()` and waveform describe the second one; no `STOP_TIMEOUT`.      |
| Call `start()` without awaiting the previous `stop()`                          | The new recording starts only after the previous one finished; its file is intact.                             |
| Record for more than 3 minutes                                                 | Recording finishes by itself at 3 minutes on both platforms.                                                   |
| Incoming call while recording                                                  | Recording is canceled (reason `0`); Android needs no `READ_PHONE_STATE`. Starting during a call fails.         |
| Android: another app takes audio focus while recording                         | Recording is canceled; a navigation prompt that only ducks does not cancel it.                                 |
| `play()` while recording                                                       | Nothing plays on either platform; the recording continues.                                                     |
| Recording directory on a full disk                                             | Recording is canceled with reason `4`; no partial file remains; no crash.                                      |
| URL that trickles data slowly                                                  | Fails with `NETWORK_ERROR` after 120 s in total on both platforms.                                             |

For iOS, check both CocoaPods and SwiftPM integration when the maintainer builds.
AudioQueue allocation/refill, interruption ownership and final-buffer draining have
changed and require this device validation; no native compile/runtime pass is claimed.

## Size comparison

Compare the same consuming app before/after, in release mode, with the same ABI,
SDK and dependencies. Check Android R8 output and native shared-library exports,
and the linked iOS executable/link map rather than summing every xcframework slice.
The Android JNI library must continue exporting its four Java JNI entry points.
Do not remove supported ABI/simulator slices just to make repository totals smaller.

The Darwin release flag change only affects a later maintainer rebuild of the
vendored codecs. Current archives are unchanged. No APK/IPA reduction has been
measured because native builds are outside this task's permitted verification.
