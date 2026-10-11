import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribbled_angel_studio/models/layer.dart';
import 'package:scribbled_angel_studio/models/project.dart';
import 'package:scribbled_angel_studio/models/stroke.dart';

/// Covers the Reference-vs-Render export rules from the rotoscoping spec:
/// a layer's TYPE decides export inclusion, never its editor visibility.
///
/// This is a repeatable checklist as much as a test suite - each group
/// below maps to one of the manually-verifiable scenarios (video-reference
/// scrubbing and project save/reopen round-tripping are exercised by hand
/// on-device, since they need real video/file I/O).
void main() {
  Stroke stroke() =>
      Stroke(id: 's', colorValue: 0xFF000000, width: 4, isEraser: false, points: [const Offset(0, 0)]);

  Shot buildShot({required List<Layer> layers}) => Shot(id: 'shot', name: 'Test Shot', layers: layers);

  Layer buildLayer({
    required String id,
    required LayerType type,
    bool visible = true,
    bool withStroke = true,
  }) =>
      Layer(
        id: id,
        name: id,
        type: type,
        visible: visible,
        frames: [AnimFrame(id: '$id-f0', strokes: withStroke ? [stroke()] : [])],
      );

  group('Reference layers never export', () {
    test('a visible Reference layer is excluded from export content', () {
      final shot = buildShot(layers: [buildLayer(id: 'ref', type: LayerType.reference, visible: true)]);
      expect(shot.exportLayerContentsAt(0), isEmpty);
      expect(shot.hasExportableContent, isFalse);
    });

    test('a hidden Reference layer is also excluded from export content', () {
      final shot = buildShot(layers: [buildLayer(id: 'ref', type: LayerType.reference, visible: false)]);
      expect(shot.exportLayerContentsAt(0), isEmpty);
    });

    test('a Reference layer still appears in the editor composite', () {
      final shot = buildShot(layers: [buildLayer(id: 'ref', type: LayerType.reference, visible: true)]);
      expect(shot.editorLayerContentsAt(0), isNotEmpty);
    });
  });

  group('Render layers follow visibility', () {
    test('a visible Render layer appears in export content', () {
      final shot = buildShot(layers: [buildLayer(id: 'render', type: LayerType.render, visible: true)]);
      expect(shot.exportLayerContentsAt(0), hasLength(1));
      expect(shot.hasExportableContent, isTrue);
    });

    test('a hidden Render layer is excluded from export content', () {
      final shot = buildShot(layers: [buildLayer(id: 'render', type: LayerType.render, visible: false)]);
      expect(shot.exportLayerContentsAt(0), isEmpty);
      expect(shot.hasExportableContent, isTrue); // still exportable once toggled visible
    });
  });

  group('Switching a layer\'s type', () {
    test('Reference -> Render makes its content exportable without losing it', () {
      final layer = buildLayer(id: 'l', type: LayerType.reference, visible: true);
      final shot = buildShot(layers: [layer]);
      expect(shot.exportLayerContentsAt(0), isEmpty);

      layer.type = LayerType.render;
      expect(shot.exportLayerContentsAt(0), hasLength(1));
      expect(layer.frames.first.strokes, isNotEmpty); // content preserved
    });

    test('Render -> Reference excludes content from export but preserves it', () {
      final layer = buildLayer(id: 'l', type: LayerType.render, visible: true);
      final shot = buildShot(layers: [layer]);
      expect(shot.exportLayerContentsAt(0), hasLength(1));

      layer.type = LayerType.reference;
      expect(shot.exportLayerContentsAt(0), isEmpty);
      expect(layer.frames.first.strokes, isNotEmpty); // content preserved
    });
  });

  test('multiple reference and render layers combine correctly', () {
    final shot = buildShot(layers: [
      buildLayer(id: 'video-ref', type: LayerType.reference),
      buildLayer(id: 'photo-bg', type: LayerType.render),
      buildLayer(id: 'pose-ref', type: LayerType.reference),
      buildLayer(id: 'lines', type: LayerType.render),
      buildLayer(id: 'colour', type: LayerType.render),
    ]);
    expect(shot.editorLayerContentsAt(0), hasLength(5));
    expect(shot.exportLayerContentsAt(0), hasLength(3));
  });

  group('Project persistence / migration', () {
    test('a layer saved before this feature existed migrates to Render, opacity 1.0', () {
      final json = {
        'id': 'old-layer',
        'name': 'Old Layer',
        'visible': true,
        'frames': [
          {'id': 'f0', 'strokes': []},
        ],
        // no 'type', 'opacity' or 'videoSource' keys at all.
      };
      final layer = Layer.fromJson(json);
      expect(layer.type, LayerType.render);
      expect(layer.opacity, 1.0);
      expect(layer.videoSource, isNull);
    });

    test('an existing shot with no reference layers exports exactly as before', () {
      final shot = buildShot(layers: [buildLayer(id: 'only-layer', type: LayerType.render)]);
      expect(shot.exportLayerContentsAt(0).length, shot.editorLayerContentsAt(0).length);
    });

    test('layer type/opacity/video source round-trip through JSON', () {
      final layer = Layer(
        id: 'l',
        name: 'Video Reference',
        type: LayerType.reference,
        opacity: 0.4,
        videoSource: VideoReferenceSource(
          sourceVideoFileName: 'clip.mp4',
          audioFileName: 'clip.m4a',
          snippetStart: 1.5,
          snippetEnd: 4.0,
          extractionFps: 12,
        ),
      );
      final restored = Layer.fromJson(layer.toJson());
      expect(restored.type, LayerType.reference);
      expect(restored.opacity, 0.4);
      expect(restored.videoSource?.sourceVideoFileName, 'clip.mp4');
      expect(restored.videoSource?.audioFileName, 'clip.m4a');
    });
  });
}
