// SPDX-License-Identifier: Apache-2.0
import '../models.dart';

enum SetResult {
  ok,
  unknownControl,
  readOnly,
  outOfRange,
  failed;

  String get message => switch (this) {
    ok => 'ok',
    unknownControl => 'unknown control',
    readOnly => 'control is read-only',
    outOfRange => 'value out of range',
    failed => 'the hardware refused the change',
  };
}

/// A source of controls for one device. Backends are ordered by preference (ALSA controls first) and
/// a [CompositeBackend] asks them in turn.
abstract class Backend {
  List<Control> controls();
  int? get(String id);
  SetResult set(String id, int value);

  /// Called with each control that changed, by [set] or behind our back (see [poll]).
  void Function(String id, int value)? onChange;

  /// Look for changes made behind our back (another mixer); reports them through [onChange].
  void poll() {}

  /// Backends that animate something are called back on a timer: how long from now until [tick]
  /// should next run, in milliseconds; 0 means never.
  int get tickIntervalMs => 0;
  void tick(int nowMs) {}

  /// Write anything worth keeping to disk (called shortly after a change, and on exit).
  void flush() {}

  /// The card is being closed: stop anything running for it.
  void close() {}
}

/// Several backends as one. The first one that offers a control owns it.
class CompositeBackend extends Backend {
  CompositeBackend(this._parts) {
    for (final b in _parts) {
      b.onChange = (id, v) => onChange?.call(id, v);
      for (final c in b.controls()) {
        _owner.putIfAbsent(c.id, () => b);
      }
    }
  }

  final List<Backend> _parts;
  final _owner = <String, Backend>{};

  @override
  List<Control> controls() => [
    for (final b in _parts)
      for (final c in b.controls())
        if (identical(_owner[c.id], b)) c,
  ];

  @override
  int? get(String id) => _owner[id]?.get(id);

  @override
  SetResult set(String id, int value) =>
      _owner[id]?.set(id, value) ?? SetResult.unknownControl;

  @override
  void poll() {
    for (final b in _parts) {
      b.poll();
    }
  }

  @override
  int get tickIntervalMs {
    var best = 0;
    for (final b in _parts) {
      final ms = b.tickIntervalMs;
      if (ms > 0 && (best == 0 || ms < best)) best = ms;
    }
    return best;
  }

  @override
  void tick(int nowMs) {
    for (final b in _parts) {
      b.tick(nowMs);
    }
  }

  @override
  void flush() {
    for (final b in _parts) {
      b.flush();
    }
  }

  @override
  void close() {
    for (final b in _parts) {
      b.close();
    }
  }
}
