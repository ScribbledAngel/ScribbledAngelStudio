import 'package:flutter_test/flutter_test.dart';
import 'package:scribbled_angel_studio/models/project.dart';

/// Covers [Shot.audioKeyframes] and [Shot.audioKeyframeFrames] - sync-point
/// markers are stored as seconds from frame 0 (not a raw frame index) so
/// they stay meaningful if frames are inserted/deleted earlier in the shot;
/// this checks the seconds<->frame mapping and JSON round-trip. The actual
/// waveform decode needs real device audio codecs, so it's checked by hand
/// (see docs/rotoscoping_qa_checklist.md).
void main() {
  group('Shot.audioKeyframeFrames', () {
    test('maps seconds onto the nearest frame at the shot\'s fps', () {
      final shot = Shot(id: 's', name: 'Test', fps: 10);
      shot.layers.first.frames.addAll(List.generate(20, (i) => AnimFrame(id: 'f$i')));
      // frameCount == 20 at fps 10 -> frame i covers i/10 .. (i+1)/10 seconds.
      shot.audioKeyframes = [0.0, 0.53, 1.0];

      expect(shot.audioKeyframeFrames, {0, 5, 10});
    });

    test('clamps a keyframe beyond the last frame to the last frame', () {
      final shot = Shot(id: 's', name: 'Test', fps: 10);
      shot.layers.first.frames.addAll(List.generate(5, (i) => AnimFrame(id: 'f$i')));
      shot.audioKeyframes = [99.0];

      expect(shot.audioKeyframeFrames, {shot.frameCount - 1});
    });

    test('empty when there are no keyframes or no frames', () {
      final shot = Shot(id: 's', name: 'Test', fps: 10);
      shot.layers.first.frames.addAll(List.generate(5, (i) => AnimFrame(id: 'f$i')));
      expect(shot.audioKeyframeFrames, isEmpty);

      shot.audioKeyframes = [0.1];
      shot.layers.first.frames.clear();
      expect(shot.audioKeyframeFrames, isEmpty);
    });
  });

  group('audioKeyframes JSON round-trip', () {
    test('persists and restores keyframe times', () {
      final shot = Shot(id: 's', name: 'Test', fps: 12)..audioKeyframes = [0.25, 1.5, 3.0];
      final restored = Shot.fromJson(shot.toJson());
      expect(restored.audioKeyframes, [0.25, 1.5, 3.0]);
    });

    test('older saves with no audioKeyframes field default to empty', () {
      final shot = Shot(id: 's', name: 'Test');
      final json = shot.toJson()..remove('audioKeyframes');
      final restored = Shot.fromJson(json);
      expect(restored.audioKeyframes, isEmpty);
    });
  });
}
