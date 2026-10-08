import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frame_preview.dart';
import '../widgets/prompt_dialog.dart';
import 'shot_editor_screen.dart';

class ShotsScreen extends StatelessWidget {
  final String projectId;
  final String episodeId;

  const ShotsScreen({super.key, required this.projectId, required this.episodeId});

  Future<void> _createShot(BuildContext context) async {
    final appState = context.read<AppState>();
    final episode = appState.getEpisode(projectId, episodeId);
    final nextNumber = (episode?.shots.length ?? 0) + 1;
    final result = await showPromptDialog(
      context,
      title: 'New shot',
      fields: [
        PromptField(label: 'Name, e.g. Cold Open', initialValue: 'Shot ${nextNumber.toString().padLeft(3, '0')}'),
        const PromptField(label: 'Notes (optional)', maxLines: 3),
      ],
      confirmLabel: 'Create',
    );
    if (result == null || result[0].isEmpty) return;
    if (!context.mounted) return;
    final shot = await appState.addShot(projectId, episodeId, name: result[0], notes: result[1]);
    if (shot == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShotEditorScreen(projectId: projectId, episodeId: episodeId, shotId: shot.id),
      ),
    );
  }

  Future<void> _deleteShot(BuildContext context, Shot shot) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${shot.name}"?',
      message: 'This will permanently delete all ${shot.frames.length} drawn frame(s). This cannot be undone.',
    );
    if (confirmed && context.mounted) {
      await context.read<AppState>().deleteShot(projectId, episodeId, shot.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final episode = appState.getEpisode(projectId, episodeId);

    if (episode == null) {
      return const Scaffold(body: Center(child: Text('Episode not found')));
    }

    return Scaffold(
      appBar: AppBar(title: Text(episode.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createShot(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New shot'),
      ),
      body: episode.shots.isEmpty
          ? Center(
              child: Text(
                'No shots yet.\nTap "New shot" to add your first one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: episode.shots.length,
              onReorder: (oldIndex, newIndex) =>
                  appState.reorderShots(projectId, episodeId, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final shot = episode.shots[index];
                return Padding(
                  key: ValueKey(shot.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShotEditorScreen(
                            projectId: projectId,
                            episodeId: episodeId,
                            shotId: shot.id,
                          ),
                        ),
                      ),
                      onLongPress: () => _deleteShot(context, shot),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FramePreview(
                                frame: shot.frames.isNotEmpty ? shot.frames.first : null,
                                width: 48,
                                height: 72,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${(index + 1).toString().padLeft(3, '0')}  ${shot.name}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${shot.frames.length} frame${shot.frames.length == 1 ? '' : 's'} · '
                                    '${shot.fps} fps · ${shot.durationSeconds.toStringAsFixed(1)}s',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            _StatusChip(
                              status: shot.status,
                              onTap: () => appState.cycleShotStatus(projectId, episodeId, shot.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ShotStatus status;
  final VoidCallback onTap;

  const _StatusChip({required this.status, required this.onTap});

  Color get _color {
    switch (status) {
      case ShotStatus.notStarted:
        return AppColors.textSecondary;
      case ShotStatus.inProgress:
        return AppColors.warning;
      case ShotStatus.complete:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status == ShotStatus.complete ? '✓' : status == ShotStatus.inProgress ? '→' : '·',
          style: TextStyle(color: _color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
