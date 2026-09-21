// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/alsa_backend.dart';
import 'package:openblaster/src/hw/alsa_io.dart';
import 'package:openblaster/src/hw/backend.dart';
import 'package:openblaster/src/hw/catalog.dart';
import 'package:openblaster/src/hw/discovery.dart';
import 'package:openblaster/src/hw/store.dart';
import 'package:openblaster/src/models.dart';

void main() {
  group('catalogue', () {
    test('ids and ALSA names are unique', () {
      expect({
        for (final m in alsaCatalog) m.id,
      }, hasLength(alsaCatalog.length));
      expect({
        for (final m in alsaCatalog) m.alsaName,
      }, hasLength(alsaCatalog.length));
    });
    test(
      'every equalizer band is there and only the two mutes are inverted',
      () {
        for (var i = 0; i < 10; i++) {
          expect(alsaCatalog.any((m) => m.id == 'eq.band$i'), isTrue);
        }
        expect(
          {
            for (final m in alsaCatalog)
              if (m.invert) m.id,
          },
          {'volume.mute', 'input.mute'},
        );
      },
    );
    test('models are found by subsystem id', () {
      expect(modelName(0x1102, 0x0191), 'Sound BlasterX AE-5 Plus');
      expect(modelName(0x1102, 0x0051), 'Sound BlasterX AE-5');
      expect(modelName(0x1102, 0xffff), 'Creative sound card');
      expect(modelName(0x8086, 0x0191), 'Creative sound card');
    });
  });

  group('alsa backend', () {
    late MemoryAlsaIo io;
    late AlsaBackend b;
    setUp(() {
      io = makeDemoCard();
      b = AlsaBackend(io);
    });
    Control c(String id) => b.controls().firstWhere((x) => x.id == id);

    test('the demo card offers the whole catalogue in order', () {
      expect(b.controls().map((x) => x.id), [
        for (final m in alsaCatalog) m.id,
      ]);
    });
    test('only catalogued controls the card has are offered', () {
      final small = MemoryAlsaIo()
        ..addInt('Master Playback Volume', 0, 99, 0, [50])
        ..addBool('Something Else', 1);
      expect(AlsaBackend(small).controls().map((x) => x.id), ['volume.master']);
    });
    test('kind, range and choices come from the card', () {
      expect(c('volume.master').kind, ControlKind.range);
      expect(c('volume.master').max, 99);
      expect(c('volume.master').step, 1, reason: 'a step of 0 means 1');
      expect(c('output.select').kind, ControlKind.choice);
      expect(c('output.select').choices, ['Speakers', 'Headphone']);
      expect(c('output.select').max, 1);
      expect(c('fx.crystalizer').kind, ControlKind.toggle);
      expect(c('volume.master').value, 50);
    });
    test('other types and empty enumerations are left out', () {
      final odd = MemoryAlsaIo()
        ..addOther('Master Playback Volume')
        ..addEnum('Output Select', [], 0);
      expect(AlsaBackend(odd).controls(), isEmpty);
    });
    test(
      'get reads the first channel; a failed read is no value, not zero',
      () {
        expect(b.get('input.volume'), 90);
        io.failReads = true;
        expect(b.get('volume.master'), isNull);
        expect(b.get('nope'), isNull);
      },
    );
    test('mute is the inverse of the ALSA switch', () {
      expect(b.get('volume.mute'), 0);
      expect(b.set('volume.mute', 1), SetResult.ok);
      expect(io.valuesOf('Master Playback Switch'), [0]);
      expect(b.get('volume.mute'), 1);
      expect(b.get('fx.enable'), 1, reason: 'other switches are not inverted');
    });
    test('set checks the range', () {
      expect(b.set('volume.master', 100), SetResult.outOfRange);
      expect(b.set('volume.master', -1), SetResult.outOfRange);
      expect(b.set('volume.master', 99), SetResult.ok);
      expect(b.set('bass.crossover', 1), SetResult.unknownControl);
      expect(
        b.set('speakers.bass_crossover', 0),
        SetResult.outOfRange,
        reason: 'minimum is 1',
      );
    });
    test('a stereo control moves both channels together', () {
      b.set('input.volume', 70);
      expect(io.valuesOf('Capture Volume'), [70, 70]);
    });
    test('a read-only control cannot be set, a refused write is reported', () {
      final ro = MemoryAlsaIo()
        ..addInt('Master Playback Volume', 0, 9, 1, [1], writable: false);
      expect(AlsaBackend(ro).set('volume.master', 2), SetResult.readOnly);
      io.failWrites = true;
      expect(b.set('volume.master', 60), SetResult.failed);
    });
    test('our own set is announced once; a repeat is not', () {
      final seen = <(String, int)>[];
      b.onChange = (id, v) => seen.add((id, v));
      b.set('volume.master', 60);
      b.set('volume.master', 60);
      expect(seen, [('volume.master', 60)]);
    });
    test(
      'changes behind our back are reported once, in the control\'s own sense',
      () {
        final seen = <(String, int)>[];
        b.onChange = (id, v) => seen.add((id, v));
        io.externalSet('Master Playback Volume', [10]);
        io.externalSet('Master Playback Switch', [0]); // ALSA "off" is muted
        b.poll();
        b.poll();
        expect(seen, [('volume.master', 10), ('volume.mute', 1)]);
      },
    );
    test('poll without a handler is harmless', () {
      io.externalSet('Master Playback Volume', [10]);
      expect(b.poll, returnsNormally);
    });
  });

  group('discovery', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('ob-sys'));
    tearDown(() => root.deleteSync(recursive: true));

    void card(
      String name, {
      String? vendor = '0x1102',
      String device = '0x0012',
      String sv = '0x1102',
      String sd = '0x0191',
    }) {
      final dev = Directory('${root.path}/$name/device')
        ..createSync(recursive: true);
      if (vendor != null)
        File('${dev.path}/vendor').writeAsStringSync('$vendor\n');
      File('${dev.path}/device').writeAsStringSync('$device\n');
      File('${dev.path}/subsystem_vendor').writeAsStringSync('$sv\n');
      File('${dev.path}/subsystem_device').writeAsStringSync('$sd\n');
    }

    test('a Creative Sound Core3D card is found with its model', () {
      card('card1');
      final cards = findCards(root.path);
      expect(cards.single.card, 1);
      expect(cards.single.name, 'Sound BlasterX AE-5 Plus');
      expect(cards.single.hasLighting, isTrue);
    });
    test('other cards and other nodes are skipped', () {
      card('card0', vendor: '0x8086', device: '0x9d71');
      card('controlC1');
      card('hwC1D0');
      card('card');
      card('card1x');
      expect(findCards(root.path), isEmpty);
    });
    test('cards come back in numeric order', () {
      card('card10');
      card('card2');
      expect(findCards(root.path).map((c) => c.card), [2, 10]);
    });
    test('models without the LED strip say so', () {
      card('card1', sd: '0x0071');
      expect(findCards(root.path).single.hasLighting, isFalse);
    });
    test('unreadable or malformed ids skip the card', () {
      card('card1', vendor: null);
      card('card2', vendor: 'banana');
      expect(findCards(root.path), isEmpty);
    });
    test('a missing sysfs is no cards, not a crash', () {
      expect(findCards('${root.path}/nope'), isEmpty);
    });
  });

  group('file store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ob-state'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a missing file is no settings', () {
      expect(FileStore('${dir.path}/a/lighting.conf').load(), isNull);
    });
    test(
      'save creates the directory, replaces the file and leaves no temporary',
      () {
        final s = FileStore('${dir.path}/a/lighting.conf');
        expect(s.save('one'), isTrue);
        expect(s.save('two'), isTrue);
        expect(s.load(), 'two');
        expect(
          Directory('${dir.path}/a')
              .listSync()
              .map((e) => e.uri.pathSegments.last),
          ['lighting.conf'],
        );
      },
    );
    test('a save that cannot happen says so', () {
      File('${dir.path}/blocked').writeAsStringSync('x');
      expect(FileStore('${dir.path}/blocked/lighting.conf').save('x'), isFalse);
    });
    test('a file that is not text is as good as none', () {
      File('${dir.path}/bin').writeAsBytesSync([0xff, 0xfe, 0x80]);
      expect(FileStore('${dir.path}/bin').load(), isNull);
    });
  });
}
