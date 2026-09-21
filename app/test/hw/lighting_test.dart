// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/apa102.dart';
import 'package:openblaster/src/hw/backend.dart';
import 'package:openblaster/src/hw/bar2.dart';
import 'package:openblaster/src/hw/color.dart';
import 'package:openblaster/src/hw/led_port.dart';
import 'package:openblaster/src/hw/lighting_backend.dart';
import 'package:openblaster/src/hw/renderer.dart';
import 'package:openblaster/src/hw/settings.dart';
import 'package:openblaster/src/hw/store.dart';
import 'package:openblaster/src/models.dart';

const red = Rgb(255, 0, 0), green = Rgb(0, 255, 0), blue = Rgb(0, 0, 255);
const yellow = Rgb(255, 255, 0), cyan = Rgb(0, 255, 255), black = Rgb(0, 0, 0);

Matcher near(Rgb e, [int tol = 1]) => predicate<Rgb>(
  (a) =>
      (a.r - e.r).abs() <= tol &&
      (a.g - e.g).abs() <= tol &&
      (a.b - e.b).abs() <= tol,
  'is within $tol of $e',
);

// Five distinct colours at full brightness and one cycle a second, so a time in ms is a phase in permille.
Settings rainbow(
  LightPattern p, [
  LightDirection d = LightDirection.leftToRight,
]) => Settings(
  pattern: p,
  direction: d,
  speed: 60,
  brightness: 100,
  colors: const [red, green, blue, yellow, cyan],
);

