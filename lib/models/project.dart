import 'episode.dart';
import 'shot.dart';

// Re-exported so screens only need one import for the whole model graph.
export 'episode.dart';
export 'shot.dart';
export 'frame.dart';
export 'stroke.dart';

class Project {
  String id;
  String title;
  String description;
  DateTime createdAt;
  List<Episode> episodes;

  Project({
    required this.id,
    required this.title,
    this.description = '',
    DateTime? createdAt,
    List<Episode>? episodes,
  })  : createdAt = createdAt ?? DateTime.now(),
        episodes = episodes ?? [];

  int get totalShotCount => episodes.fold(0, (sum, e) => sum + e.shots.length);

  int get completedShotCount =>
      episodes.fold(0, (sum, e) => sum + e.completedShotCount);

  double get totalRuntimeSeconds => episodes.fold(
        0.0,
        (sum, e) => sum + e.shots.fold(0.0, (s2, shot) => s2 + shot.durationSeconds),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };

  static Project fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        episodes: (json['episodes'] as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
