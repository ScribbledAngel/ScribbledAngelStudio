# third_party

Local forks of pub.dev packages, used as path dependencies in `pubspec.yaml`,
kept here only when a package has a real bug we can't work around any other
way (wrong pub.dev version pin, upstream not responding, etc). Prefer a
normal pub.dev dependency whenever possible - only fork as a last resort.

## flutter_quick_video_encoder

Forked from v1.7.2. Its own `android/build.gradle` hardcodes
`compileSdkVersion 33`, which is too low for transitive AndroidX
dependencies (fragment/activity/lifecycle/core, pulled in by other plugins
in this build) that require compileSdk 34+. Flutter/AGP reads a module's
compileSdk very early during project evaluation, so trying to override it
from the root `build.gradle.kts` for an unpatched pub-cache copy doesn't
work reliably (see git history for the attempts). Bumped to 36 directly in
the local copy's `android/build.gradle` instead.

If a future pub.dev release of `flutter_quick_video_encoder` fixes this,
switch back to a normal version dependency and delete this folder.

Also patched `feedAudioEncoder()` in `FlutterQuickVideoEncoderPlugin.java`
to drain the audio encoder's output after every internal input-buffer push,
not just once after the whole chunk is submitted. One `appendAudioFrame`
call (one video frame's worth of PCM) is often bigger than the codec's own
input buffer and needs several pushes; without draining between them, the
encoder's output buffers fill up, it stops recycling input buffers, and
`dequeueInputBuffer` blocks forever - freezing the single processing thread,
then the platform channel, then the whole app (observed as an ANR/ "Lost
connection to device" partway through export once audio muxing was added).

## video_thumbnail

Forked from v0.5.6 (the latest available). Same `compileSdkVersion 33`
problem as above, bumped to 36. Also removed its own nested `buildscript`
block (which pinned AGP 4.1.0 and pulled from the now-dead `jcenter()`
repository) and its own `rootProject.allprojects` repositories block -
both unnecessary now that AGP and repositories are already provided by the
root project's `pluginManagement`/`allprojects` setup, and `jcenter()`
doesn't serve artifacts anymore regardless.

If a future pub.dev release fixes this, switch back to a normal version
dependency and delete this folder.
