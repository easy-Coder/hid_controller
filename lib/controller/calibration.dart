import 'dart:math' as math;

import 'models.dart';

class AxisCalibration {
  const AxisCalibration(this.minimum, this.center, this.maximum);
  final double minimum, center, maximum;
  bool get valid =>
      minimum.isFinite &&
      center.isFinite &&
      maximum.isFinite &&
      minimum < center &&
      center < maximum;
  double normalize(int raw) {
    if (!valid) return 0;
    final span = raw >= center ? maximum - center : center - minimum;
    return ((raw - center) / span).clamp(-1, 1).toDouble();
  }

  Map<String, double> toJson() => {
    'min': minimum,
    'center': center,
    'max': maximum,
  };
  factory AxisCalibration.fromJson(Map<String, dynamic> json) =>
      AxisCalibration(
        (json['min'] as num).toDouble(),
        (json['center'] as num).toDouble(),
        (json['max'] as num).toDouble(),
      );
}

class StickAxes {
  const StickAxes(this.name, this.x, this.y);
  final String name;
  final HidInput x, y;
}

List<StickAxes> findSticks(List<HidInput> inputs) {
  final axes = {
    for (final i in inputs.where((i) => i.isAxis && i.page == 1)) i.usage: i,
  };
  final result = <StickAxes>[];
  if (axes[0x30] != null && axes[0x31] != null) {
    result.add(StickAxes('LS · Left stick', axes[0x30]!, axes[0x31]!));
  }
  // Xbox-style layouts use Rx/Ry; Switch/DS4-style descriptors use Z/Rz.
  if (axes[0x33] != null && axes[0x34] != null) {
    result.add(StickAxes('RS · Right stick', axes[0x33]!, axes[0x34]!));
  } else if (axes[0x32] != null && axes[0x35] != null) {
    result.add(StickAxes('RS · Right stick', axes[0x32]!, axes[0x35]!));
  }
  return result;
}

({double x, double y}) applyDeadzone(double x, double y, double deadzone) {
  final radius = math.sqrt(x * x + y * y);
  final zone = deadzone.clamp(0, 0.5);
  if (radius <= zone || radius == 0) return (x: 0, y: 0);
  final scaled = ((radius - zone) / (1 - zone)).clamp(0, 1);
  return (x: x / radius * scaled, y: y / radius * scaled);
}

const controlNames = [
  'A',
  'B',
  'X',
  'Y',
  'LB',
  'RB',
  'LT',
  'RT',
  'LS click',
  'RS click',
  'View',
  'Menu',
  'Home',
  'Capture',
];
