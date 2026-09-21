// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:openblaster/src/client.dart';
import 'package:openblaster/src/models.dart';

/// Hardware in memory with hooks to make it misbehave, to test the window's state.
class FakeClient implements OpenBlasterClient {
  FakeClient({
    List<Control>? controls,
    this.deviceName = 'Sound BlasterX AE-5 Plus (demo)',
  }) : _controls = {for (final c in controls ?? demoControls()) c.id: c};

  String? deviceName;
  final Map<String, Control> _controls;
  final _devices = StreamController<void>.broadcast();
  final _changes = StreamController<ControlChange>.broadcast();

  /// Every accepted set(), in order.
  final sets = <(String, int)>[];

  /// When set, the next set() throws this (a [ControlError], or anything to imitate a broken bus).
  Object? failNext;
  bool failControls = false;

  static const device = DeviceRef(name: 'demo', card: 99);

  @override
  final notices = <String>[];

  @override
  Stream<void> get devicesChanged => _devices.stream;

  @override
  Future<List<DeviceRef>> devices() async => deviceName == null
      ? const []
      : [DeviceRef(name: deviceName!, card: device.card)];

  @override
  Future<List<Control>> controls(DeviceRef d) async {
    if (failControls)
      throw const ControlError('Failed', 'cannot read the card');
    return _controls.values.toList();
  }

  @override
  Future<void> set(DeviceRef d, String id, int value) async {
    final err = failNext;
    if (err != null) {
      failNext = null;
      throw err;
    }
    final c = _controls[id];
    if (c == null) {
      throw ControlError('UnknownControl', 'No readable control "$id"');
    }
    if (!c.writable) {
      throw ControlError('ReadOnly', '$id: control is read-only');
    }
    if (value < c.min || value > c.max) {
      throw ControlError('OutOfRange', '$id: value out of range');
    }
    _controls[id] = c.withValue(value);
    sets.add((id, value));
    _changes.add(ControlChange(id, value));
  }

  @override
  Stream<ControlChange> changes(DeviceRef d) => _changes.stream;

  // Test hooks ----------------------------------------------------------------------------------

  /// Another program changed a control.
  void externalChange(String id, int value) {
    _controls[id] = _controls[id]!.withValue(value);
    _changes.add(ControlChange(id, value));
  }

  void deviceListChanged() => _devices.add(null);

  @override
  Future<void> close() async {
    await _devices.close();
    await _changes.close();
  }

  static List<Control> demoControls() => const [
    Control(
      id: 'volume.master',
      group: 'Output',
      label: 'Volume',
      kind: ControlKind.range,
      max: 99,
      value: 50,
    ),
    Control(
      id: 'volume.mute',
      group: 'Output',
      label: 'Mute',
      kind: ControlKind.toggle,
      value: 0,
    ),
    Control(
      id: 'output.select',
      group: 'Output',
      label: 'Output',
      kind: ControlKind.choice,
      max: 1,
      choices: ['Speakers', 'Headphone'],
      value: 0,
    ),
    Control(
      id: 'speakers.layout',
      group: 'Speakers',
      label: 'Speaker layout',
      kind: ControlKind.choice,
      max: 4,
      choices: ['2.0', '2.1', '4.0', '4.1', '5.1'],
      value: 0,
    ),
    Control(
      id: 'fx.crystalizer',
      group: 'Effects',
      label: 'Crystalizer',
      kind: ControlKind.toggle,
      value: 0,
    ),
    Control(
      id: 'fx.crystalizer_level',
      group: 'Effects',
      label: 'Crystalizer level',
      kind: ControlKind.range,
      max: 100,
      value: 65,
    ),
    Control(
      id: 'eq.band0',
      group: 'Equalizer',
      label: '31 Hz',
      kind: ControlKind.range,
      max: 48,
      value: 24,
    ),
    Control(
      id: 'eq.band1',
      group: 'Equalizer',
      label: '62 Hz',
      kind: ControlKind.range,
      max: 48,
      value: 24,
    ),
  ];
}
