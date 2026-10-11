/// Metadata for a layer created from an imported video's snippet - kept so
/// the reference footage and audio stay associated with the layer across
/// save/reopen, and so the UI can show what the layer was built from.
class VideoReferenceSource {
  /// Filename of the imported source video, copied into the app's private
  /// reference-video storage (see ReferenceAssetService).
  String sourceVideoFileName;

  /// Filename of the extracted audio track, if extraction succeeded.
  String? audioFileName;

  double snippetStart;
  double snippetEnd;
  double extractionFps;

  VideoReferenceSource({
    required this.sourceVideoFileName,
    this.audioFileName,
    required this.snippetStart,
    required this.snippetEnd,
    required this.extractionFps,
  });

  Map<String, dynamic> toJson() => {
        'sourceVideoFileName': sourceVideoFileName,
        'audioFileName': audioFileName,
        'snippetStart': snippetStart,
        'snippetEnd': snippetEnd,
        'extractionFps': extractionFps,
      };

  static VideoReferenceSource fromJson(Map<String, dynamic> json) => VideoReferenceSource(
        sourceVideoFileName: json['sourceVideoFileName'] as String,
        audioFileName: json['audioFileName'] as String?,
        snippetStart: (json['snippetStart'] as num).toDouble(),
        snippetEnd: (json['snippetEnd'] as num).toDouble(),
        extractionFps: (json['extractionFps'] as num).toDouble(),
      );
}
