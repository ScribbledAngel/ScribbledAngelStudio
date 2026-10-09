/// A camera framing: pan position (as a fraction of canvas width/height, so
/// it scales correctly at any export resolution), zoom multiplier, and
/// rotation in radians. The artwork itself never moves - only how it's
/// framed for viewing/export does.
class CameraState {
  double x;
  double y;
  double zoom;
  double rotation;

  CameraState({this.x = 0, this.y = 0, this.zoom = 1.0, this.rotation = 0});

  CameraState copy() => CameraState(x: x, y: y, zoom: zoom, rotation: rotation);

  static CameraState lerp(CameraState a, CameraState b, double t) => CameraState(
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
        zoom: a.zoom + (b.zoom - a.zoom) * t,
        rotation: a.rotation + (b.rotation - a.rotation) * t,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'zoom': zoom, 'rotation': rotation};

  static CameraState fromJson(Map<String, dynamic> json) => CameraState(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );
}
