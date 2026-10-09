/// A single audio clip attached to a shot (recorded or imported).
///
/// [fileName] is just the file's name within the app's private audio
/// folder (see AudioService) - never a full path, since that can change
/// between app installs/devices.
class AudioClip {
  String id;
  String fileName;
  double trimStart;
  double trimEnd;
  double volume;
  double sourceDurationSeconds;

  AudioClip({
    required this.id,
    required this.fileName,
    this.trimStart = 0,
    double? trimEnd,
    this.volume = 1.0,
    this.sourceDurationSeconds = 0,
  }) : trimEnd = trimEnd ?? sourceDurationSeconds;

  double get effectiveDuration => (trimEnd - trimStart).clamp(0, sourceDurationSeconds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'trimStart': trimStart,
        'trimEnd': trimEnd,
        'volume': volume,
        'sourceDurationSeconds': sourceDurationSeconds,
      };

  static AudioClip fromJson(Map<String, dynamic> json) => AudioClip(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        trimStart: (json['trimStart'] as num?)?.toDouble() ?? 0,
        trimEnd: (json['trimEnd'] as num?)?.toDouble(),
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        sourceDurationSeconds: (json['sourceDurationSeconds'] as num?)?.toDouble() ?? 0,
      );
}
