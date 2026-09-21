// SPDX-License-Identifier: Apache-2.0
import '../models.dart';
import 'backend.dart';
import 'color.dart';
import 'led_port.dart';
import 'renderer.dart';
import 'settings.dart';
import 'store.dart';

const _group = 'Lighting';

Control _control(
  String id,
  String label,
  ControlKind kind,
  int min,
  int max, {
  List<String> choices = const [],
}) => Control(
  id: id,
  group: _group,
  label: label,
  kind: kind,
  min: min,
  max: max,
  choices: choices,
);

/// "lighting.color3" -> 2, or -1.
int _colorSlot(String id) {
  final m = RegExp(r'^lighting\.color([1-5])$').firstMatch(id);
  return m == null ? -1 : int.parse(m[1]!) - 1;
}

/// The built-in LEDs as controls. The animation runs here, on [tick]; the settings are kept in a file.
class LightingBackend extends Backend {
  LightingBackend(this._sink, this._store) {
    final text = _store.load();
    if (text != null) _settings = Settings.parse(text);
  }

  /// A frame is sent at least this often even if nothing changed: the card may have forgotten it
  /// (a suspend and resume, another program).
  static const refreshMs = 2000;

  final LedSink _sink;
  final SettingsStore _store;
  Settings _settings = const Settings();
  bool _dirty = false;
  Frame? _lastFrame;
  int _lastSentMs = 0;

  Settings get settings => _settings;

  @override
  List<Control> controls() => [
    _control('lighting.enable', 'Lighting', ControlKind.toggle, 0, 1),
    _control(
      'lighting.pattern',
      'Pattern',
      ControlKind.choice,
      0,
      LightPattern.values.length - 1,
      choices: [for (final p in LightPattern.values) p.label],
    ),
    _control(
      'lighting.direction',
      'Direction',
      ControlKind.choice,
      0,
      LightDirection.values.length - 1,
      choices: [for (final d in LightDirection.values) d.label],
    ),
    _control(
      'lighting.speed',
      'Speed (cycles per minute)',
      ControlKind.range,
      kMinSpeed,
      kMaxSpeed,
    ),
    _control('lighting.brightness', 'Brightness', ControlKind.range, 0, 100),
    for (var i = 0; i < kColorSlots; i++)
      _control(
        'lighting.color${i + 1}',
        'Colour ${i + 1}',
        ControlKind.color,
        0,
        0xffffff,
      ),
  ].map((c) => c.withValue(get(c.id))).toList();

  @override
  int? get(String id) {
    switch (id) {
      case 'lighting.enable':
        return _settings.enabled ? 1 : 0;
      case 'lighting.pattern':
        return _settings.pattern.index;
      case 'lighting.direction':
        return _settings.direction.index;
      case 'lighting.speed':
        return _settings.speed;
      case 'lighting.brightness':
        return _settings.brightness;
    }
    final slot = _colorSlot(id);
    return slot >= 0 ? _settings.colors[slot].toInt() : null;
  }

  @override
  SetResult set(String id, int value) {
    bool range(int lo, int hi) => value >= lo && value <= hi;
    final Settings next;
    switch (id) {
      case 'lighting.enable':
        if (!range(0, 1)) return SetResult.outOfRange;
        next = _settings.copyWith(enabled: value == 1);
      case 'lighting.pattern':
        if (!range(0, LightPattern.values.length - 1))
          return SetResult.outOfRange;
        next = _settings.copyWith(pattern: LightPattern.values[value]);
      case 'lighting.direction':
        if (!range(0, LightDirection.values.length - 1))
          return SetResult.outOfRange;
        next = _settings.copyWith(direction: LightDirection.values[value]);
      case 'lighting.speed':
        if (!range(kMinSpeed, kMaxSpeed)) return SetResult.outOfRange;
        next = _settings.copyWith(speed: value);
      case 'lighting.brightness':
        if (!range(0, 100)) return SetResult.outOfRange;
        next = _settings.copyWith(brightness: value);
      default:
        final slot = _colorSlot(id);
        if (slot < 0) return SetResult.unknownControl;
        if (!range(0, 0xffffff)) return SetResult.outOfRange;
        next = _settings.copyWith(
          colors: List.of(_settings.colors)..[slot] = Rgb.fromInt(value),
        );
    }
    if (next == _settings)
      return SetResult.ok; // nothing to save, show or announce
    _settings = next;
    _dirty = true;
    _lastFrame = null; // show the change on the next tick
    onChange?.call(id, value);
    return SetResult.ok;
  }

  @override
  int get tickIntervalMs {
    final animated =
        _settings.enabled &&
        _settings.pattern != LightPattern.solid &&
        _settings.brightness > 0;
    return animated ? 33 : 250; // about 30 frames a second while it moves
  }

  @override
  void tick(int nowMs) {
    final frame = render(_settings, nowMs);
    final last = _lastFrame;
    final stale = last == null || nowMs - _lastSentMs >= refreshMs;
    if (!stale && _same(frame, last)) return;
    if (_sink.show(frame)) {
      _lastFrame = frame;
      _lastSentMs = nowMs;
    } // else try again on the next tick
  }

  static bool _same(Frame a, Frame b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void flush() {
    if (_dirty && _store.save(_settings.serialize())) _dirty = false;
  }
}
