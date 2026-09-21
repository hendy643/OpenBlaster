// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/backend.dart';
import 'package:openblaster/src/hw/store.dart';
import 'package:openblaster/src/hw/virtual_surround.dart';
import 'package:openblaster/src/hw/virtual_surround_backend.dart';

const _kemar = Hrir(
  '/usr/share/libmysofa/default.sofa',
  HrirKind.sofa,
  'KEMAR',
);
const _atmos = Hrir(
  '/h/atmos.wav',
  HrirKind.hesuvi,
  'Dolby Atmos for Headphones',
);
const _profiles = [_atmos, _kemar];

/// The first 44 bytes of a WAV with [channels] channels (enough for the header check).
Uint8List wavHeader(int channels) {
  final b = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, channels, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('labels', () {
    test('the products are named as the user knows them', () {
      for (final (path, label) in [
        ('atmos.wav', 'Dolby Atmos for Headphones'),
        ('atmos-.wav', 'Dolby Atmos for Headphones (no reverb)'),
        ('cmss_game/hesuvi.wav', 'CMSS-3D Game'),
        ('cmss_game-/hesuvi.wav', 'CMSS-3D Game (no reverb)'),
        ('cmss_ent.wav', 'CMSS-3D Entertainment'),
        ('cmss_rx+.wav', 'CMSS-3D'),
        ('dtshx.wav', 'DTS Headphone:X'),
        ('dtshx-/x.wav', 'DTS Headphone:X (no reverb)'),
        ('sbx33.wav', 'SBX Surround 33%'),
        ('sbx67-.wav', 'SBX Surround 67% (no reverb)'),
        ('SBX100/HeSuVi.wav', 'SBX Surround 100%'),
        ('DolbyAccess.wav', 'Dolby Access'),
        ('something else.wav', 'something else'),
        ('deep/dir/my.hrtf.sofa', 'my.hrtf'),
        ('A3D/A3D.wav', 'Aureal A3D'),
        ('Razer/razer.wav', 'Razer Surround'),
        ('Steam/SteamAudio.wav', 'Steam Audio'),
        (
          'Dolby/atmosgame-noeq-3.14.67.wav',
          'Dolby Atmos - Game (no EQ) v3.14.67',
        ),
        ('Dolby/atmosgameperf.wav', 'Dolby Atmos - Game (performance)'),
        ('Dolby/atmosvoice.wav', 'Dolby Atmos - Voice'),
        (
          'DTS/DTSHX-GenericEarbuds-Spacious-R0.14.wav',
          'DTS Headphone:X - Earbuds, Spacious (R0.14)',
        ),
        ('DTS/DTSHX-NoEQ-Balanced.wav', 'DTS Headphone:X - Balanced, No EQ'),
        ('DTS/DTSVirtualX-for-speakers.wav', 'DTS Virtual:X for speakers'),
        ('SoundBlaster/sbc80.wav', 'Sound Blaster SBC 80%'),
      ]) {
        expect(profileLabel(path), label, reason: path);
      }
    });
  });

  group('filter-chain configuration', () {
    String conf(Hrir h, {String sink = 'alsa_output.x'}) =>
        buildFilterChainConf(hrir: h, targetSink: sink);

    test(
      'the sink has the eight 7.1 channels in order, whatever the profile',
      () {
        for (final h in _profiles) {
          final c = conf(h);
          expect(c, contains('audio.channels = 8'));
          expect(c, contains('audio.position = [ FL FR FC LFE RL RR SL SR ]'));
          expect(c, contains('outputs = [ "mixL:Out" "mixR:Out" ]'));
          expect(c, contains('node.name = $virtualSinkName'));
          expect(c, contains('media.class = Audio/Sink'));
        }
      },
    );

    test('a HeSuVi WAV becomes convolvers on its 14 channels, both ears of every speaker', () {
      final c = conf(_atmos);
      expect(c, isNot(contains('type = sofa')));
      expect('label = convolver'.allMatches(c), hasLength(16));
      // the HeSuVi order: FL 0/1, SL 2/3, RL 4/5, FC 6/13, FR 8/7 (its ears crossed), SR 10/9, RR 12/11
      for (final (name, ch) in [
        ('convFL_L', 0),
        ('convFL_R', 1),
        ('convSL_L', 2),
        ('convSL_R', 3),
        ('convRL_L', 4),
        ('convRL_R', 5),
        ('convFC_L', 6),
        ('convFC_R', 13),
        ('convFR_L', 8),
        ('convFR_R', 7),
        ('convSR_L', 10),
        ('convSR_R', 9),
        ('convRR_L', 12),
        ('convRR_R', 11),
        ('convLFE_L', 6),
        ('convLFE_R', 13),
      ]) {
        expect(
          c,
          contains(
            'name = $name config = { filename = "/h/atmos.wav" channel = $ch }',
          ),
          reason: name,
        );
      }
      expect(
        c,
        contains(
          'inputs = [ "copyFL:In" "copyFR:In" "copyFC:In" "copyLFE:In" "copyRL:In" "copyRR:In" "copySL:In" "copySR:In" ]',
        ),
      );
    });

    test('a 7-channel HeSuVi WAV gives each right ear the mirror speaker\'s left ear', () {
      final c = conf(const Hrir('/h/razer.wav', HrirKind.hesuvi7, 'x'));
      expect('label = convolver'.allMatches(c), hasLength(16));
      for (final (name, ch) in [
        ('convFL_L', 0),
        ('convFL_R', 4),
        ('convFR_L', 4),
        ('convFR_R', 0),
        ('convSL_L', 1),
        ('convSL_R', 5),
        ('convSR_L', 5),
        ('convSR_R', 1),
        ('convRL_L', 2),
        ('convRL_R', 6),
        ('convRR_L', 6),
        ('convRR_R', 2),
        ('convFC_L', 3),
        ('convFC_R', 3),
        ('convLFE_L', 3),
        ('convLFE_R', 3),
      ]) {
        expect(
          c,
          contains(
            'name = $name config = { filename = "/h/razer.wav" channel = $ch }',
          ),
          reason: name,
        );
      }
    });

    test('every mixer input is fed exactly once, left and right', () {
      for (final h in _profiles) {
        final c = conf(h);
        for (var i = 1; i <= 8; i++) {
          expect(
            'input = "mixL:In $i"'.allMatches(c),
            hasLength(1),
            reason: '${h.label} L $i',
          );
          expect(
            'input = "mixR:In $i"'.allMatches(c),
            hasLength(1),
            reason: '${h.label} R $i',
          );
        }
        expect(c, isNot(contains('mixL:In 9')));
      }
    });

    test('a SOFA file becomes a spatializer per speaker with each at its angle; the LFE goes to both ears', () {
      final c = conf(_kemar);
      expect('type = sofa'.allMatches(c), hasLength(7));
      for (final (name, az) in [
        ('FL', 30),
        ('FR', 330),
        ('FC', 0),
        ('SL', 90),
        ('SR', 270),
        ('RL', 150),
        ('RR', 210),
      ]) {
        expect(
          c,
          contains(
            'name = sp$name config = { filename = "/usr/share/libmysofa/default.sofa" } control = { "Azimuth" = $az.0',
          ),
        );
      }
      expect(
        c,
        contains(
          'inputs = [ "spFL:In" "spFR:In" "spFC:In" "copyLFE:In" "spRL:In" "spRR:In" "spSL:In" "spSR:In" ]',
        ),
      );
    });

    test('the output is played to the chosen sink', () {
      final c = conf(
        _atmos,
        sink: 'alsa_output.pci-0000_0b_00.0.analog-stereo',
      );
      expect(
        c,
        contains(
          'target.object = "alsa_output.pci-0000_0b_00.0.analog-stereo"',
        ),
      );
      expect(c, contains('node.passive = true'));
    });

    test('quotes in a file name cannot break out of the configuration', () {
      final c = conf(const Hrir('/x/a"b\\c.wav', HrirKind.hesuvi, 'x'));
      expect(c, contains(r'filename = "/x/a\"b\\c.wav"'));
    });
  });

  group('HRIR discovery', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('ob-hrir'));
    tearDown(() => root.deleteSync(recursive: true));
    File file(String rel, [List<int> bytes = const []]) {
      final f = File('${root.path}/$rel')..createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return f;
    }

    test('finds HeSuVi WAVs (14 channels) and SOFA files, in nested folders, labelled and sorted', () {
      file('sbx100/HeSuVi/sbx100.wav', wavHeader(14));
      file('atmos.wav', wavHeader(14));
      file('cmss_game/x.wav', wavHeader(14));
      file('lib/a.sofa');
      final found = findHrirs(dirs: [root.path]);
      expect(found.map((h) => h.label), [
        'CMSS-3D Game',
        'SBX Surround 100%',
        'Dolby Atmos for Headphones',
        'a',
      ]);
      expect(found.map((h) => h.kind), [
        HrirKind.hesuvi,
        HrirKind.hesuvi,
        HrirKind.hesuvi,
        HrirKind.sofa,
      ]);
    });

    test('a WAV that is not 14 channels, not a WAV at all, or other files are skipped', () {
      file('stereo.wav', wavHeader(2));
      file('junk.wav', [1, 2, 3]);
      file('empty.wav');
      file('notes.txt');
      expect(findHrirs(dirs: [root.path]), isEmpty);
    });

    test('a symlink to a file already found is listed once, a dead link is skipped, a missing directory is fine', () {
      final real = file('a/real.wav', wavHeader(14));
      Link('${root.path}/a/copy.wav').createSync(real.path);
      Link('${root.path}/a/dead.wav').createSync('${root.path}/a/nothing.wav');
      expect(findHrirs(dirs: [root.path, '${root.path}/none']), hasLength(1));
    });

    test(
      'two files with the same label are told apart by their file names',
      () {
        file('atmos/48k.wav', wavHeader(14));
        file('atmos/44k.wav', wavHeader(14));
        final labels = findHrirs(dirs: [root.path])
            .map((h) => h.label)
            .toList();
        expect(labels, [
          'Dolby Atmos for Headphones (44k.wav)',
          'Dolby Atmos for Headphones (48k.wav)',
        ]);
      },
    );
  });

  group('backend', () {
    late MemoryPipeWire host;
    late MemoryStore store;
    String? target;
    VirtualSurroundBackend make({List<Hrir> profiles = _profiles}) {
      return VirtualSurroundBackend(
        host: host,
        store: store,
        profiles: profiles,
        targetSink: () => target,
      );
    }

    setUp(() {
      host = MemoryPipeWire();
      store = MemoryStore();
      target = 'alsa_output.pci.analog-stereo';
    });

    test('it lists two controls on the Virtual surround page, off by default, one choice per profile', () {
      final b = make();
      expect(b.controls().map((c) => c.id), [
        'vsurround.enable',
        'vsurround.profile',
      ]);
      expect(
        b.controls().map((c) => c.group),
        everyElement('Virtual surround'),
      );
      expect(b.get('vsurround.enable'), 0);
      expect(b.controls()[1].choices, ['Dolby Atmos for Headphones', 'KEMAR']);
      expect(host.started, isEmpty);
    });

    test('turning it on starts the graph on the card\'s sink and makes it the default output', () async {
      final b = make();
      expect(b.set('vsurround.enable', 1), SetResult.ok);
      await b.idle;
      expect(host.started, hasLength(1));
      expect(
        host.started.single,
        contains('target.object = "alsa_output.pci.analog-stereo"'),
      );
      expect(host.started.single, contains('/h/atmos.wav'));
      expect(host.def, virtualSinkName);
    });

    test(
      'turning it off stops it and gives the previous output back',
      () async {
        final b = make();
        b.set('vsurround.enable', 1);
        await b.idle;
        b.set('vsurround.enable', 0);
        await b.idle;
        expect(host.running, isFalse);
        expect(host.def, 'alsa_output.demo.analog-stereo');
      },
    );

    test(
      'a restart does not remember the virtual sink as the previous output',
      () async {
        final b = make();
        b.set('vsurround.enable', 1);
        await b.idle;
        b.set('vsurround.profile', 1);
        await b.idle;
        b.set('vsurround.enable', 0);
        await b.idle;
        expect(host.def, 'alsa_output.demo.analog-stereo');
      },
    );

    test('choosing another effect restarts a running graph with it, and does nothing while off', () async {
      final b = make();
      b.set('vsurround.profile', 1);
      await b.idle;
      expect(host.started, isEmpty);
      b.set('vsurround.enable', 1);
      await b.idle;
      expect(host.started.single, contains('default.sofa'));
      b.set('vsurround.profile', 0);
      await b.idle;
      expect(host.started, hasLength(2));
      expect(host.started.last, contains('/h/atmos.wav'));
    });

    test('out-of-range and unknown values are refused', () {
      final b = make();
      expect(b.set('vsurround.enable', 2), SetResult.outOfRange);
      expect(b.set('vsurround.profile', 2), SetResult.outOfRange);
      expect(b.set('vsurround.profile', -1), SetResult.outOfRange);
      expect(b.set('vsurround.nope', 1), SetResult.unknownControl);
    });

    test('a failure to start puts the switch back and says so', () async {
      host.failStart = true;
      final b = make();
      final seen = <(String, int)>[];
      b.onChange = (id, v) => seen.add((id, v));
      b.set('vsurround.enable', 1);
      await b.idle;
      expect(b.get('vsurround.enable'), 0);
      expect(seen.last, ('vsurround.enable', 0));
      expect(host.defaultChanges, isEmpty);
    });

    test('no output for the card is a failure too', () async {
      target = null;
      final b = make();
      b.set('vsurround.enable', 1);
      await b.idle;
      expect(b.get('vsurround.enable'), 0);
      expect(host.started, isEmpty);
    });

    test('without any profile it cannot be turned on', () {
      expect(
        make(profiles: const []).set('vsurround.enable', 1),
        SetResult.failed,
      );
    });

    test(
      'the choice survives a restart: it is applied again when the app starts',
      () async {
        final b = make();
        b.set('vsurround.enable', 1);
        b.set('vsurround.profile', 1);
        await b.idle;
        b.flush();

        final host2 = MemoryPipeWire();
        final again = VirtualSurroundBackend(
          host: host2,
          store: store,
          profiles: _profiles,
          targetSink: () => target,
        );
        await again.idle;
        expect(again.get('vsurround.enable'), 1);
        expect(again.get('vsurround.profile'), 1);
        expect(host2.started.single, contains('default.sofa'));
      },
    );

    test(
      'what a crash left behind is undone when the app starts with it off',
      () async {
        store.text = 'enabled=0\nprevious_default=alsa_output.old\n';
        final b = make();
        await b.idle;
        expect(host.def, 'alsa_output.old');
        b.flush();
        expect(store.text, contains('previous_default=\n'));
      },
    );

    test('a saved profile that is gone falls back to the first, and junk in the file is ignored', () {
      store.text = 'profile=/nope.wav\nenabled=maybe\nÿ\n=\n';
      final b = make();
      expect(b.get('vsurround.profile'), 0);
      expect(b.get('vsurround.enable'), 0);
    });

    test('settings are saved on flush only when changed', () {
      final b = make();
      b.flush();
      expect(store.saves, 0);
      b.set('vsurround.profile', 1);
      b.flush();
      b.flush();
      expect(store.saves, 1);
    });

    test(
      'closing gives the output back and keeps the choice for next time',
      () async {
        final b = make();
        b.set('vsurround.enable', 1);
        await b.idle;
        b.close();
        expect(host.def, 'alsa_output.demo.analog-stereo');
        expect(store.text, contains('enabled=1'));
      },
    );
  });

  // Creates a real PipeWire sink for a couple of seconds (nothing plays, the default output is untouched).
  test(
    'the real host starts a PipeWire process that hosts the virtual sink',
    () async {
      final dir = Directory.systemTemp.createTempSync('ob-pw');
      addTearDown(() => dir.deleteSync(recursive: true));
      final host = ProcessPipeWire(dir.path);
      final hrir = findHrirs().first;
      final sink = host.sinkFor(
        Directory('/sys/class/sound/card1/device')
            .resolveSymbolicLinksSync()
            .split('/')
            .last,
      );
      expect(sink, isNotNull);
      expect(
        await host.start(buildFilterChainConf(hrir: hrir, targetSink: sink!)),
        isTrue,
      );
      await host.stop();
      expect(
        Process.runSync('pactl', ['list', 'short', 'sinks']).stdout as String,
        isNot(contains(virtualSinkName)),
      );
    },
    skip: Platform.environment['OB_REAL_PIPEWIRE'] == null
        ? 'set OB_REAL_PIPEWIRE=1 to try it against this machine\'s PipeWire'
        : false,
  );
}
