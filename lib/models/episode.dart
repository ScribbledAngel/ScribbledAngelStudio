import 'shot.dart';

/// An ordered list of shots, e.g. "Episode 1".
class Episode {
  String id;
  String title;
  List<Shot> shots;

  Episode({required this.id, required this.title, List<Shot>? shots}) : shots = shots ?? [];

  int get completedShotCount => shots.where((s) => s.status == ShotStatus.complete).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'shots': shots.map((s) => s.toJson()).toList(),
      };

  static Episode fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String,
        title: json['title'] as String,
        shots: (json['shots'] as List)
            .map((s) => Shot.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
