import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/episode.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/prompt_dialog.dart';
import 'shots_screen.dart';

class EpisodesScreen extends StatelessWidget {
  final String projectId;

  const EpisodesScreen({super.key, required this.projectId});

  Future<void> _createEpisode(BuildContext context) async {
    final appState = context.read<AppState>();
    final nextNumber = (appState.getProject(projectId)?.episodes.length ?? 0) + 1;
    final result = await showPromptDialog(
      context,
      title: 'New episode',
      fields: [PromptField(label: 'Title', initialValue: 'Episode $nextNumber')],
      confirmLabel: 'Create',
    );
    if (result == null || result[0].isEmpty) return;
    if (!context.mounted) return;
    final episode = await appState.addEpisode(projectId, result[0]);
    if (episode == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShotsScreen(projectId: projectId, episodeId: episode.id),
      ),
    );
  }

  Future<void> _deleteEpisode(BuildContext context, Episode episode) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${episode.title}"?',
      message: 'This will delete all ${episode.shots.length} shot(s) inside it. This cannot be undone.',
    );
    if (confirmed && context.mounted) {
      await context.read<AppState>().deleteEpisode(projectId, episode.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final project = appState.getProject(projectId);

    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    return Scaffold(
      appBar: AppBar(title: Text(project.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createEpisode(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New episode'),
      ),
      body: project.episodes.isEmpty
          ? Center(
              child: Text(
                'No episodes yet.\nTap "New episode" to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: project.episodes.length,
              onReorder: (oldIndex, newIndex) =>
                  appState.reorderEpisodes(projectId, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final episode = project.episodes[index];
                return Padding(
                  key: ValueKey(episode.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShotsScreen(projectId: projectId, episodeId: episode.id),
                        ),
                      ),
                      onLongPress: () => _deleteEpisode(context, episode),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    episode.title,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${episode.completedShotCount}/${episode.shots.length} shots complete',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
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
