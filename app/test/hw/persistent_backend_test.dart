// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/alsa_backend.dart';
import 'package:openblaster/src/hw/alsa_io.dart';
import 'package:openblaster/src/hw/persistent_backend.dart';
import 'package:openblaster/src/hw/store.dart';

void main() {
  late MemoryAlsaIo io;
  late MemoryStore store;
  PersistentBackend open([MemoryAlsaIo? card, MemoryStore? s]) =>
      PersistentBackend(AlsaBackend(card ?? io), s ?? store);

  setUp(() {
    io = makeDemoCard();
    store = MemoryStore();
  });

  test('the first run records what the card has, and changes nothing', () {
    final b = open();
    expect(io.writes, isEmpty);
    b.flush();
    expect(store.saves, 1);
    expect(store.text, contains('volume.master=50'));
    expect(store.text, contains('output.select=0'));
  });

  test('every writable control is saved, read-only ones are not', () {
    final card = MemoryAlsaIo()
      ..addInt('Master Playback Volume', 0, 99, 1, [30])
      ..addBool('Master Playback Switch', 1, writable: false);
    final s = MemoryStore();
    open(card, s).flush();
    expect(parseSnapshot(s.text!), {'volume.master': 30});
  });

  test('a change is saved on flush, once per burst, and not again when nothing changed', () {
    final b = open();
    b.flush();
    b.set('volume.master', 70);
    b.set('volume.master', 71);
    b.flush();
    b.flush();
    expect(store.saves, 2);
    expect(parseSnapshot(store.text!)['volume.master'], 71);
  });

  test('a change made by another program is saved too', () {
    final b = open();
    b.flush();
    io.externalSet('Output Select', [1]);
    b.poll();
    b.flush();
    expect(parseSnapshot(store.text!)['output.select'], 1);
  });

  test('the saved values are put back when the card has forgotten them', () {
    final first = open();
    first.set('volume.master', 70);
    first.set('fx.crystalizer', 1);
    first.set('eq.band3', 40);
    first.set('volume.mute', 1); // an inverted control
    first.flush();

    final restarted = makeDemoCard(); // a fresh boot: defaults again
    final b = open(restarted);
    expect(b.get('volume.master'), 70);
    expect(b.get('fx.crystalizer'), 1);
    expect(b.get('eq.band3'), 40);
    expect(b.get('volume.mute'), 1);
    expect(b.get('output.select'), 0);
  });

  test('only values that differ are written to the card', () {
    open().flush();
    final restarted = makeDemoCard();
    open(restarted);
    expect(restarted.writes, isEmpty);
  });

  test('restoring does not rewrite the file', () {
    open().flush();
    final saves = store.saves;
    final b = open(makeDemoCard()..externalSet('Master Playback Volume', [10]));
    b.flush();
    expect(store.saves, saves);
  });

  test('values the card refuses are skipped and the rest still apply', () {
    store.text = 'version=1\nvolume.master=5000\nnope.gone=1\nvolume.mute=1\noutput.select=1\n';
    final b = open();
    expect(b.get('volume.master'), 50, reason: 'out of range');
    expect(b.get('output.select'), 1);
    expect(b.get('volume.mute'), 1);
  });

  test('a damaged file is ignored, not fatal', () {
    store.text = 'ÿ\u0000 garbage\n=\nvolume.master=abc\nvolume.master=\n';
    final b = open();
    expect(b.get('volume.master'), 50);
    expect(io.writes, isEmpty);
  });

  test('a failed save is retried at the next flush', () {
    final b = open();
    store.failSaves = true;
    b.flush();
    b.flush();
    expect(store.saves, 2);
    store.failSaves = false;
    b.flush();
    b.flush();
    expect(store.saves, 3);
    expect(store.text, isNotNull);
  });

  test('changes are announced through the wrapper', () {
    final b = open();
    final seen = <(String, int)>[];
    b.onChange = (id, v) => seen.add((id, v));
    b.set('volume.master', 60);
    expect(seen, [('volume.master', 60)]);
  });

  test('parsing ignores the version line and junk', () {
    expect(parseSnapshot('version=1\na.b=3\nbad line\nc=-2\nD=4\n'), {
      'a.b': 3,
      'c': -2,
    });
  });
}
