// SPDX-License-Identifier: Apache-2.0
import '../models.dart';
import 'alsa_io.dart';
import 'backend.dart';
import 'catalog.dart';

class _Entry {
  _Entry(this.control, this.alsaName, this.count, this.invert);
  final Control control;
  final String alsaName;
  final int count;
  final bool invert;
}

/// The stock driver's ALSA controls, under stable ids (see [alsaCatalog]).
class AlsaBackend extends Backend {
  AlsaBackend(this._io) {
    final raw = {for (final r in _io.list()) r.name: r};
    for (final m in alsaCatalog) {
      final r = raw[m.alsaName];
      if (r == null) continue;
      final ControlKind kind;
      var min = 0, max = 1, step = 1;
      var choices = const <String>[];
      switch (r.type) {
        case RawType.boolean:
          kind = ControlKind.toggle;
        case RawType.integer:
          kind = ControlKind.range;
          min = r.min;
          max = r.max;
          step = r.step < 1 ? 1 : r.step;
        case RawType.enumerated:
          if (r.items.isEmpty) continue;
          kind = ControlKind.choice;
          max = r.items.length - 1;
          choices = r.items;
        case RawType.other:
          continue;
      }
      _entries[m.id] = _Entry(
        Control(
          id: m.id,
          group: m.group,
          label: m.label,
          kind: kind,
          min: min,
          max: max,
          step: step,
          choices: choices,
          writable: r.writable,
        ),
        m.alsaName,
        r.count < 1 ? 1 : r.count,
        m.invert && kind == ControlKind.toggle,
      );
    }
    for (final e in _entries.entries) {
      final v = _read(e.value);
      if (v != null) _last[e.key] = v;
    }
  }

  final AlsaIo _io;
  final _entries = <String, _Entry>{}; // by id
  final _last = <String, int>{};

  @override
  List<Control> controls() => [
    for (final m in alsaCatalog)
      if (_entries[m.id] case final e?)
        e.control.withValue(_last[m.id] ?? _read(e)),
  ];

  int? _read(_Entry e) {
    final values = _io.read(e.alsaName);
    if (values == null || values.isEmpty) return null;
    return e.invert ? 1 - values.first : values.first;
  }

  @override
  int? get(String id) {
    final e = _entries[id];
    return e == null ? null : _read(e);
  }

  @override
  SetResult set(String id, int value) {
    final e = _entries[id];
    if (e == null) return SetResult.unknownControl;
    if (!e.control.writable) return SetResult.readOnly;
    if (value < e.control.min || value > e.control.max)
      return SetResult.outOfRange;
    // A stereo control moves both channels together; per-channel balance is not a user setting.
    final raw = e.invert ? 1 - value : value;
    if (!_io.write(e.alsaName, List.filled(e.count, raw)))
      return SetResult.failed;
    if (_last[id] != value) {
      _last[id] = value;
      onChange?.call(id, value);
    }
    return SetResult.ok;
  }

  @override
  void poll() {
    for (final e in _entries.entries) {
      final v = _read(e.value);
      if (v == null || _last[e.key] == v) continue;
      _last[e.key] = v;
      onChange?.call(e.key, v);
    }
  }
}
