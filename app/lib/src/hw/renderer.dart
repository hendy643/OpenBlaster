// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'color.dart';
import 'settings.dart';

typedef Frame = List<Rgb>;

Frame _black() => List.filled(kBuiltInLeds, const Rgb(0, 0, 0));

/// The colour slots as a loop: 0 is slot 1, and past the last slot it blends back into the first.
Rgb _paletteAt(Settings s, double p) {
  p = frac(p) * kColorSlots;
  final i = p.floor() % kColorSlots;
  return mix(
    s.colors[i],
    s.colors[(i + 1) % kColorSlots],
    p - p.floorToDouble(),
  );
}

/// What the five LEDs show at [nowMs]. Pure: the same settings and time always give the same frame.
Frame render(Settings s, int nowMs) {
  if (!s.enabled || s.brightness <= 0) return _black();
  final period = 60000.0 / s.speed;
  final phase = frac(nowMs / period);
  final bounce =
      s.direction == LightDirection.leftToRightBounce ||
      s.direction == LightDirection.rightToLeftBounce;
  final ltr =
      s.direction == LightDirection.leftToRight ||
      s.direction == LightDirection.leftToRightBounce;
  // How far the pattern has travelled, in strip lengths: a loop, or there and back again.
  final travelled = bounce ? 1.0 - (2.0 * phase - 1.0).abs() : phase;
  final shift = ltr ? travelled : -travelled;
  return [
    for (var i = 0; i < kBuiltInLeds; i++)
      () {
        final x = i / kBuiltInLeds; // where this LED sits along the strip
        final c = switch (s.pattern) {
          LightPattern.solid => s.colors[i],
          LightPattern.pulsate => scale(
            s.colors[i],
            0.08 + 0.92 * (1.0 - math.cos(tau * phase)) / 2.0,
          ),
          LightPattern.colourCycle => _paletteAt(s, phase),
          LightPattern.wave => _paletteAt(s, x - shift),
          LightPattern.aurora => scale(
            _paletteAt(s, 0.6 * x - 0.5 * shift),
            0.65 + 0.35 * math.sin(tau * (1.3 * x + 2.0 * phase)),
          ),
          LightPattern.mood => _paletteAt(s, phase + 0.13 * i),
        };
        return scale(c, s.brightness / 100.0);
      }(),
  ];
}