void main() {
  group('colour', () {
    test('an integer round-trips', () {
      expect(Rgb.fromInt(0x1e88e5), const Rgb(0x1e, 0x88, 0xe5));
      expect(const Rgb(0x1e, 0x88, 0xe5).toInt(), 0x1e88e5);
      expect(Rgb.fromInt(0xffffff).toInt(), 0xffffff);
    });
    test('mix blends and clamps t', () {
      expect(mix(red, blue, 0), red);
      expect(mix(red, blue, 1), blue);
      expect(mix(red, blue, 0.5), near(const Rgb(128, 0, 128)));
      expect(mix(red, blue, -3), red);
      expect(mix(red, blue, 9), blue);
    });
    test('scale is clamped', () {
      expect(scale(const Rgb(100, 200, 50), 0.5), const Rgb(50, 100, 25));
      expect(scale(const Rgb(100, 200, 50), 0), black);
      expect(scale(const Rgb(100, 200, 50), 5), const Rgb(100, 200, 50));
    });
    test('hsv primaries, greys and wrapping', () {
      expect(fromHsv(0, 1, 1), red);
      expect(fromHsv(120, 1, 1), green);
      expect(fromHsv(240, 1, 1), blue);
      expect(fromHsv(60, 1, 1), yellow);
      expect(fromHsv(180, 1, 1), cyan);
      expect(fromHsv(77, 0, 1), const Rgb(255, 255, 255));
      expect(fromHsv(77, 1, 0), black);
      expect(fromHsv(-120, 1, 1), blue);
      expect(fromHsv(480, 1, 1), green);
    });
  });

  group('settings', () {
    test('the defaults are lit and static', () {
      const s = Settings();
      expect(s.enabled, isTrue);
      expect(s.pattern, LightPattern.solid);
      expect(s.brightness, greaterThan(0));
    });
    test('they round-trip through text', () {
      final s = const Settings().copyWith(
        enabled: false,
        pattern: LightPattern.aurora,
        direction: LightDirection.rightToLeftBounce,
        speed: 77,
        brightness: 12,
        colors: const [red, green, blue, yellow, Rgb(1, 2, 3)],
      );
      expect(Settings.parse(s.serialize()), s);
      for (final p in LightPattern.values) {
        for (final d in LightDirection.values) {
          final x = Settings(pattern: p, direction: d);
          expect(Settings.parse(x.serialize()), x);
        }
      }
    });
    test('an empty or garbage file gives the defaults', () {
      expect(Settings.parse(''), const Settings());
      expect(Settings.parse('\n\n'), const Settings());
      expect(Settings.parse('not a settings file'), const Settings());
      expect(Settings.parse('\u0000ÿ\u0001=\u0002\n'), const Settings());
    });
    test('a bad value keeps its default and the rest still apply', () {
      const d = Settings();
      final s = Settings.parse(
        'pattern=disco\nspeed=0\nbrightness=101\ncolor1=zzzzzz\ncolor2=1234567\nenabled=2\n'
        'speed=-4\ndirection=\nbrightness=42\n',
      );
      expect(s.pattern, d.pattern);
      expect(s.speed, d.speed);
      expect(s.colors[0], d.colors[0]);
      expect(s.colors[1], d.colors[1]);
      expect(s.enabled, d.enabled);
      expect(s.direction, d.direction);
      expect(s.brightness, 42);
    });
    test('limits are inclusive', () {
      expect(Settings.parse('speed=1\nbrightness=0\n').speed, kMinSpeed);
      expect(Settings.parse('speed=120\nbrightness=100\n').speed, kMaxSpeed);
      expect(Settings.parse('speed=121\n').speed, const Settings().speed);
    });
    test('unknown keys and colour slots outside 1..5 are ignored', () {
      final s = Settings.parse(
        'future=1\ncolor6=ff0000\ncolor0=ff0000\ncolor=ff0000\ncolor3=00ff00\n',
      );
      expect(s.colors[2], green);
      expect(s.colors[0], const Settings().colors[0]);
    });
    test('a short colour is read', () {
      expect(
        Settings.parse('color1=fff\n').colors[0],
        const Rgb(0, 0x0f, 0xff),
      );
    });
  });

  group('renderer', () {
    test('disabled or dark is black', () {
      expect(
        render(rainbow(LightPattern.wave).copyWith(enabled: false), 123),
        everyElement(black),
      );
      expect(
        render(rainbow(LightPattern.wave).copyWith(brightness: 0), 123),
        everyElement(black),
      );
    });
    test('static shows each LED its own colour at any time', () {
      for (final t in [0, 1, 333, 999, 123456789]) {
        expect(render(rainbow(LightPattern.solid), t), [
          red,
          green,
          blue,
          yellow,
          cyan,
        ]);
      }
    });
    test('brightness scales the channels', () {
      final f = render(rainbow(LightPattern.solid).copyWith(brightness: 50), 0);
      expect(f[0], near(const Rgb(128, 0, 0)));
      expect(f[3], near(const Rgb(128, 128, 0)));
    });
    test('pulsate breathes from nearly off to full', () {
      final s = rainbow(LightPattern.pulsate);
      expect(render(s, 0)[0], near(const Rgb(20, 0, 0)));
      expect(render(s, 500)[0], near(red));
      expect(render(s, 500)[2], near(blue));
      expect(render(s, 1000)[0], near(render(s, 0)[0]));
    });
    test('colour cycle moves all LEDs through the colours together', () {
      final s = rainbow(LightPattern.colourCycle);
      expect(render(s, 0), everyElement(red));
      expect(render(s, 200), everyElement(near(green)));
      expect(render(s, 100), everyElement(near(const Rgb(128, 128, 0))));
    });
    test('wave travels with its direction', () {
      final f = render(rainbow(LightPattern.wave), 200);
      expect(f[1], near(red));
      expect(f[2], near(green));
      expect(f[0], near(cyan));
      final b = render(
        rainbow(LightPattern.wave, LightDirection.rightToLeft),
        200,
      );
      expect(b[0], near(green));
      expect(b[1], near(blue));
      expect(b[4], near(red));
    });
    test('bouncing goes there and back again', () {
      final s = rainbow(LightPattern.wave, LightDirection.leftToRightBounce);
      final q = render(s, 250), tq = render(s, 750);
      for (var i = 0; i < kBuiltInLeds; i++) {
        expect(q[i], near(tq[i]));
        expect(render(s, 0)[i], near(render(s, 1000)[i]));
      }
      expect(render(s, 0)[1], isNot(near(q[1], 5)));
      final loop = rainbow(LightPattern.wave);
      expect(render(loop, 250)[1], isNot(near(render(loop, 750)[1], 5)));
    });
    test('double speed runs the same animation twice as fast', () {
      for (final p in LightPattern.values) {
        final slow = rainbow(p).copyWith(speed: 30),
            fast = slow.copyWith(speed: 60);
        for (final t in [0, 137, 500, 1901]) {
          final a = render(slow, 2 * t), b = render(fast, t);
          for (var i = 0; i < kBuiltInLeds; i++) {
            expect(a[i], near(b[i]), reason: '$p $t');
          }
        }
      }
    });
    test('every pattern repeats after one period', () {
      for (final p in LightPattern.values) {
        for (final d in LightDirection.values) {
          final s = rainbow(p, d);
          for (final t in [0, 77, 431, 999]) {
            final a = render(s, t), b = render(s, t + 1000);
            for (var i = 0; i < kBuiltInLeds; i++) {
              expect(a[i], near(b[i]), reason: '$p $d $t');
            }
          }
        }
      }
    });
    test(
      'mood and aurora are deterministic and stay within the brightness',
      () {
        for (final p in [LightPattern.mood, LightPattern.aurora]) {
          final s = rainbow(p).copyWith(brightness: 40);
          for (var t = 0; t < 3000; t += 97) {
            expect(render(s, t), render(s, t));
            for (final c in render(s, t)) {
              expect(
                [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b),
                lessThanOrEqualTo(102),
              );
            }
          }
        }
        final f = render(rainbow(LightPattern.mood), 100);
        expect(f[0] == f[1] && f[1] == f[2] && f[2] == f[3], isFalse);
      },
    );
    test('huge and negative clocks are fine', () {
      expect(
        render(rainbow(LightPattern.wave), 4000000000000)[0],
        near(render(rainbow(LightPattern.wave), 0)[0]),
      );
      expect(() => render(rainbow(LightPattern.wave), -12345), returnsNormally);
    });
  });

  group('wire format', () {
    test('a red frame is the bytes led_test sent to the real card', () {
      final expected = [
        0,
        0,
        0,
        0,
        for (var i = 0; i < 5; i++) ...[0xff, 0, 0, 0xff],
        0xff,
        0xff,
        0xff,
        0xff,
      ];
      expect(encodeFrame(List.filled(5, red)), expected);
    });
    test('colours go out blue, green, red', () {
      final f = List.filled(5, black)..[0] = const Rgb(1, 2, 3);
      expect(encodeFrame(f).sublist(4, 8), [0xff, 3, 2, 1]);
    });
  });

  group('led port', () {
    late MemoryBar2 bar;
    late LedPort port;
    setUp(() {
      bar = MemoryBar2()..regs[LedPort.kEnable] = 0x0c;
      port = LedPort(bar);
    });

    test('the strip receives exactly the encoded frame', () {
      final f = [red, green, blue, yellow, cyan];
      expect(port.show(f), isTrue);
      expect(bar.received, encodeFrame(f));
      expect(bar.bitsLog, hasLength(28 * 8));
    });
    test('bits go out most significant first on the rising clock edge', () {
      final f = List.filled(5, black)..[0] = const Rgb(0x80, 0x01, 0);
      port.show(f);
      const first = (4 + 1) * 8;
      expect(bar.bitsLog.sublist(first, first + 8), [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]); // blue
      expect(bar.bitsLog.sublist(first + 8, first + 16), [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
      ]); // green
      expect(bar.bitsLog.sublist(first + 16, first + 24), [
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]); // red
    });
    test('only the two verified registers are touched, and only pins 2 and 3 driven', () {
      port.show(List.filled(5, red));
      for (final a in bar.accesses) {
        expect(
          a.offset == LedPort.kPort || a.offset == LedPort.kEnable,
          isTrue,
          reason: '${a.offset}',
        );
        if (a.write && a.offset == LedPort.kPort) {
          expect(a.width, 16);
          expect([
            LedPort.kDataPin,
            LedPort.kClockPin,
          ], contains(a.value & 0xff));
          expect(a.value & ~0x1ff, 0);
        }
        expect(a.write && a.offset == 0x100, isFalse);
      }
    });
    test('every port write is read back', () {
      port.show(List.filled(5, red));
      var writes = 0;
      for (var i = 0; i < bar.accesses.length; i++) {
        final a = bar.accesses[i];
        if (a.offset == LedPort.kPort && a.write) {
          writes++;
          expect(bar.accesses[i + 1].write, isFalse);
          expect(bar.accesses[i + 1].offset, LedPort.kPort);
        }
      }
      expect(writes, greaterThan(28 * 8 * 3));
    });
    test(
      'the pins are enabled only when they are not, and others are kept',
      () {
        port.show(List.filled(5, black));
        expect(
          bar.accesses.where((a) => a.write && a.offset == LedPort.kEnable),
          isEmpty,
        );
        final other = MemoryBar2()..regs[LedPort.kEnable] = 0x03;
        LedPort(other).show(List.filled(5, black));
        expect(other.regs[LedPort.kEnable], 0x0f);
      },
    );
    test('setup happens once and both pins end low', () {
      final b = MemoryBar2();
      final p = LedPort(b);
      p.show(List.filled(5, red));
      p.show(List.filled(5, blue));
      expect(
        b.accesses.where((a) => a.write && a.offset == LedPort.kEnable),
        hasLength(1),
      );
      expect(b.level[LedPort.kDataPin], isFalse);
      expect(b.level[LedPort.kClockPin], isFalse);
      expect(b.received, hasLength(56));
    });
  });

  group('lighting backend', () {
    late _Sink sink;
    late MemoryStore store;
    late LightingBackend b;
    setUp(() {
      sink = _Sink();
      store = MemoryStore();
      b = LightingBackend(sink, store);
    });
    Control info(String id) => b.controls().firstWhere((c) => c.id == id);

    test('the controls are on the Lighting page in order', () {
      expect(b.controls().map((c) => c.id), [
        'lighting.enable',
        'lighting.pattern',
        'lighting.direction',
        'lighting.speed',
        'lighting.brightness',
        'lighting.color1',
        'lighting.color2',
        'lighting.color3',
        'lighting.color4',
        'lighting.color5',
      ]);
      expect(b.controls().map((c) => c.group), everyElement('Lighting'));
    });
    test('kinds, ranges and choices', () {
      expect(info('lighting.enable').kind, ControlKind.toggle);
      expect(
        info('lighting.pattern').choices,
        hasLength(LightPattern.values.length),
      );
      expect(
        info('lighting.direction').choices,
        hasLength(LightDirection.values.length),
      );
      expect(info('lighting.speed').min, kMinSpeed);
      expect(info('lighting.speed').max, kMaxSpeed);
      expect(info('lighting.color3').kind, ControlKind.color);
      expect(info('lighting.color3').max, 0xffffff);
    });
    test('values start at the defaults, and controls carry them', () {
      expect(b.get('lighting.enable'), 1);
      expect(b.get('lighting.speed'), const Settings().speed);
      expect(info('lighting.brightness').value, const Settings().brightness);
      for (final id in ['lighting.nope', 'lighting.color6', 'lighting.color']) {
        expect(b.get(id), isNull);
      }
    });
    test('every control can be set and read back', () {
      for (final (id, v) in [
        ('lighting.enable', 0),
        ('lighting.pattern', 3),
        ('lighting.direction', 2),
        ('lighting.speed', 99),
        ('lighting.brightness', 7),
        ('lighting.color1', 0xff0000),
        ('lighting.color5', 0x00ff00),
      ]) {
        expect(b.set(id, v), SetResult.ok, reason: id);
        expect(b.get(id), v, reason: id);
      }
    });
    test('out of range is refused and changes nothing', () {
      for (final (id, v) in [
        ('lighting.enable', 2),
        ('lighting.enable', -1),
        ('lighting.pattern', 6),
        ('lighting.direction', 4),
        ('lighting.speed', 0),
        ('lighting.speed', 121),
        ('lighting.brightness', 101),
        ('lighting.brightness', -1),
        ('lighting.color2', -1),
        ('lighting.color2', 0x1000000),
      ]) {
        final before = b.get(id);
        expect(b.set(id, v), SetResult.outOfRange, reason: '$id=$v');
        expect(b.get(id), before);
      }
      expect(b.set('lighting.nope', 1), SetResult.unknownControl);
      expect(b.set('volume.master', 1), SetResult.unknownControl);
      b.flush();
      expect(store.saves, 0);
    });
    test('a change is announced but a repeat is not', () {
      final seen = <(String, int)>[];
      b.onChange = (id, v) => seen.add((id, v));
      b.set('lighting.brightness', 30);
      b.set('lighting.brightness', 30);
      expect(seen, [('lighting.brightness', 30)]);
    });
    test('settings are saved on flush, once per burst, only when changed', () {
      b.flush();
      expect(store.saves, 0);
      b.set('lighting.pattern', 4);
      b.set('lighting.speed', 44);
      b.flush();
      b.flush();
      expect(store.saves, 1);
      expect(Settings.parse(store.text!), b.settings);
    });
    test('a failed save is retried on the next flush', () {
      store.failSaves = true;
      b.set('lighting.pattern', 2);
      b.flush();
      b.flush();
      expect(store.saves, 2);
      store.failSaves = false;
      b.flush();
      b.flush();
      expect(store.saves, 3);
    });
    test('settings survive a restart, and damage gives the defaults', () {
      b.set('lighting.pattern', 5);
      b.set('lighting.color4', 0x123456);
      b.set('lighting.enable', 0);
      b.flush();
      final again = LightingBackend(_Sink(), MemoryStore()..text = store.text);
      expect(again.get('lighting.pattern'), 5);
      expect(again.get('lighting.color4'), 0x123456);
      expect(again.get('lighting.enable'), 0);
      final broken = LightingBackend(
        _Sink(),
        MemoryStore()..text = 'ÿ garbage\npattern=??\n',
      );
      expect(broken.get('lighting.pattern'), const Settings().pattern.index);
    });
    test('the first tick shows a frame and an unchanged one is not resent', () {
      b.tick(1000);
      expect(sink.frames, hasLength(1));
      expect(sink.frames[0], render(b.settings, 1000));
      b.tick(1100);
      expect(sink.frames, hasLength(1));
    });
    test('a change is shown on the next tick', () {
      b.tick(0);
      b.set('lighting.color1', 0xff0000);
      b.tick(10);
      expect(sink.frames, hasLength(2));
      expect(
        sink.frames.last[0],
        scale(red, 0.6),
      ); // at the default 60% brightness
    });
    test('disabled lighting shows black', () {
      b.set('lighting.enable', 0);
      b.tick(0);
      expect(sink.frames.single, everyElement(black));
    });
    test('an animation sends a frame whenever the frame changes', () {
      b.set('lighting.pattern', LightPattern.colourCycle.index);
      b.set('lighting.color1', 0xff0000);
      b.set('lighting.color2', 0x00ff00);
      for (var t = 0; t < 1000; t += 33) {
        b.tick(t);
      }
      expect(sink.frames.length, greaterThan(10));
    });
    test(
      'a static frame is resent periodically in case the card forgot it',
      () {
        b.tick(0);
        b.tick(LightingBackend.refreshMs - 1);
        expect(sink.frames, hasLength(1));
        b.tick(LightingBackend.refreshMs);
        expect(sink.frames, hasLength(2));
        b.tick(LightingBackend.refreshMs + 10);
        expect(sink.frames, hasLength(2));
      },
    );
    test('a failed show is retried on the next tick', () {
      sink.ok = false;
      b.tick(0);
      b.tick(10);
      expect(sink.attempts, 2);
      sink.ok = true;
      b.tick(20);
      expect(sink.frames, hasLength(1));
    });
    test('the timer runs fast only while something moves', () {
      expect(b.tickIntervalMs, 250);
      b.set('lighting.pattern', LightPattern.wave.index);
      expect(b.tickIntervalMs, 33);
      b.set('lighting.enable', 0);
      expect(b.tickIntervalMs, 250);
      b.set('lighting.enable', 1);
      b.set('lighting.brightness', 0);
      expect(b.tickIntervalMs, 250);
    });
  });

  group('composite', () {
    late _Stub one, two;
    late CompositeBackend c;
    setUp(() {
      one = _Stub('one');
      two = _Stub('two', interval: 33);
      c = CompositeBackend([one, two]);
    });
    test('controls are each backend\'s in order without duplicates', () {
      expect(c.controls().map((x) => x.id), ['one.a', 'shared.x', 'two.a']);
      expect(c.controls()[1].label, 'one shared');
    });
    test('reads and writes go to the owner', () {
      expect(c.get('shared.x'), 1);
      expect(c.get('two.a'), 5);
      expect(c.set('shared.x', 1), SetResult.ok);
      expect(c.set('two.a', 3), SetResult.ok);
      expect(one.sets, hasLength(1));
      expect(two.sets, [('two.a', 3)]);
      expect(c.get('nope'), isNull);
      expect(c.set('nope', 1), SetResult.unknownControl);
    });
    test('changes from any backend reach the handler', () {
      final seen = <String>[];
      c.onChange = (id, _) => seen.add(id);
      one.onChange!('one.a', 1);
      two.onChange!('two.a', 2);
      expect(seen, ['one.a', 'two.a']);
    });
    test('poll, tick and flush reach every backend', () {
      c.poll();
      c.tick(1234);
      c.flush();
      expect(one.polled + two.polled, 2);
      expect(one.ticks, [1234]);
      expect(two.ticks, [1234]);
      expect(one.flushed + two.flushed, 2);
    });
    test('the interval is the smallest asked for', () {
      expect(c.tickIntervalMs, 33);
      expect(
        CompositeBackend([
          _Stub('a', interval: 250),
          _Stub('b', interval: 33),
          _Stub('c'),
        ]).tickIntervalMs,
        33,
      );
      expect(CompositeBackend([_Stub('a')]).tickIntervalMs, 0);
    });
  });
}

class _Sink implements LedSink {
  final frames = <Frame>[];
  int attempts = 0;
  bool ok = true;
  @override
  bool show(Frame f) {
    attempts++;
    if (!ok) return false;
    frames.add(f);
    return true;
  }
}

class _Stub extends Backend {
  _Stub(this.prefix, {this.interval = 0});
  final String prefix;
  final int interval;
  final sets = <(String, int)>[];
  final ticks = <int>[];
  int polled = 0, flushed = 0;

  @override
  List<Control> controls() => [
    Control(
      id: '$prefix.a',
      group: 'G',
      label: '${prefix}A',
      kind: ControlKind.range,
      max: 9,
    ),
    Control(
      id: 'shared.x',
      group: 'G',
      label: '$prefix shared',
      kind: ControlKind.toggle,
    ),
  ];
  @override
  int? get(String id) => id == 'shared.x' ? (prefix == 'one' ? 1 : 2) : 5;
  @override
  SetResult set(String id, int v) {
    sets.add((id, v));
    return SetResult.ok;
  }

  @override
  void poll() => polled++;
  @override
  int get tickIntervalMs => interval;
  @override
  void tick(int t) => ticks.add(t);
  @override
  void flush() => flushed++;
}
