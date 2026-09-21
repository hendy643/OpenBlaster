// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import '../models.dart';
import 'backend.dart';
import 'store.dart';
import 'virtual_surround.dart';

/// Virtual surround for headphones: while it is on, a PipeWire virtual 7.1 sink takes the surround audio from apps,
/// places each channel around the listener with an HRIR (a SOFA file or a HeSuVi WAV: CMSS-3D, SBX, Dolby Atmos,
/// DTS Headphone:X ...) and plays the stereo result on the card. It becomes
/// the default output; turning it off gives the previous default back. The choice is remembered and applied when
/// the app starts.
class VirtualSurroundBackend extends Backend {
  VirtualSurroundBackend({
    required this.host,
    required SettingsStore store,
    required List<Hrir> profiles,
    required this.targetSink,
  }) : _store = store,
       // ignore: prefer_initializing_formals
       _profiles = profiles {
    _load(store.load());
    if (_enabled || _previousDefault != null)
      _schedule(); // start it again, or undo what a crash left behind
  }

  static const _group = 'Virtual surround';

  final PipeWireHost host;
  final String? Function() targetSink;
  final SettingsStore _store;
  final List<Hrir> _profiles;

  bool _enabled = false;
  int _profile = 0;
  String? _previousDefault; // the default output to give back
  bool _dirty = false;
  Future<void> _chain = Future.value();

  /// Completes when everything asked for so far has been done (for tests).
  Future<void> get idle => _chain;

  void _load(String? text) {
    for (final line in (text ?? '').split('\n')) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq), value = line.substring(eq + 1);
      switch (key) {
        case 'enabled':
          _enabled = value == '1';
        case 'profile':
          final i = _profiles.indexWhere((p) => p.path == value);
          if (i >= 0) _profile = i;
        case 'previous_default':
          _previousDefault = value.isEmpty ? null : value;
      }
    }
    if (_profiles.isEmpty) _enabled = false;
  }

  String _serialize() =>
      'version=1\nenabled=${_enabled ? 1 : 0}\n'
      'profile=${_profiles.isEmpty ? '' : _profiles[_profile].path}\nprevious_default=${_previousDefault ?? ''}\n';

  @override
  List<Control> controls() => [
    Control(
      id: 'vsurround.enable',
      group: _group,
      label: 'Virtual surround for headphones',
      kind: ControlKind.toggle,
      value: _enabled ? 1 : 0,
    ),
    Control(
      id: 'vsurround.profile',
      group: _group,
      label: 'Effect',
      kind: ControlKind.choice,
      max: _profiles.length - 1,
      choices: [for (final p in _profiles) p.label],
      value: _profile,
    ),
  ];

  @override
  int? get(String id) => switch (id) {
    'vsurround.enable' => _enabled ? 1 : 0,
    'vsurround.profile' => _profile,
    _ => null,
  };

  @override
  SetResult set(String id, int value) {
    switch (id) {
      case 'vsurround.enable':
        if (value < 0 || value > 1) return SetResult.outOfRange;
        if (value == 1 && _profiles.isEmpty) return SetResult.failed;
        if ((value == 1) == _enabled) return SetResult.ok;
        _enabled = value == 1;
      case 'vsurround.profile':
        if (value < 0 || value >= _profiles.length) return SetResult.outOfRange;
        if (value == _profile) return SetResult.ok;
        _profile = value;
      default:
        return SetResult.unknownControl;
    }
    _dirty = true;
    onChange?.call(id, value);
    _schedule(); // the effect only matters while it runs, but _apply knows that
    return SetResult.ok;
  }

  void _schedule() {
    _chain = _chain.then((_) => _apply()).catchError((Object _) {});
  }

  Future<void> _apply() async {
    if (!_enabled) {
      await host.stop();
      final back = _previousDefault;
      if (back != null) {
        host.setDefaultSink(back);
        _previousDefault = null;
        _dirty = true;
      }
      return;
    }
    final target = targetSink();
    final ok =
        target != null &&
        await host.start(
          buildFilterChainConf(hrir: _profiles[_profile], targetSink: target),
        );
    if (!ok) {
      _enabled = false; // say so: the window puts the switch back
      _dirty = true;
      onChange?.call('vsurround.enable', 0);
      return;
    }
    final current = host.defaultSink();
    if (current != virtualSinkName) {
      _previousDefault = current;
      _dirty = true;
      // a new sink starts at 100%: give it the volume the output had, or the switch would be a lot louder
      final volume = current == null ? null : host.sinkVolume(current);
      if (volume != null) host.setSinkVolume(virtualSinkName, volume);
    }
    host.setDefaultSink(virtualSinkName);
  }

  @override
  void flush() {
    if (_dirty && _store.save(_serialize())) _dirty = false;
  }

  @override
  void close() {
    // the process outlives the app on purpose only if the app is killed; a clean close gives the output back
    if (_enabled) {
      unawaited(host.stop());
      final back = _previousDefault;
      if (back != null) host.setDefaultSink(back);
    }
    flush();
  }
}
