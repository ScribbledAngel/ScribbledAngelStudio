import 'package:flutter/material.dart';

import '../models/frame.dart';
import '../theme/app_theme.dart';
import 'frame_preview.dart';

class TimelineStrip extends StatelessWidget {
  final List<AnimFrame> frames;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddFrame;
  final ValueChanged<int> onDuplicate;
  final ValueChanged<int> onDelete;

  const TimelineStrip({
    super.key,
    required this.frames,
    required this.currentIndex,
    required this.onSelect,
    required this.onAddFrame,
    required this.onDuplicate,
    required this.onDelete,
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
              enabled: frames.length > 1,
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
    return Container(
      height: 124,
      color: AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: frames.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == frames.length) {
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
                    child: FramePreview(frame: frames[index], width: 48, height: 72),
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
              ],
            ),
          );
        },
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
