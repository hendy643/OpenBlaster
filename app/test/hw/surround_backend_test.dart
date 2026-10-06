// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/backend.dart';
import 'package:openblaster/src/hw/store.dart';
import 'package:openblaster/src/hw/surround_backend.dart';
import 'package:openblaster/src/hw/virtual_surround.dart';
import 'package:openblaster/src/hw/virtual_surround_backend.dart';
import 'package:openblaster/src/models.dart';

const _pci = '0000:0b:00.0';
const _stereo = 'output:analog-stereo+input:analog-stereo';
const _stereoSink = 'alsa_output.pci-0000_0b_00.0.analog-stereo';

void main() {
  late MemoryPipeWire host;
  late MemoryStore store;
  late _Controls controls;
  late Serial serial;
  final changes = <String>[];

  SurroundBackend make({MemoryStore? s}) {
    final b = SurroundBackend(
      inner: controls,
      host: host,
      pci: _pci,
      store: s ?? store,
      serial: serial,
    );
    b.onChange = (id, v) => changes.add('$id=$v');
    return b;
  }

  setUp(() {
    host = MemoryPipeWire()
      ..def = _stereoSink
      ..volumes[_stereoSink] = 14;
    store = MemoryStore();
    controls = _Controls({'output.select': 1, 'fx.surround': 0, 'other': 5});
    serial = Serial();
    changes.clear();
  });

  group('the card\'s Surround', () {
    test('other controls are the card\'s own', () {
      final b = make();
      expect(b.get('other'), 5);
      expect(b.set('other', 6), SetResult.ok);
      expect(controls.values['other'], 6);
      expect(host.profileChanges, isEmpty);
    });

    test('on: the card gets its 5.1 profile, Output Select stays, the 5.1 sink is the output', () async {
      final b = make();
      expect(b.set('fx.surround', 1), SetResult.ok);
      await serial.idle;
      expect(host.profiles[_pci], surround51Profile);
      expect(controls.values['fx.surround'], 1);
      expect(controls.values['output.select'], 1);
      expect(host.def, endsWith('analog-surround-51'));
      expect(host.started, isEmpty); // nothing runs in PipeWire
    });

    test(
      'the volume of the output it replaces is given to the 5.1 sink',
      () async {
        final b = make();
        b.set('fx.surround', 1);
        await serial.idle;
        expect(host.volumes[host.def], host.volumes[_stereoSink]);
      },
    );

    test('the output it replaces is remembered, and given back even after a restart', () async {
      final b = make();
      b.set('fx.surround', 1);
      await serial.idle;
      b.flush();
      expect(store.load(), contains('previous_default=$_stereoSink'));
      host.def = 'alsa_output.pci-0000_0b_00.0.analog-surround-51';
      final again = make();
      await serial.idle;
      again.set('fx.surround', 0);
      await serial.idle;
      expect(host.defaultChanges.last, _stereoSink);
    });

    test('Output Select is put back after the profile change, which flips it, and again when the card goes back', () async {
      host = _FlippingPipeWire(() => controls.values['output.select'] = 0)
        ..def = _stereoSink;
      final b = make();
      b.set('fx.surround', 1);
      await serial.idle;
      expect(controls.values['output.select'], 1);
      b.set('fx.surround', 0);
      await serial.idle;
      expect(controls.values['output.select'], 1);
    });

    test(
      'off: the profile, Output Select and default output come back',
      () async {
        final b = make();
        b.set('fx.surround', 1);
        await serial.idle;
        b.set('fx.surround', 0);
        await serial.idle;
        expect(host.profiles[_pci], _stereo);
        expect(controls.values['fx.surround'], 0);
        expect(host.def, _stereoSink);
      },
    );

    test('setting what it already is does nothing', () async {
      final b = make();
      b.set('fx.surround', 0);
      await serial.idle;
      expect(host.profileChanges, isEmpty);
      b.set('fx.surround', 1);
      b.set('fx.surround', 1);
      await serial.idle;
      expect(host.profileChanges, [surround51Profile]);
    });

    test(
      'a card that will not switch puts the switch back and says so',
      () async {
        host.failProfile = true;
        final b = make();
        b.set('fx.surround', 1);
        await serial.idle;
        expect(controls.values['fx.surround'], 0);
        expect(changes, contains('fx.surround=0'));
        expect(host.def, _stereoSink);
        expect(controls.values['output.select'], 1);
      },
    );

    test('a refused value is refused', () {
      controls.refuse = true;
      expect(make().set('fx.surround', 1), SetResult.failed);
    });

    test(
      'a profile that was already 5.1 goes back to stereo, not to 5.1',
      () async {
        host.profiles[_pci] = surround51Profile;
        final b = make();
        b.set('fx.surround', 1);
        await serial.idle;
        b.set('fx.surround', 0);
        await serial.idle;
        expect(host.profiles[_pci], _stereo);
      },
    );

    test(
      'closing leaves the card set up; a restart remembers what to give back',
      () async {
        host.profiles[_pci] = _stereo;
        final b = make();
        b.set('fx.surround', 1);
        await serial.idle;
        b.close();
        expect(host.profiles[_pci], surround51Profile);

        final again = make(); // the switch is still on (the controls keep it)
        await serial.idle;
        expect(host.profiles[_pci], surround51Profile);
        again.set('fx.surround', 0);
        await serial.idle;
        expect(host.profiles[_pci], _stereo);
        expect(host.def, _stereoSink);
      },
    );

    test('what a crash left behind is undone when the app starts with Surround off', () async {
      host.profiles[_pci] = surround51Profile;
      host.def = 'alsa_output.pci-0000_0b_00.0.analog-surround-51';
      store.save(
        'version=1\nprevious_profile=$_stereo\nprevious_default=$_stereoSink\nprevious_output=1\n',
      );
      make();
      await serial.idle;
      expect(host.profiles[_pci], _stereo);
      expect(host.def, _stereoSink);
    });
  });

  group('exclusive with the virtual surround', () {
    late SurroundBackend hw;
    late VirtualSurroundBackend vs;

    setUp(() {
      hw = make();
      vs = VirtualSurroundBackend(
        host: host,
        store: MemoryStore(),
        profiles: const [
          Hrir('/h/atmos.wav', HrirKind.hesuvi, 'Dolby Atmos for Headphones'),
        ],
        targetSink: () => host.sinkFor(_pci),
        serial: serial,
      );
      vs.onEnabling = () => hw.set(SurroundBackend.id, 0);
      hw.onEnabling = () => vs.set('vsurround.enable', 0);
    });

    test('turning the card\'s Surround on turns the virtual one off', () async {
      vs.set('vsurround.enable', 1);
      await serial.idle;
      expect(host.running, isTrue);
      expect(host.def, virtualSinkName);

      hw.set('fx.surround', 1);
      await serial.idle;
      expect(vs.get('vsurround.enable'), 0);
      expect(host.running, isFalse);
      expect(controls.values['fx.surround'], 1);
      expect(host.profiles[_pci], surround51Profile);
      expect(host.def, endsWith('analog-surround-51'));
    });

    test('turning the virtual one on turns the card\'s Surround off, and the virtual graph goes to the stereo sink', () async {
      hw.set('fx.surround', 1);
      await serial.idle;
      vs.set('vsurround.enable', 1);
      await serial.idle;
      expect(controls.values['fx.surround'], 0);
      expect(host.profiles[_pci], _stereo);
      expect(host.running, isTrue);
      expect(
        host.started.single,
        contains('alsa_output.pci-0000_0b_00.0.analog-stereo'),
      );
      expect(host.def, virtualSinkName);
      // and turning it off gives the stereo sink back, not the 5.1 one
      vs.set('vsurround.enable', 0);
      await serial.idle;
      expect(host.def, _stereoSink);
    });

    test('quick changes of mind end in the last choice', () async {
      hw.set('fx.surround', 1);
      vs.set('vsurround.enable', 1);
      hw.set('fx.surround', 1);
      await serial.idle;
      expect(controls.values['fx.surround'], 1);
      expect(vs.get('vsurround.enable'), 0);
      expect(host.profiles[_pci], surround51Profile);
      expect(host.running, isFalse);
    });
  });
}

/// A card's ALSA controls as a map.
class _Controls extends Backend {
  _Controls(this.values);
  final Map<String, int> values;
  bool refuse = false;

  @override
  List<Control> controls() => const [];

  @override
  int? get(String id) => values[id];

  @override
  SetResult set(String id, int value) {
    if (refuse) return SetResult.failed;
    final changed = values[id] != value;
    values[id] = value;
    if (changed) onChange?.call(id, value);
    return SetResult.ok;
  }
}

/// A PipeWire that, like the real one, makes the driver flip Output Select whenever the card's profile changes.
class _FlippingPipeWire extends MemoryPipeWire {
  _FlippingPipeWire(this.flip);
  final void Function() flip;

  @override
  Future<bool> setCardProfile(String pciAddress, String profile) async {
    final ok = await super.setCardProfile(pciAddress, profile);
    flip();
    return ok;
  }
}
