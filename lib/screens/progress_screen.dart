import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../models/project.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final projects = appState.projects;
    final progress = appState.progress;

    final allShots = [
      for (final p in projects)
        for (final e in p.episodes) ...e.shots,
    ];
    final totalFrames = allShots.fold<int>(0, (sum, s) => sum + s.frameCount);
    final totalShots = allShots.length;
    final completedShots = allShots.where((s) => s.status == ShotStatus.complete).length;
    final totalRuntime = allShots.fold<double>(0, (sum, s) => sum + s.durationSeconds);
    final episodesCompleted = projects
        .expand((p) => p.episodes)
        .where((e) => e.shots.isNotEmpty && e.shots.every((s) => s.status == ShotStatus.complete))
        .length;

    final unlocked = appState.unlockedAchievements;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _StatCard(value: '${progress.totalXp}', label: 'XP', icon: Icons.bolt_rounded),
              _StatCard(
                value: '${progress.currentStreak}',
                label: progress.currentStreak == 1 ? 'Day streak' : 'Day streak',
                icon: Icons.local_fire_department_rounded,
              ),
              _StatCard(value: '${progress.longestStreak}', label: 'Longest streak', icon: Icons.emoji_events_outlined),
              _StatCard(value: '$completedShots / $totalShots', label: 'Shots complete', icon: Icons.check_circle_outline_rounded),
              _StatCard(value: '$totalFrames', label: 'Total frames', icon: Icons.burst_mode_outlined),
              _StatCard(
                value: '${totalRuntime.toStringAsFixed(1)}s',
                label: 'Total runtime',
                icon: Icons.schedule_rounded,
              ),
              _StatCard(value: '$episodesCompleted', label: 'Episodes complete', icon: Icons.theaters_outlined),
            ],
          ),
          const SizedBox(height: 28),
          const Text('Today\'s goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Pick any one. Small counts.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          _DailyGoalTile(
            label: 'TINY',
            description: 'Draw 1 frame',
            done: progress.hasDrawnToday,
          ),
          _DailyGoalTile(
            label: 'SMALL',
            description: 'Animate about 1 second',
            done: progress.framesAddedToday >= 8,
          ),
          _DailyGoalTile(
            label: 'MEDIUM',
            description: 'Complete one shot',
            done: progress.shotsCompletedToday >= 1,
          ),
          _DailyGoalTile(
            label: 'BIG',
            description: 'Complete and export a shot',
            done: progress.shotsExportedToday >= 1,
          ),
          const SizedBox(height: 28),
          const Text('Achievements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: kAchievements.length,
            itemBuilder: (context, index) {
              final achievement = kAchievements[index];
              final isUnlocked = unlocked.contains(achievement.id);
              return _AchievementCard(achievement: achievement, isUnlocked: isUnlocked);
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatCard({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _DailyGoalTile extends StatelessWidget {
  final String label;
  final String description;
  final bool done;

  const _DailyGoalTile({required this.label, required this.description, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: done ? Border.all(color: AppColors.success, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: done ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                Text(description, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final bool isUnlocked;

  const _AchievementCard({required this.achievement, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    final dimmed = !isUnlocked;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            achievement.icon,
            color: dimmed ? AppColors.textSecondary.withOpacity(0.4) : AppColors.accent,
            size: 26,
          ),
          const SizedBox(height: 6),
          Text(
            achievement.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: dimmed ? AppColors.textSecondary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              achievement.comingSoon ? '${achievement.description} (coming soon)' : achievement.description,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
