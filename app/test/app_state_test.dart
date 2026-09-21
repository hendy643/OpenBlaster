// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/app_state.dart';

import 'support/fake_client.dart';

import 'package:openblaster/src/models.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  logTests();
  late FakeClient client;
  late AppState state;

  setUp(() {
    client = FakeClient();
    state = AppState(client);
  });
  tearDown(() async {
    state.dispose();
    await client.close();
  });

  Control control(String id) => state.controls.firstWhere((c) => c.id == id);

  test(
    'starts connecting, then is ready with the card and its controls',
    () async {
      expect(state.status, AppStatus.connecting);
      await state.start();
      expect(state.status, AppStatus.ready);
      expect(state.device?.name, 'Sound BlasterX AE-5 Plus (demo)');
      expect(state.controls, isNotEmpty);
    },
  );

  test('pages are the groups in the order the controls listed them', () async {
    await state.start();
    expect(state.groups, ['Output', 'Speakers', 'Effects', 'Equalizer']);
    expect(state.controlsIn('Equalizer').map((c) => c.id), [
      'eq.band0',
      'eq.band1',
    ]);
    expect(state.controlsIn('Nope'), isEmpty);
  });

  test('no card is its own state, and a card appearing fixes it', () async {
    client.deviceName = null;
    await state.start();
    expect(state.status, AppStatus.noDevice);
    expect(state.controls, isEmpty);
    client.deviceName = 'Card';
    client.deviceListChanged();
    await settle();
    await settle();
    expect(state.status, AppStatus.ready);
    expect(state.device?.name, 'Card');
  });

  test('a card that vanishes empties the page', () async {
    await state.start();
    client.deviceName = null;
    client.deviceListChanged();
    await settle();
    await settle();
    expect(state.status, AppStatus.noDevice);
    expect(state.device, isNull);
  });

  test('a card that cannot be read is reported, not thrown', () async {
    final broken = _ThrowingClient();
    final s = AppState(broken);
    await s.start();
    expect(s.status, AppStatus.noDevice);
    expect(s.message, contains('Cannot read'));
    s.dispose();
  });

  test('notices from the hardware layer are shown', () async {
    client.notices.add('Lighting is unavailable: nope');
    await state.start();
    expect(state.message, 'Lighting is unavailable: nope');
  });

  test('failing to read the controls is reported, not thrown', () async {
    client.failControls = true;
    await state.start();
    expect(state.status, AppStatus.noDevice);
    expect(state.message, 'cannot read the card');
  });

  group('set', () {
    test('changes the value at once and tells the card', () async {
      await state.start();
      final seen = <int?>[];
      state.addListener(() => seen.add(control('volume.master').value));
      final done = state.set(control('volume.master'), 70);
      expect(
        control('volume.master').value,
        70,
        reason: 'the window must not wait for the card',
      );
      await done;
      expect(client.sets, [('volume.master', 70)]);
      expect(control('volume.master').value, 70);
    });

    test('a refusal puts the old value back and says why', () async {
      await state.start();
      final c = control('volume.master');
      client.failNext = const ControlError(
        'OutOfRange',
        'volume.master: value out of range',
      );
      await state.set(c, 70);
      expect(control('volume.master').value, 50);
      expect(state.message, 'Volume: volume.master: value out of range');
    });

    test('an unexpected failure puts the old value back and says so', () async {
      await state.start();
      client.failNext = StateError('device gone');
      await state.set(control('volume.master'), 70);
      expect(control('volume.master').value, 50);
      expect(state.message, contains('device gone'));
    });

    test('a read-only or unreadable control is not sent', () async {
      client = FakeClient(
        controls: const [
          Control(
            id: 'a.ro',
            group: 'G',
            label: 'RO',
            kind: ControlKind.toggle,
            writable: false,
            value: 0,
          ),
          Control(
            id: 'a.na',
            group: 'G',
            label: 'NA',
            kind: ControlKind.toggle,
            available: false,
          ),
        ],
      );
      state = AppState(client);
      await state.start();
      await state.set(control('a.ro'), 1);
      await state.set(control('a.na'), 1);
      expect(client.sets, isEmpty);
      expect(control('a.ro').value, 0);
    });

    test('nothing is sent when there is no card', () async {
      client.deviceName = null;
      await state.start();
      await state.set(
        const Control(
          id: 'x',
          group: 'G',
          label: 'X',
          kind: ControlKind.toggle,
          value: 0,
        ),
        1,
      );
      expect(client.sets, isEmpty);
    });
  });

  test('a change made elsewhere shows up', () async {
    await state.start();
    client.externalChange('output.select', 1);
    await settle();
    expect(control('output.select').value, 1);
  });

  test('a change for a control we do not have is ignored', () async {
    await state.start();
    client.externalChange('eq.band1', 30);
    final before = state.controls.length;
    await settle();
    expect(state.controls.length, before);
  });

  test('listeners are told only when something changed', () async {
    await state.start();
    var calls = 0;
    state.addListener(() => calls++);
    client.externalChange('volume.master', 50); // the value it already has
    await settle();
    expect(calls, 0);
    client.externalChange('volume.master', 51);
    await settle();
    expect(calls, 1);
  });

  test(
    'clearing the message tells listeners once, and only if there was one',
    () async {
      await state.start();
      var calls = 0;
      state.addListener(() => calls++);
      state.clearMessage();
      expect(calls, 0);
      client.failNext = const ControlError('Failed', 'nope');
      await state.set(control('volume.master'), 60);
      calls = 0;
      state.clearMessage();
      expect(state.message, isNull);
      expect(calls, 1);
    },
  );

  test('of overlapping refreshes only the newest counts', () async {
    final slow = _SlowClient();
    final s = AppState(slow);
    final first = s.refresh();
    slow.controlsGate = Completer<void>(); // hold the first answer
    final second = s.refresh();
    slow.controlsGate!.complete();
    await Future.wait([first, second]);
    expect(s.status, AppStatus.ready);
    expect(slow.controlCalls, greaterThanOrEqualTo(1));
    s.dispose();
  });

  test('nothing is notified after dispose', () async {
    await state.start();
    state.dispose();
    client.externalChange('volume.master', 60); // would notify a live listener
    await settle();
    // no exception is the assertion (a disposed ChangeNotifier throws if notified)
    state = AppState(client); // give tearDown something to dispose
  });
}

