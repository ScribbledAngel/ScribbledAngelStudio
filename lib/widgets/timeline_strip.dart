import 'package:flutter/material.dart';

import '../models/stroke.dart';
import '../theme/app_theme.dart';
import 'frame_preview.dart';

class TimelineStrip extends StatelessWidget {
  final int frameCount;
  final List<Stroke> Function(int index) compositeStrokesAt;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddFrame;
  final ValueChanged<int> onDuplicate;
  final ValueChanged<int> onDelete;

  /// One peak (0.0-1.0) per frame, aligned 1:1 with the frame thumbnails -
  /// null when the shot has no audio (or it's still loading), in which case
  /// no waveform/keyframe row is shown at all.
  final List<double>? waveformPeaks;

  /// Frame indices with a sync-point marker set (see [onToggleKeyframe]).
  final Set<int> keyframeFrames;

  /// Called when the user taps a frame's waveform bar to add/remove a
  /// sync-point marker there - a separate tap target from [onSelect], so
  /// marking time doesn't also jump the current frame.
  final ValueChanged<int>? onToggleKeyframe;

  const TimelineStrip({
    super.key,
    required this.frameCount,
    required this.compositeStrokesAt,
    required this.currentIndex,
    required this.onSelect,
    required this.onAddFrame,
    required this.onDuplicate,
    required this.onDelete,
    this.waveformPeaks,
    this.keyframeFrames = const {},
    this.onToggleKeyframe,
  });

  void _showFrameOptions(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Frame ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Duplicate frame'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDuplicate(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text('Delete frame', style: TextStyle(color: AppColors.danger)),
              enabled: frameCount > 1,
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showWaveform = waveformPeaks != null;
    return Container(
      height: showWaveform ? 148 : 124,
      color: AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: frameCount + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == frameCount) {
            return _AddFrameButton(onTap: onAddFrame);
          }
          final isSelected = index == currentIndex;
          return GestureDetector(
            onTap: () => onSelect(index),
            onLongPress: () => _showFrameOptions(context, index),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: FramePreview(strokes: compositeStrokesAt(index), width: 48, height: 72),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? AppColors.accent : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (showWaveform) ...[
                  const SizedBox(height: 4),
                  _WaveformKeyframeCell(
                    peak: index < waveformPeaks!.length ? waveformPeaks![index] : 0,
                    isKeyframe: keyframeFrames.contains(index),
                    onTap: onToggleKeyframe == null ? null : () => onToggleKeyframe!(index),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One frame's audio-peak bar, doubling as a tappable sync-point marker.
/// A separate, smaller tap target nested inside the frame cell's own
/// GestureDetector - Flutter resolves a direct tap to the innermost
/// recognizer, so this doesn't also select the frame.
class _WaveformKeyframeCell extends StatelessWidget {
  final double peak;
  final bool isKeyframe;
  final VoidCallback? onTap;

  const _WaveformKeyframeCell({required this.peak, required this.isKeyframe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const maxBarHeight = 16.0;
    final barHeight = (2 + peak.clamp(0.0, 1.0) * (maxBarHeight - 2)).toDouble();
    final color = isKeyframe ? AppColors.accent : AppColors.textSecondary.withValues(alpha: 0.6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: maxBarHeight + 6,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: 5,
              height: barHeight,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            if (isKeyframe)
              const Positioned(
                top: 0,
                child: Icon(Icons.diamond, size: 9, color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddFrameButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddFrameButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.4)),
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.accent, size: 28),
      ),
    );
  }
}
