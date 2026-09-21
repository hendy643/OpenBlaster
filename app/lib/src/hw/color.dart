// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

/// An LED colour, 8 bits a channel.
class Rgb {
  const Rgb(this.r, this.g, this.b);
  factory Rgb.fromInt(int v) =>
      Rgb((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);

  final int r, g, b;

  int toInt() => (r << 16) | (g << 8) | b;

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => toInt();

  @override
  String toString() => 'Rgb($r, $g, $b)';
}

int _byte(double v) => v.clamp(0.0, 255.0).round();

/// From [a] (t = 0) to [b] (t = 1).
Rgb mix(Rgb a, Rgb b, double t) {
  t = t.clamp(0.0, 1.0);
  return Rgb(
    _byte(a.r + (b.r - a.r) * t),
    _byte(a.g + (b.g - a.g) * t),
    _byte(a.b + (b.b - a.b) * t),
  );
}

/// Dimmed to [f] (0..1) of its brightness.
Rgb scale(Rgb c, double f) {
  f = f.clamp(0.0, 1.0);
  return Rgb(_byte(c.r * f), _byte(c.g * f), _byte(c.b * f));
}

/// Hue in degrees (any value, it wraps), saturation and value 0..1.
Rgb fromHsv(double hue, double saturation, double value) {
  hue = ((hue % 360.0) + 360.0) % 360.0;
  saturation = saturation.clamp(0.0, 1.0);
  value = value.clamp(0.0, 1.0);
  final c = value * saturation;
  final x = c * (1 - ((hue / 60.0) % 2.0 - 1).abs());
  final m = value - c;
  final (r, g, b) = switch (hue ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return Rgb(_byte((r + m) * 255), _byte((g + m) * 255), _byte((b + m) * 255));
}

/// Fractional part, always 0 <= x < 1.
double frac(double x) => x - x.floorToDouble();

const double tau = 2 * math.pi;
