// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models.dart';

enum AppStatus { connecting, noDevice, ready }

/// What the window shows, and the operations it can ask for. It is the only place that talks to
/// the [OpenBlasterClient].
class AppState extends ChangeNotifier {
  // A named parameter cannot be `this._log`: the field is private.
  // ignore: prefer_initializing_formals
  AppState(this._client, {void Function(String)? log}) : _log = log;

  final OpenBlasterClient _client;
  final void Function(String)? _log;

  AppStatus status = AppStatus.connecting;
  DeviceRef? device;
  List<Control> controls = const [];

  /// The last problem worth telling the user about; the window shows it once and clears it.
  String? message;

  StreamSubscription<void>? _devicesSub;
  StreamSubscription<ControlChange>? _changeSub;
  int _generation = 0;
  bool _disposed = false;

  /// The pages, in the order the controls list them.
  List<String> get groups {
    final seen = <String>[];
    for (final c in controls) {
      if (!seen.contains(c.group)) seen.add(c.group);
    }
    return seen;
  }

  List<Control> controlsIn(String group) => [
    for (final c in controls)
      if (c.group == group) c,
  ];

  Future<void> start() async {
    _devicesSub = _client.devicesChanged.listen((_) => refresh());
    await refresh();
  }

  /// Look at what is there now. Overlapping refreshes are harmless: only the newest counts.
  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final devices = await _client.devices();
      if (generation != _generation) return;
      if (devices.isEmpty) {
        await _changeSub?.cancel();
        _changeSub = null;
        device = null;
        controls = const [];
        _become(AppStatus.noDevice);
        return;
      }
      final first = devices.first;
      final list = await _client.controls(first);
      if (generation != _generation) return;
      if (device != first || _changeSub == null) {
        await _changeSub?.cancel();
        _changeSub = _client.changes(first).listen(_onChange);
      }
      device = first;
      controls = list;
      if (_client.notices.isNotEmpty) message = _client.notices.join('\n');
      _log?.call('connected to ${first.name}: ${list.length} controls');
      _become(AppStatus.ready);
    } on ControlError catch (e) {
      if (generation == _generation) {
        message = e.message;
        _become(AppStatus.noDevice);
      }
    } catch (e) {
      if (generation == _generation) {
        _log?.call('refresh failed: $e');
        message = 'Cannot read the sound card: $e';
        _become(AppStatus.noDevice);
      }
    }
  }

  /// Set a control. The window changes at once; if the card refuses, it changes back.
  Future<void> set(Control control, int value) async {
    final dev = device;
    if (dev == null || !control.enabled) {
      _log?.call(
        'set ${control.id} = $value ignored: '
        '${dev == null ? 'no card' : 'the control is read-only or unreadable'}',
      );
      return;
    }
    final previous = control.value;
    _log?.call('set ${control.id} = $value');
    _apply(control.id, value);
    try {
      await _client.set(dev, control.id, value);
      _log?.call('  ${control.id}: accepted');
    } on ControlError catch (e) {
      _log?.call('  ${control.id}: refused: ${e.name}: ${e.message}');
      message = '${control.label}: ${e.message}';
      _apply(control.id, previous);
    } catch (e) {
      _log?.call('  ${control.id}: the request failed: $e');
      message = '${control.label}: $e';
      _apply(control.id, previous);
      unawaited(refresh());
    }
  }

  void clearMessage() {
    if (message == null) return;
    message = null;
    _notify();
  }

  void _onChange(ControlChange c) {
    _log?.call('reports ${c.id} = ${c.value}');
    _apply(c.id, c.value);
  }

  void _apply(String id, int? value) {
    final i = controls.indexWhere((c) => c.id == id);
    if (i < 0 || controls[i].value == value) return;
    controls = List.of(controls)..[i] = controls[i].withValue(value);
    _notify();
  }

  void _become(AppStatus s) {
    status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _devicesSub?.cancel();
    _changeSub?.cancel();
    super.dispose();
  }
}
