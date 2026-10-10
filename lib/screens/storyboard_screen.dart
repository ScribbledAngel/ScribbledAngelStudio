import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frame_preview.dart';
import 'shot_editor_screen.dart';
import 'storyboard_sketch_screen.dart';

/// Every shot in an episode, shown as a thumbnail grid - a quick way to see
/// the whole episode at a glance and jump into sketching or animating any
/// shot.
class StoryboardScreen extends StatelessWidget {
  final String projectId;
  final String episodeId;

  const StoryboardScreen({super.key, required this.projectId, required this.episodeId});

  void _showShotOptions(BuildContext context, Shot shot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(shot.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Sketch storyboard'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoryboardSketchScreen(
                      projectId: projectId,
                      episodeId: episodeId,
                      shotId: shot.id,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('Open shot editor'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShotEditorScreen(
                      projectId: projectId,
                      episodeId: episodeId,
                      shotId: shot.id,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final episode = context.watch<AppState>().getEpisode(projectId, episodeId);
    if (episode == null) {
      return const Scaffold(body: Center(child: Text('Episode not found')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Storyboard · ${episode.title}')),
      body: episode.shots.isEmpty
          ? Center(
              child: Text('No shots yet', style: TextStyle(color: AppColors.textSecondary)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.78,
              ),
              itemCount: episode.shots.length,
              itemBuilder: (context, index) {
                final shot = episode.shots[index];
                final hasStoryboardSketch = shot.storyboardFrame.strokes.isNotEmpty;
                return GestureDetector(
                  onTap: () => _showShotOptions(context, shot),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: AspectRatio(
                              aspectRatio: shot.orientation.aspectRatio,
                              child: FramePreview(
                                strokes: hasStoryboardSketch
                                    ? shot.storyboardFrame.strokes
                                    : (shot.frameCount > 0 ? shot.compositeStrokesAt(0) : const []),
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${(index + 1).toString().padLeft(3, '0')}  ${shot.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${shot.durationSeconds.toStringAsFixed(1)}s',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                  const Spacer(),
                                  Text(
                                    shot.status == ShotStatus.complete
                                        ? '✓'
                                        : shot.status == ShotStatus.inProgress
                                            ? '→'
                                            : '·',
                                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
