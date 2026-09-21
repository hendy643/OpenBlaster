// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/models.dart';

void main() {
  const c = Control(
    id: 'output.select',
    group: 'Output',
    label: 'Output',
    kind: ControlKind.choice,
    max: 1,
    choices: ['Speakers', 'Headphone'],
    value: 1,
  );

  test('a control is enabled when writable and available', () {
    expect(c.enabled, isTrue);
    expect(
      const Control(
        id: 'a',
        group: 'G',
        label: 'A',
        kind: ControlKind.toggle,
        writable: false,
      ).enabled,
      isFalse,
    );
    expect(
      const Control(
        id: 'a',
        group: 'G',
        label: 'A',
        kind: ControlKind.toggle,
        available: false,
      ).enabled,
      isFalse,
    );
  });

  test('withValue changes only the value', () {
    final d = c.withValue(0);
    expect(d.value, 0);
    expect(d.label, 'Output');
    expect(d.choices, hasLength(2));
    expect(d.kind, ControlKind.choice);
  });

  test('devices are the same device when their card matches', () {
    expect(
      const DeviceRef(card: 1, name: 'x'),
      const DeviceRef(card: 1, name: 'renamed'),
    );
    expect(
      const DeviceRef(card: 1, name: 'x'),
      isNot(const DeviceRef(card: 2, name: 'x')),
    );
  });
}
