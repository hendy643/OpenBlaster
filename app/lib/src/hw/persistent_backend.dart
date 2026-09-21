// SPDX-License-Identifier: Apache-2.0
import '../models.dart';
import 'backend.dart';
import 'store.dart';

/// Remembers every writable control's value and puts them back the next time the card is opened (the card
/// forgets its DSP settings when the machine restarts). Wraps another backend and changes nothing else about it.
///
/// The file is a snapshot of the last known values of all controls, `id=value` per line, rewritten whenever one
/// changes, whether we changed it or another program did.
class PersistentBackend extends Backend {
  PersistentBackend(this._inner, this._store) {
    _inner.onChange = (id, value) {
      _dirty = true;
      onChange?.call(id, value);
    };
    final text = _store.load();
    if (text == null) {
      _dirty = true; // first run: record what the card has now
    } else {
      _restore(text);
    }
  }

  final Backend _inner;
  final SettingsStore _store;
  bool _dirty = false;

  /// Every saved value that the card lacks, in the order the controls are listed. A value the card refuses
  /// (out of range, control gone, read-only) is skipped; the rest still apply.
  void _restore(String text) {
    final saved = parseSnapshot(text);
    for (final c in _inner.controls()) {
      final want = saved[c.id];
      if (want == null || !c.writable || _inner.get(c.id) == want) continue;
      _inner.set(c.id, want);
    }
    _dirty = false; // what we just applied is what the file says
  }

  @override
  List<Control> controls() => _inner.controls();

  @override
  int? get(String id) => _inner.get(id);

  @override
  SetResult set(String id, int value) => _inner.set(id, value);

  @override
  void poll() => _inner.poll();

  @override
  int get tickIntervalMs => _inner.tickIntervalMs;

  @override
  void tick(int nowMs) => _inner.tick(nowMs);

  @override
  void close() => _inner.close();

  @override
  void flush() {
    _inner.flush();
    if (!_dirty) return;
    if (_store.save(snapshot(_inner.controls())))
      _dirty = false; // else tried again at the next flush
  }
}

/// The text form of the current values of the writable controls that could be read.
String snapshot(List<Control> controls) {
  final b = StringBuffer('version=1\n');
  for (final c in controls) {
    if (c.writable && c.value != null) b.writeln('${c.id}=${c.value}');
  }
  return b.toString();
}

/// Forgiving: lines that make no sense are ignored.
Map<String, int> parseSnapshot(String text) {
  final out = <String, int>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^([a-z0-9_.]+)=(-?[0-9]+)$').firstMatch(line);
    final v = m == null ? null : int.tryParse(m[2]!);
    if (m != null && v != null && m[1] != 'version') out[m[1]!] = v;
  }
  return out;
}
