import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/prompt_dialog.dart';
import 'episodes_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  Future<void> _createProject(BuildContext context) async {
    final result = await showPromptDialog(
      context,
      title: 'New project',
      fields: const [
        PromptField(label: 'Title, e.g. Veritas'),
        PromptField(label: 'Description (optional)', maxLines: 2),
      ],
      confirmLabel: 'Create',
    );
    if (result == null || result[0].isEmpty) return;
    if (!context.mounted) return;
    final project = await context.read<AppState>().addProject(result[0], result[1]);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EpisodesScreen(projectId: project.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<AppState>().projects;

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProject(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New project'),
      ),
      body: projects.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_creation_outlined, size: 56, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text(
                      'No projects yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "New project" to start Veritas.',
                      style: TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ProjectCard(project: projects[index]),
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;

  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EpisodesScreen(projectId: project.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (project.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  project.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _Pill(icon: Icons.theaters_outlined, label: '${project.episodes.length} ep'),
                  const SizedBox(width: 8),
                  _Pill(
                    icon: Icons.check_circle_outline_rounded,
                    label: '${project.completedShotCount}/${project.totalShotCount} shots',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
