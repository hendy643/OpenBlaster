// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import '../models.dart';
import 'backend.dart';
import 'store.dart';
import 'virtual_surround.dart';

/// Runs one piece of work after another. The card's Surround and the virtual surround both change the card's
/// profile and the default output, so what one undoes must be done before the other starts.
class Serial {
  Future<void> _chain = Future.value();

  void run(Future<void> Function() work) {
    _chain = _chain.then((_) => work()).catchError((Object _) {});
  }

  /// Completes when everything asked for so far has been done (for tests).
  Future<void> get idle => _chain;
}

const _stereoProfile = 'output:analog-stereo+input:analog-stereo';

/// The card's own SBX Surround, as the Effects page's Surround switch. Turning it on gives the card what it needs
/// to place 5.1 for the headphones itself: its PipeWire profile is switched to 5.1 (in the driver's channel order,
/// see install/openblaster-ae5.conf), Output Select is put back (the profile change flips it to Speakers) and the
/// 5.1 sink becomes the default output, so an app that plays 5.1 sends all six channels to the card. Turning it off
/// gives the profile, Output Select and default output back.
///
/// Everything but the Surround switch is [inner]'s. It is exclusive with the virtual surround, which would process
/// the sound a second time: [onEnabling] is called when this one is turned on.
class SurroundBackend extends Backend {
  SurroundBackend({
    required this.inner,
    required this.host,
    required this.pci,
    required SettingsStore store,
    Serial? serial,
  }) : _store = store,
       serial = serial ?? Serial() {
    inner.onChange = (id, v) => onChange?.call(id, v);
    _load(store.load());
    // On at start: make sure the card is in 5.1 (the setting is restored by [inner]), or undo what a crash left
    if (inner.get(id) == 1 || _previousProfile != null) {
      this.serial.run(inner.get(id) == 1 ? _begin : _end);
    }
  }

  static const id = 'fx.surround';

  final Backend inner;
  final PipeWireHost host;
  final String pci;
  final SettingsStore _store;
  final Serial serial;

  /// Called when the card's Surround is turned on, before anything is done.
  void Function()? onEnabling;

  // What the card had before; null when the 5.1 setup is not in effect. Kept on disk.
  String? _previousProfile, _previousDefault;
  int? _previousOutput;
  bool _dirty = false;

  void _markDirty() {
    _dirty = true;
    onDirty?.call();
  }

  void _load(String? text) {
    for (final line in (text ?? '').split('\n')) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq), value = line.substring(eq + 1);
      switch (key) {
        case 'previous_profile':
          _previousProfile = value.isEmpty ? null : value;
        case 'previous_default':
          _previousDefault = value.isEmpty ? null : value;
        case 'previous_output':
          _previousOutput = int.tryParse(value);
      }
    }
  }

  String _serialize() =>
      'version=1\nprevious_profile=${_previousProfile ?? ''}\n'
      'previous_default=${_previousDefault ?? ''}\nprevious_output=${_previousOutput ?? ''}\n';

  @override
  List<Control> controls() => inner.controls();

  @override
  int? get(String id) => inner.get(id);

  @override
  SetResult set(String controlId, int value) {
    if (controlId != id) return inner.set(controlId, value);
    final was = inner.get(id);
    final r = inner.set(id, value);
    if (r != SetResult.ok || was == value) return r;
    if (value == 1) {
      onEnabling?.call();
      serial.run(_begin);
    } else {
      serial.run(_end);
    }
    return r;
  }

  Future<void> _begin() async {
    int? volume; // of the output being replaced: its sinks are gone once the profile has changed
    if (_previousProfile == null) {
      // the default output is the card's own stereo sink, and PipeWire moves it when the profile changes: read now
      final now = host.cardProfile(pci), current = host.defaultSink();
      _previousProfile = now == surround51Profile ? _stereoProfile : now;
      _previousDefault = current;
      _previousOutput = inner.get('output.select');
      volume = current == null ? null : host.sinkVolume(current);
      _markDirty();
    }
    final ok =
        _previousProfile != null &&
        (host.cardProfile(pci) == surround51Profile ||
            await host.setCardProfile(pci, surround51Profile));
    final sink = ok ? host.surroundSinkFor(pci) : null;
    final output = _previousOutput;
    if (output != null) inner.set('output.select', output);
    if (sink == null) {
      inner.set(id, 0); // say so: the window puts the switch back
      await _end();
      return;
    }
    // a new sink starts at 100%: give it the volume the output had, or the switch would be a lot louder
    if (volume != null) host.setSinkVolume(sink, volume);
    host.setDefaultSink(sink);
  }

  Future<void> _end() async {
    final profile = _previousProfile;
    if (profile == null) return;
    if (host.cardProfile(pci) != profile)
      await host.setCardProfile(pci, profile);
    final output = _previousOutput, back = _previousDefault;
    if (output != null) inner.set('output.select', output);
    if (back != null) host.setDefaultSink(back);
    _previousProfile = _previousDefault = _previousOutput = null;
    _markDirty();
  }

  @override
  void poll() => inner.poll();

  @override
  int get tickIntervalMs => inner.tickIntervalMs;

  @override
  void tick(int nowMs) => inner.tick(nowMs);

  @override
  void flush() {
    inner.flush();
    if (_dirty && _store.save(_serialize())) _dirty = false;
  }

  @override
  void close() {
    // nothing runs for this: the card stays set up the way it is
    inner.close();
    flush();
  }
}
