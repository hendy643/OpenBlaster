// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/alsa_backend.dart';
import 'package:openblaster/src/hw/alsa_io.dart';
import 'package:openblaster/src/hw/backend.dart';
import 'package:openblaster/src/hw/bar2.dart';
import 'package:openblaster/src/hw/discovery.dart';
import 'package:openblaster/src/hw/led_port.dart';
import 'package:openblaster/src/hw/lighting_backend.dart';
import 'package:openblaster/src/hw/store.dart';
import 'package:openblaster/src/local_client.dart';
import 'package:openblaster/src/models.dart';

const _ae5 = CardInfo(
  card: 3,
  subsystemVendor: 0x1102,
  subsystemDevice: 0x0191,
  name: 'AE-5 Plus',
);

Future<void> pause([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late MemoryAlsaIo alsa;
  late MemoryBar2 bar;
  late MemoryStore store;
  late List<CardInfo> cards;
  late int opens;
  late LocalClient client;

  setUp(() {
    alsa = makeDemoCard();
    bar = MemoryBar2();
    store = MemoryStore();
    cards = [_ae5];
    opens = 0;
    client = LocalClient(
      finder: () => cards,
      factory: (_) {
        opens++;
        return CompositeBackend([
          AlsaBackend(alsa),
          LightingBackend(LedPort(bar), store),
        ]);
      },
      rescanEvery: const Duration(milliseconds: 40),
      pollEvery: const Duration(milliseconds: 30),
      saveAfter: const Duration(milliseconds: 30),
    );
  });
  tearDown(() => client.close());

  test('devices are the found cards, opened once', () async {
    final d = await client.devices();
    expect(d.single.card, 3);
    expect(d.single.name, 'AE-5 Plus');
    await client.devices();
    expect(opens, 1);
  });

  test('controls include the ALSA ones and the lighting ones', () async {
    final d = (await client.devices()).single;
    final ids = (await client.controls(d)).map((c) => c.id);
    expect(
      ids,
      containsAll(['volume.master', 'lighting.pattern', 'lighting.color1']),
    );
  });

  test(
    'a set reaches the card, and refusals are ControlErrors with a name',
    () async {
      final d = (await client.devices()).single;
      await client.set(d, 'volume.master', 70);
      expect(alsa.valuesOf('Master Playback Volume'), [70]);
      for (final (id, v, name) in [
        ('volume.master', 1000, 'OutOfRange'),
        ('nope', 1, 'UnknownControl'),
      ]) {
        await expectLater(
          client.set(d, id, v),
          throwsA(isA<ControlError>().having((e) => e.name, 'name', name)),
        );
      }
      alsa.failWrites = true;
      await expectLater(
        client.set(d, 'volume.master', 5),
        throwsA(isA<ControlError>().having((e) => e.name, 'name', 'Failed')),
      );
    },
  );

  test('changes made behind our back arrive on the change stream', () async {
    final d = (await client.devices()).single;
    final seen = <ControlChange>[];
    final sub = client.changes(d).listen(seen.add);
    alsa.externalSet('Output Select', [1]);
    await pause(100);
    await sub.cancel();
    expect(seen.map((c) => (c.id, c.value)), [('output.select', 1)]);
  });

  test('a lighting change reaches the LEDs and is saved, soon', () async {
    final d = (await client.devices()).single;
    await client.set(d, 'lighting.color1', 0xff0000);
    await client.set(d, 'lighting.pattern', 0);
    await pause(150);
    expect(bar.received, isNotEmpty, reason: 'a frame went out');
    expect(store.text, contains('color1=ff0000'));
  });

  test('a card that appears or vanishes is announced', () async {
    await client.devices();
    var events = 0;
    client.devicesChanged.listen((_) => events++);
    cards = [];
    await pause(120);
    expect(events, 1);
    expect(await client.devices(), isEmpty);
    cards = [_ae5];
    await pause(120);
    expect(events, 2);
    expect(opens, 2);
  });

  test(
    'a card that cannot be opened is tried again at the next scan',
    () async {
      var attempts = 0;
      final flaky = LocalClient(
        finder: () => cards,
        factory: (_) => ++attempts < 2 ? null : AlsaBackend(alsa),
        rescanEvery: const Duration(milliseconds: 30),
      );
      expect(await flaky.devices(), isEmpty);
      await pause(100);
      expect(await flaky.devices(), hasLength(1));
      await flaky.close();
    },
  );

  test('closing saves what is unsaved', () async {
    final d = (await client.devices()).single;
    await client.set(d, 'lighting.brightness', 33);
    await client.close();
    expect(store.text, contains('brightness=33'));
  });

  test('controls of a card that is gone fail cleanly', () async {
    final d = (await client.devices()).single;
    cards = [];
    await pause(120);
    await expectLater(client.controls(d), throwsA(isA<ControlError>()));
  });

  test('the demo client works end to end', () async {
    final demo = LocalClient.demo();
    final d = (await demo.devices()).single;
    expect(d.name, contains('demo'));
    await demo.set(d, 'volume.master', 10);
    expect(
      (await demo.controls(d)).firstWhere((c) => c.id == 'volume.master').value,
      10,
    );
    await demo.close();
  });
}
