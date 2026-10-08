import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import 'projects_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final projectCount = appState.projects.length;
    final totalShots = appState.projects.fold<int>(0, (sum, p) => sum + p.totalShotCount);
    final completedShots =
        appState.projects.fold<int>(0, (sum, p) => sum + p.completedShotCount);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Scribbled Angel Studio',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Draw a little. Finish a shot. Make Veritas.',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              if (projectCount > 0) _StatsRow(totalShots: totalShots, completedShots: completedShots),
              const SizedBox(height: 28),
              BigButton(
                icon: Icons.movie_creation_outlined,
                label: 'Your Projects',
                subtitle: projectCount == 0
                    ? 'Start your first project'
                    : '$projectCount project${projectCount == 1 ? '' : 's'}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProjectsScreen()),
                ),
              ),
              const Spacer(),
              Center(
                child: Text(
                  'You can do five minutes. ✨',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int totalShots;
  final int completedShots;

  const _StatsRow({required this.totalShots, required this.completedShots});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(value: '$completedShots', label: 'Shots complete')),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(value: '$totalShots', label: 'Total shots')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
