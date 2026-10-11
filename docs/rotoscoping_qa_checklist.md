# Rotoscoping / Reference Layers - manual QA checklist

Automated coverage for the pure export-filtering logic lives in
[`test/layer_export_test.dart`](../test/layer_export_test.dart) (run with
`flutter test`). The scenarios below need a real device (file I/O, camera
roll, actual video playback) and are checked by hand after each change to
this feature.

- [ ] **1. Visible Reference layer, shown in editor, excluded from export.**
      Add an image layer as Reference, make it visible, export the shot.
      It appears in the Animation Editor; it is absent from the exported
      video.
- [ ] **2. Hidden Reference layer, also excluded from export.**
      Same as above but toggle the Reference layer's visibility off first.
      Still absent from the export (visibility was never the rule).
- [ ] **3. Visible Render layer appears in the export.**
      Draw on a Render layer, make it visible, export - it's in the video.
- [ ] **4. Hidden Render layer is excluded from the export.**
      Hide a Render layer with content, export - it's absent, same as any
      other hidden layer always behaved.
- [ ] **5. Reference -> Render preserves content and makes it exportable.**
      Flip an existing Reference layer's type to Render via the layer panel
      chip. Its drawings/image are still there, and now show up in export.
- [ ] **6. Render -> Reference preserves content, excludes from export.**
      Flip a Render layer to Reference. Nothing is deleted; a subsequent
      export no longer includes it.
- [ ] **7. Video-reference frames update while scrubbing.**
      Import a video snippet as a reference layer, scrub the shot's timeline
      - the correct extracted frame shows for each position. Press Play on
      the shot: playback shows the reference footage (and any Render-layer
      drawings over it) smoothly, with no black flashes or white gaps.
      Export the shot: the video-reference frames are absent from the
      exported video regardless of visibility; only Render-layer content
      appears.
- [ ] **7b. Video import trim UI.**
      Open "Video" from the layer panel, pick a clip. Confirm: first/last
      frame thumbnails match the selected range; the preview loops only the
      selected snippet; the waveform under the slider shows peaks for the
      whole clip with the selected range highlighted and a moving playhead
      during preview playback; extraction produces a reference layer and
      (if the clip has audio) sets the shot's audio automatically, asking
      first if the shot already had audio.
- [ ] **8. Multiple reference and render layers work together.**
      Build a shot with 2+ Reference layers (e.g. an image + a sketch) and
      2+ Render layers (line art + colour) at once. Confirm:
      - All layers are visible/selectable in the layer panel.
      - Drawing on one Render layer never affects another layer's strokes.
      - Export contains only the Render layers, correctly stacked/ordered.
- [ ] **9. Save and reopen preserves everything.**
      Close the app (or navigate away and back) after setting up layer
      types, opacities, and a reference image. Reopen the shot - type,
      order, visibility, opacity, image association, and drawings are all
      exactly as left.
- [ ] **10. Existing (pre-feature) projects still export unchanged.**
      Open a shot created before this feature existed. Its single layer
      should already show as "Render" with opacity 1.0, and exporting it
      should look identical to how it exported before.
