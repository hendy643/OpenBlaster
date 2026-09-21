// SPDX-License-Identifier: Apache-2.0

/// How a control is shown: a switch, a slider, a list of choices or a colour (0xRRGGBB).
enum ControlKind { toggle, range, choice, color }

/// One control of a device, as the hardware layer describes it.
class Control {
  const Control({
    required this.id,
    required this.group,
    required this.label,
    required this.kind,
    this.min = 0,
    this.max = 1,
    this.step = 1,
    this.choices = const [],
    this.writable = true,
    this.available = true,
    this.value,
  });

  final String id;
  final String group;
  final String label;
  final ControlKind kind;
  final int min;
  final int max;
  final int step;
  final List<String> choices;
  final bool writable;

  /// False if the card could not be read: the control is shown but disabled.
  final bool available;
  final int? value;

  Control withValue(int? v) => Control(
    id: id,
    group: group,
    label: label,
    kind: kind,
    min: min,
    max: max,
    step: step,
    choices: choices,
    writable: writable,
    available: available,
    value: v,
  );

  bool get enabled => writable && available;
}

/// A sound card we control.
class DeviceRef {
  const DeviceRef({required this.card, required this.name});
  final int card; // the ALSA card number
  final String name;

  @override
  bool operator ==(Object other) => other is DeviceRef && other.card == card;

  @override
  int get hashCode => card;
}

/// A change made behind our back (another mixer, the card itself).
class ControlChange {
  const ControlChange(this.id, this.value);
  final String id;
  final int value;
}

/// A control refused a request. [name] says why: "OutOfRange", "ReadOnly", "UnknownControl", "Failed".
class ControlError implements Exception {
  const ControlError(this.name, this.message);
  final String name;
  final String message;

  @override
  String toString() => message;
}
