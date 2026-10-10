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
