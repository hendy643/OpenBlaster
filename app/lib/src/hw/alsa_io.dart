// SPDX-License-Identifier: Apache-2.0

enum RawType { boolean, integer, enumerated, other }

class RawControl {
  RawControl({
    required this.name,
    required this.type,
    this.count = 1,
    this.min = 0,
    this.max = 0,
    this.step = 0,
    this.items = const [],
    this.writable = true,
  });

  final String name;
  final RawType type;
  final int count; // number of values (channels)
  final int min, max, step;
  final List<String> items; // enumerated only
  final bool writable;
}

/// The narrow slice of ALSA the backend needs. The app implements it with libasound (`SndAlsaIo`);
/// the tests and `--demo` with a map, so the mapping logic runs without a sound card.
abstract class AlsaIo {
  List<RawControl> list();

  /// One value per channel, or null if it cannot be read.
  List<int>? read(String name);
  bool write(String name, List<int> values);
  void close() {}
}

/// A card in memory.
class MemoryAlsaIo implements AlsaIo {
  final _controls = <String, RawControl>{};
  final _values = <String, List<int>>{};

  /// Names written, in order.
  final writes = <(String, List<int>)>[];
  bool failWrites = false;
  bool failReads = false;

  void addBool(String name, int value, {bool writable = true}) => _add(
    RawControl(name: name, type: RawType.boolean, writable: writable),
    [value],
  );

  void addInt(
    String name,
    int min,
    int max,
    int step,
    List<int> values, {
    bool writable = true,
  }) => _add(
    RawControl(
      name: name,
      type: RawType.integer,
      count: values.length,
      min: min,
      max: max,
      step: step,
      writable: writable,
    ),
    values,
  );

  void addEnum(String name, List<String> items, int value) => _add(
    RawControl(name: name, type: RawType.enumerated, items: items),
    [value],
  );

  void addOther(String name) =>
      _add(RawControl(name: name, type: RawType.other), [0]);

  void _add(RawControl c, List<int> v) {
    _controls[c.name] = c;
    _values[c.name] = List.of(v);
  }

  /// Another program changed a control.
  void externalSet(String name, List<int> values) =>
      _values[name] = List.of(values);

  List<int>? valuesOf(String name) => _values[name];

  @override
  List<RawControl> list() => _controls.values.toList();

  @override
  List<int>? read(String name) {
    final v = _values[name];
    if (failReads || v == null || _controls[name]!.type == RawType.other)
      return null;
    return List.of(v);
  }

  @override
  bool write(String name, List<int> values) {
    final c = _controls[name];
    if (failWrites || c == null || values.length != c.count) return false;
    writes.add((name, List.of(values)));
    _values[name] = List.of(values);
    return true;
  }

  @override
  void close() {}
}

/// A made-up AE-5 Plus for `--demo` and the tests: every control the catalogue knows.
MemoryAlsaIo makeDemoCard() {
  final c = MemoryAlsaIo();
  c.addInt('Master Playback Volume', 0, 99, 0, [50]);
  c.addBool('Master Playback Switch', 1);
  c.addEnum('Output Select', ['Speakers', 'Headphone'], 0);
  c.addBool('HP/Speaker Auto Detect Playback Switch', 0);
  c.addEnum('AE-5: Headphone Gain', [
    'Low (16-31  Ohms)',
    'Medium (32-149  Ohms)',
    'High (150-600  Ohms)',
  ], 0);
  c.addEnum('AE-5: Sound Filter', [
    'Slow Roll Off',
    'Minimum Phase',
    'Fast Roll Off',
  ], 0);
  c.addEnum('Surround Channel Config', ['2.0', '2.1', '4.0', '4.1', '5.1'], 0);
  c.addBool('Full-Range Front Speakers', 1);
  c.addBool('Full-Range Rear Speakers', 1);
  c.addBool('Bass Redirection', 0);
  c.addInt('Bass Redirection Crossover', 1, 100, 1, [50]);
  c.addEnum('Input Source', ['Microphone', 'Line In', 'Front Microphone'], 0);
  c.addEnum('Mic Boost Capture Switch', ['0 dB', '10 dB', '20 dB', '30 dB'], 0);
  c.addInt('Capture Volume', 0, 99, 0, [90, 90]);
  c.addBool('Capture Switch', 1);
  c.addBool('Enable OutFX Playback Switch', 1);
  for (final (name, level) in [
    ('Surround', 50),
    ('Crystalizer', 65),
    ('Dialog Plus', 50),
    ('Smart Volume', 50),
    ('X-Bass', 50),
  ]) {
    c.addBool('FX: $name Playback Switch', 0);
    c.addInt('FX: $name Playback Volume', 0, 100, 1, [level]);
  }
  c.addEnum('FX: Smart Volume Setting', ['Normal', 'Loud', 'Night'], 0);
  c.addInt('FX: X-Bass Crossover Playback Volume', 1, 100, 1, [50]);
  c.addBool('FX: Equalizer Playback Switch', 0);
  c.addEnum('FX: Equalizer Preset Switch', [
    'Flat',
    'Acoustic',
    'Classical',
    'Country',
    'Dance',
    'Jazz',
    'Pop',
    'Rock',
    'Vocal',
    'Custom',
  ], 0);
  for (var band = 0; band < 10; band++) {
    c.addInt('EQ Band$band Playback Volume', 0, 48, 1, [24]);
  }
  c.addBool('Enable InFX Capture Switch', 0);
  c.addBool('FX: Voice Focus Capture Switch', 0);
  c.addInt('Wedge Angle Capture Volume', 20, 180, 1, [40]);
  c.addBool('FX: Noise Reduction Capture Switch', 0);
  c.addBool('FX: Mic SVM Capture Switch', 0);
  c.addInt('SVM Level Capture Volume', 0, 100, 1, [50]);
  c.addEnum('VoiceFX Capture Switch', [
    'Neutral',
    'Female2Male',
    'Male2Female',
    'Deep',
    'Chipmunk',
  ], 0);
  return c;
}
