import 'package:flutter/material.dart';

import 'project.dart';

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  /// True for achievements that can't be unlocked yet in this build (e.g.
  /// they depend on a feature that isn't built yet) - shown, but honestly
  /// marked as not-yet-available rather than faked.
  final bool comingSoon;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.comingSoon = false,
  });
}

const List<Achievement> kAchievements = [
  Achievement(
    id: 'first_shot',
    title: 'First Shot',
    description: 'Create your first shot',
    icon: Icons.movie_creation_outlined,
  ),
  Achievement(
    id: 'first_frame',
    title: 'First Frame',
    description: 'Draw your first frame',
    icon: Icons.brush_rounded,
  ),
  Achievement(
    id: 'first_10_seconds',
    title: 'First 10 Seconds',
    description: 'Animate 10 seconds in a single shot',
    icon: Icons.timer_outlined,
  ),
  Achievement(
    id: 'first_minute',
    title: 'First Minute',
    description: "Animate a minute's worth across your projects",
    icon: Icons.timelapse_rounded,
  ),
  Achievement(
    id: 'first_voice',
    title: 'First Voice Recording',
    description: 'Record or import audio for a shot',
    icon: Icons.mic_rounded,
  ),
  Achievement(
    id: 'first_completed_scene',
    title: 'First Completed Scene',
    description: 'Mark a shot complete',
    icon: Icons.check_circle_outline_rounded,
  ),
  Achievement(
    id: 'ugly_first_draft',
    title: 'Ugly First Draft',
    description: 'Complete a shot in 3 frames or fewer - done beats perfect',
    icon: Icons.emoji_emotions_outlined,
  ),
  Achievement(
    id: 'episode_complete',
    title: 'Episode Complete',
    description: 'Finish every shot in an episode',
    icon: Icons.theaters_rounded,
  ),
  Achievement(
    id: 'first_export',
    title: 'First Export',
    description: 'Export a shot to video',
    icon: Icons.file_download_outlined,
  ),
  Achievement(
    id: 'first_youtube',
    title: 'First YouTube Video',
    description: 'Coming with the YouTube upload workflow',
    icon: Icons.ondemand_video_rounded,
    comingSoon: true,
  ),
];

/// Pure function: which achievements are unlocked, computed fresh from the
/// actual project data (plus [everExported], the one thing that isn't
/// derivable from project data since exporting doesn't change it).
Set<String> computeUnlockedAchievements(List<Project> projects, bool everExported) {
  final unlocked = <String>{};

  final allShots = [for (final p in projects) for (final e in p.episodes) ...e.shots];
  final totalShotCount = allShots.length;
  final hasAnyFrame = allShots.any((s) => s.hasAnyStrokes);
  final longestShotSeconds = allShots.fold<double>(0, (m, s) => s.durationSeconds > m ? s.durationSeconds : m);
  final totalSeconds = allShots.fold<double>(0, (sum, s) => sum + s.durationSeconds);
  final hasVoice = allShots.any((s) => s.audioClip != null);
  final completedShots = allShots.where((s) => s.status == ShotStatus.complete).toList();
  final hasUglyDraft = completedShots.any((s) => s.frameCount <= 3);
  final hasCompleteEpisode =
      projects.any((p) => p.episodes.any((e) => e.shots.isNotEmpty && e.shots.every((s) => s.status == ShotStatus.complete)));

  if (totalShotCount >= 1) unlocked.add('first_shot');
  if (hasAnyFrame) unlocked.add('first_frame');
  if (longestShotSeconds >= 10) unlocked.add('first_10_seconds');
  if (totalSeconds >= 60) unlocked.add('first_minute');
  if (hasVoice) unlocked.add('first_voice');
  if (completedShots.isNotEmpty) unlocked.add('first_completed_scene');
  if (hasUglyDraft) unlocked.add('ugly_first_draft');
  if (hasCompleteEpisode) unlocked.add('episode_complete');
  if (everExported) unlocked.add('first_export');

  return unlocked;
}
