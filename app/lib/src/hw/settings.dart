// SPDX-License-Identifier: Apache-2.0
import 'color.dart';

const int kBuiltInLeds = 5;
const int kColorSlots = 5; // Windows offers up to five colour groups
const int kMinSpeed = 1; // cycles per minute
const int kMaxSpeed = 120;

enum LightPattern {
  solid('static', 'Static'),
  pulsate('pulsate', 'Pulsate'),
  colourCycle('colour-cycle', 'Colour cycle'),
  wave('wave', 'Wave'),
  aurora('aurora', 'Aurora'),
  mood('mood', 'Mood');

  const LightPattern(this.wire, this.label);
  final String wire, label;
}

enum LightDirection {
  leftToRight('left-to-right', 'Left to right'),
  rightToLeft('right-to-left', 'Right to left'),
  leftToRightBounce('left-to-right-bounce', 'Left to right (bounce)'),
  rightToLeftBounce('right-to-left-bounce', 'Right to left (bounce)');

  const LightDirection(this.wire, this.label);
  final String wire, label;
}

int? _num(String v, {int radix = 10}) =>
    RegExp(radix == 16 ? r'^[0-9a-fA-F]+$' : r'^[0-9]+$').hasMatch(v)
    ? int.parse(v, radix: radix)
    : null;

/// Everything the lighting page sets. Kept in a small `key=value` file.
class Settings {
  const Settings({
    this.enabled = true,
    this.pattern = LightPattern.solid,
    this.direction = LightDirection.leftToRight,
    this.speed = 20,
    this.brightness = 60,
    this.colors = _defaultColors,
  });

  static const _blue = Rgb(0x1e, 0x88, 0xe5);
  static const _defaultColors = [_blue, _blue, _blue, _blue, _blue];

  final bool enabled;
  final LightPattern pattern;
  final LightDirection direction;
  final int speed; // cycles per minute
  final int brightness; // percent
  final List<Rgb> colors;

  Settings copyWith({
    bool? enabled,
    LightPattern? pattern,
    LightDirection? direction,
    int? speed,
    int? brightness,
    List<Rgb>? colors,
  }) => Settings(
    enabled: enabled ?? this.enabled,
    pattern: pattern ?? this.pattern,
    direction: direction ?? this.direction,
    speed: speed ?? this.speed,
    brightness: brightness ?? this.brightness,
    colors: colors ?? this.colors,
  );

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.enabled == enabled &&
      other.pattern == pattern &&
      other.direction == direction &&
      other.speed == speed &&
      other.brightness == brightness &&
      _sameColors(other.colors, colors);

  static bool _sameColors(List<Rgb> a, List<Rgb> b) {
    for (var i = 0; i < kColorSlots; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    pattern,
    direction,
    speed,
    brightness,
    Object.hashAll(colors),
  );

  String serialize() {
    final b = StringBuffer('version=1\n')
      ..writeln('enabled=${enabled ? 1 : 0}')
      ..writeln('pattern=${pattern.wire}')
      ..writeln('direction=${direction.wire}')
      ..writeln('speed=$speed')
      ..writeln('brightness=$brightness');
    for (var i = 0; i < kColorSlots; i++) {
      b.writeln(
        'color${i + 1}=${colors[i].toInt().toRadixString(16).padLeft(6, '0')}',
      );
    }
    return b.toString();
  }

  /// Forgiving: a line that makes no sense keeps that setting's default and the rest still apply.
  factory Settings.parse(String text) {
    var s = const Settings();
    final colors = List.of(s.colors);
    for (final line in text.split('\n')) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq), value = line.substring(eq + 1);
      switch (key) {
        case 'enabled':
          if (value == '0' || value == '1')
            s = s.copyWith(enabled: value == '1');
        case 'pattern':
          for (final p in LightPattern.values) {
            if (p.wire == value) s = s.copyWith(pattern: p);
          }
        case 'direction':
          for (final d in LightDirection.values) {
            if (d.wire == value) s = s.copyWith(direction: d);
          }
        case 'speed':
          final v = _num(value);
          if (v != null && v >= kMinSpeed && v <= kMaxSpeed)
            s = s.copyWith(speed: v);
        case 'brightness':
          final v = _num(value);
          if (v != null && v >= 0 && v <= 100) s = s.copyWith(brightness: v);
        default:
          final m = RegExp(r'^color([1-5])$').firstMatch(key);
          if (m == null || value.isEmpty || value.length > 6) break;
          final v = _num(value, radix: 16);
          if (v != null && v >= 0)
            colors[int.parse(m[1]!) - 1] = Rgb.fromInt(v);
      }
    }
    return s.copyWith(colors: colors);
  }
}
