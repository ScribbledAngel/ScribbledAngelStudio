# Scribbled Angel Studio

A tiny, mobile-first 2D animation studio for making *Veritas*, one hand-drawn
shot at a time. Built with Flutter, for Android (Pixel 8a).

## What's working right now (Phase 1)

- **Home → Projects → Episodes → Shots → Animation Editor**, the full
  drill-down structure.
- Create/rename/delete projects, episodes and shots; drag to reorder.
- **Drawing canvas**: pencil, eraser, brush size, 13-swatch color picker,
  undo/redo, clear frame (confirmed, undoable).
- **Frame timeline**: add, duplicate, delete, select/scrub frames; FPS
  stepper; live duration readout.
- **Playback** of the current shot's frames at its own FPS.
- **Local saving**: everything autosaves to one JSON file in the app's
  private storage, with an atomic write and a `.bak` safety copy if the
  save file is ever unreadable.
- The **Move/Select** tool is visibly labelled "soon" and shows a message
  when tapped — it's not wired up yet, by design (see Roadmap below).

Nothing else is faked: every other button on screen does exactly what it says.

## Roadmap

- **Phase 2**: onion skinning, camera moves, audio recording/import, storyboard view.
- **Phase 3**: local video export, progress tracking, XP, daily goals, achievements.
- **Phase 4**: script/dialogue notes per shot, creative challenges, advanced camera tools, YouTube upload workflow.

## One-time setup (nothing is installed on this machine yet)

1. **Install Flutter.** Follow the official Windows install guide:
   https://docs.flutter.dev/get-started/install/windows
   This also walks you through installing Android Studio + the Android SDK,
   which Flutter needs to build for Android.
2. Open a terminal and confirm everything's wired up:
   ```bash
   flutter doctor
   ```
   Fix anything it flags with a `✗` (usually an Android SDK license to
   accept: `flutter doctor --android-licenses`).
3. From this project folder, generate the Android platform scaffolding
   (this won't touch the `lib/` folder or `pubspec.yaml` you already have —
   it only fills in the missing `android/` project files):
   ```bash
   cd C:\MyProjects\ScribbledAngelStudio
   flutter create --platforms=android --org com.scribbledangelstudio .
   ```
4. Fetch packages:
   ```bash
   flutter pub get
   ```

## Running it on your Pixel 8a

1. On the phone: **Settings → About phone**, tap **Build number** 7 times
   to unlock Developer options, then **Settings → Developer options → USB
   debugging** → on.
2. Plug the phone into this PC with a USB cable, and allow the "Allow USB
   debugging?" prompt on the phone.
3. Confirm it's detected:
   ```bash
   flutter devices
   ```
4. Run it:
   ```bash
   flutter run
   ```
   This installs a debug build straight onto the phone and gives you hot
   reload while you keep developing.

### Building an installable APK (no cable needed afterwards)

```bash
flutter build apk --release
```
The APK lands at `build/app/outputs/flutter-apk/app-release.apk` — copy it
to your phone (e.g. via a file-sync app or USB) and tap it to install.
You'll need to allow "install from this source" once; this is completely
normal for a personal, non-Play-Store app.

## Where your projects are stored

Everything you draw is saved locally on the phone, inside the app's own
private storage folder — not in this repo. It persists across app restarts
and normal phone backups, but isn't yet exportable/shareable (that's part
of Phase 3's export work).
