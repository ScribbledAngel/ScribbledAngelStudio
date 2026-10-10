/// A simple pre-flight checklist for getting a shot ready to publish.
/// [video] is set automatically once an export succeeds; the rest are
/// manual reminders for things prepared outside the app.
class ExportChecklist {
  bool video;
  bool audio;
  bool thumbnail;
  bool title;
  bool description;
  bool subtitles;

  ExportChecklist({
    this.video = false,
    this.audio = false,
    this.thumbnail = false,
    this.title = false,
    this.description = false,
    this.subtitles = false,
  });

  Map<String, dynamic> toJson() => {
        'video': video,
        'audio': audio,
        'thumbnail': thumbnail,
        'title': title,
        'description': description,
        'subtitles': subtitles,
      };

  static ExportChecklist fromJson(Map<String, dynamic> json) => ExportChecklist(
        video: json['video'] as bool? ?? false,
        audio: json['audio'] as bool? ?? false,
        thumbnail: json['thumbnail'] as bool? ?? false,
        title: json['title'] as bool? ?? false,
        description: json['description'] as bool? ?? false,
        subtitles: json['subtitles'] as bool? ?? false,
      );
}