class _ThrowingClient extends FakeClient {
  @override
  Future<List<DeviceRef>> devices() async => throw StateError('bus closed');
}

class _SlowClient extends FakeClient {
  Completer<void>? controlsGate;
  int controlCalls = 0;
  @override
  Future<List<Control>> controls(DeviceRef d) async {
    controlCalls++;
    await controlsGate?.future;
    return super.controls(d);
  }
}

void logTests() {
  test('the log says what was asked and what came back', () async {
    final client = FakeClient();
    final lines = <String>[];
    final state = AppState(client, log: lines.add);
    await state.start();
    expect(lines.first, contains('connected to'));
    await state.set(
      state.controls.firstWhere((c) => c.id == 'volume.master'),
      70,
    );
    expect(lines, contains('set volume.master = 70'));
    expect(lines, contains('  volume.master: accepted'));
    client.failNext = const ControlError('OutOfRange', 'no');
    await state.set(
      state.controls.firstWhere((c) => c.id == 'volume.master'),
      71,
    );
    expect(
      lines.any((l) => l.contains('refused') && l.contains('OutOfRange')),
      isTrue,
    );
    client.externalChange('output.select', 1);
    await Future<void>.delayed(Duration.zero);
    expect(lines, contains('reports output.select = 1'));
    state.dispose();
    await client.close();
  });

  test('an ignored click says why', () async {
    final lines = <String>[];
    final client = FakeClient(
      controls: const [
        Control(
          id: 'a.ro',
          group: 'G',
          label: 'RO',
          kind: ControlKind.toggle,
          writable: false,
          value: 0,
        ),
      ],
    );
    final state = AppState(client, log: lines.add);
    await state.start();
    await state.set(state.controls.single, 1);
    expect(lines.last, contains('ignored'));
    expect(lines.last, contains('read-only'));
    state.dispose();
    await client.close();
  });
}
