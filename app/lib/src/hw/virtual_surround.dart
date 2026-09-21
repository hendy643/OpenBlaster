// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

/// The virtual sink apps play 5.1/7.1 into; PipeWire turns it into binaural stereo (an HRTF, from a SOFA file)
/// and sends that to the card's own stereo output. The card only ever sees stereo.
const virtualSinkName = 'openblaster_virtual_surround';

/// One speaker of a layout: its PipeWire position name and where it sits, as an azimuth in degrees (0 front,
/// 90 left, 180 behind, 270 right), or null for the subwoofer, which has no direction and goes to both ears.
class Speaker {
  const Speaker(this.position, this.azimuth);
  final String position;
  final int? azimuth;
}

/// The speakers of the virtual sink: 7.1.
const surroundSpeakers = [
  Speaker('FL', 30),
  Speaker('FR', 330),
  Speaker('FC', 0),
  Speaker('LFE', null),
  Speaker('RL', 150),
  Speaker('RR', 210),
  Speaker('SL', 90),
  Speaker('SR', 270),
];

enum HrirKind {
  /// A SOFA file: the HRTF of a head, from which PipeWire's spatializer places each speaker.
  sofa,

  /// A HeSuVi WAV: 14 channels of ready-made impulse responses, one per speaker and ear. The sound of a product
  /// (CMSS-3D, SBX, Dolby Atmos, DTS Headphone:X) is captured in it.
  hesuvi,

  /// A HeSuVi WAV with 7 channels: the left ear's response for each speaker; the right ear's is the mirror
  /// speaker's left ear.
  hesuvi7,
}

class Hrir {
  const Hrir(this.path, this.kind, this.label);
  final String path;
  final HrirKind kind;
  final String label;
}

/// A PipeWire configuration file that hosts one filter-chain: a 7.1 sink whose output is a stereo binaural mix
/// made from [hrir], played to [targetSink]. Run with `pipewire -c FILE`.
String buildFilterChainConf({required Hrir hrir, required String targetSink}) {
  String q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final nodes = <String>[];
  final links = <String>[];
  final file = q(hrir.path);
  final positions = surroundSpeakers.map((s) => s.position).join(' ');
  final inputs = <String>[];

  if (hrir.kind == HrirKind.sofa) {
    final directional = [
      for (final s in surroundSpeakers)
        if (s.azimuth != null) s,
    ];
    for (final s in directional) {
      nodes.add(
        '{ type = sofa label = spatializer name = sp${s.position} '
        'config = { filename = $file } '
        'control = { "Azimuth" = ${s.azimuth}.0 "Elevation" = 0.0 "Radius" = 3.0 } }',
      );
    }
    nodes.addAll([
      '{ type = builtin label = copy name = copyLFE }',
      '{ type = builtin label = mixer name = mixL }',
      '{ type = builtin label = mixer name = mixR }',
    ]);
    for (var i = 0; i < directional.length; i++) {
      final p = directional[i].position;
      links.add('{ output = "sp$p:Out L" input = "mixL:In ${i + 1}" }');
      links.add('{ output = "sp$p:Out R" input = "mixR:In ${i + 1}" }');
    }
    final lfe = directional.length + 1;
    links.add('{ output = "copyLFE:Out" input = "mixL:In $lfe" }');
    links.add('{ output = "copyLFE:Out" input = "mixR:In $lfe" }');
    for (final s in surroundSpeakers) {
      inputs.add(s.azimuth == null ? '"copyLFE:In"' : '"sp${s.position}:In"');
    }
  } else {
    // HeSuVi channel order, 14 channels: FL-L FL-R SL-L SL-R RL-L RL-R FC-L FR-R FR-L SR-R SR-L RR-R RR-L FC-R.
    // 7 channels: the left-ear response of FL SL RL FC FR SR RR; a right ear is the mirror speaker's left ear.
    // The LFE reuses the centre's responses.
    const ir14 = <String, (int, int)>{
      // speaker: (left ear channel, right ear channel)
      'FL': (0, 1),
      'SL': (2, 3),
      'RL': (4, 5),
      'FC': (6, 13),
      'FR': (8, 7),
      'SR': (10, 9),
      'RR': (12, 11),
      'LFE': (6, 13),
    };
    const ir7 = <String, (int, int)>{
      'FL': (0, 4),
      'SL': (1, 5),
      'RL': (2, 6),
      'FC': (3, 3),
      'FR': (4, 0),
      'SR': (5, 1),
      'RR': (6, 2),
      'LFE': (3, 3),
    };
    final ir = hrir.kind == HrirKind.hesuvi7 ? ir7 : ir14;
    nodes.addAll([
      '{ type = builtin label = mixer name = mixL }',
      '{ type = builtin label = mixer name = mixR }',
    ]);
    var n = 0;
    for (final s in surroundSpeakers) {
      final (l, r) = ir[s.position]!;
      n++;
      nodes.add('{ type = builtin label = copy name = copy${s.position} }');
      nodes.add(
        '{ type = builtin label = convolver name = conv${s.position}_L config = { filename = $file channel = $l } }',
      );
      nodes.add(
        '{ type = builtin label = convolver name = conv${s.position}_R config = { filename = $file channel = $r } }',
      );
      links.add(
        '{ output = "copy${s.position}:Out" input = "conv${s.position}_L:In" }',
      );
      links.add(
        '{ output = "copy${s.position}:Out" input = "conv${s.position}_R:In" }',
      );
      links.add('{ output = "conv${s.position}_L:Out" input = "mixL:In $n" }');
      links.add('{ output = "conv${s.position}_R:Out" input = "mixR:In $n" }');
      inputs.add('"copy${s.position}:In"');
    }
  }
  return '''
context.properties = { log.level = 2 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-filter-chain args = {
      node.description = "OpenBlaster Virtual Surround"
      media.name = "OpenBlaster Virtual Surround"
      filter.graph = {
        nodes = [ ${nodes.join(' ')} ]
        links = [ ${links.join(' ')} ]
        inputs = [ ${inputs.join(' ')} ]
        outputs = [ "mixL:Out" "mixR:Out" ]
      }
      capture.props = {
        node.name = $virtualSinkName
        media.class = Audio/Sink
        audio.channels = ${surroundSpeakers.length}
        audio.position = [ $positions ]
      }
      playback.props = {
        node.name = "$virtualSinkName.output"
        node.passive = true
        audio.channels = 2
        audio.position = [ FL FR ]
        target.object = ${q(targetSink)}
      }
  } }
]
''';
}

/// What a profile is called, from where it lies under its directory (folder and file name).
String profileLabel(String relativePath) {
  final p = relativePath.toLowerCase();
  final stem = p.split('/').last.replaceFirst(RegExp(r'\.[a-z0-9]+$'), '');
  final noReverb =
      RegExp(r'(^|[^a-z0-9])(no[ _-]?reverb)|[a-z0-9]-(\.|/|$)').hasMatch(p)
      ? ' (no reverb)'
      : '';
  final version = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(stem);
  final room = RegExp(r'-r(\d+\.\d+)').firstMatch(stem);
  final noEq = stem.contains('noeq');
  final qualifiers =
      '${version == null ? '' : ' v${version[1]}'}${room == null ? '' : ' (R${room[1]})'}$noReverb';

  String? name;
  if (p.contains('a3d')) {
    name = 'Aureal A3D';
  } else if (p.contains('razer')) {
    name = 'Razer Surround';
  } else if (p.contains('steamaudio')) {
    name = 'Steam Audio';
  } else if (p.contains('atmos')) {
    const modes = {
      'game': 'Game',
      'movie': 'Movie',
      'music': 'Music',
      'voice': 'Voice',
      'custom': 'Custom',
    };
    final mode = modes.entries.where((e) => stem.contains(e.key)).firstOrNull;
    name = mode == null
        ? 'Dolby Atmos for Headphones'
        : 'Dolby Atmos - ${mode.value}${stem.contains('perf') ? ' (performance)' : ''}';
    if (noEq) name = '$name (no EQ)';
  } else if (p.contains('dolbyaccess')) {
    name = 'Dolby Access';
  } else if (stem.contains('dtsvirtualx')) {
    name = 'DTS Virtual:X for speakers';
  } else if (p.contains('dtshx') ||
      p.contains('dts') && p.contains('headphone')) {
    final parts = [
      if (stem.contains('earbuds'))
        'Earbuds'
      else if (stem.contains('overear'))
        'Over-ear',
      if (stem.contains('balanced'))
        'Balanced'
      else if (stem.contains('spacious'))
        'Spacious',
      if (noEq) 'No EQ',
    ];
    name = 'DTS Headphone:X${parts.isEmpty ? '' : ' - ${parts.join(', ')}'}';
  } else if (p.contains('cmss_game') || p.contains('cmss-game')) {
    name = 'CMSS-3D Game';
  } else if (p.contains('cmss_ent') || p.contains('cmss-ent')) {
    name = 'CMSS-3D Entertainment';
  } else if (p.contains('cmss')) {
    name = 'CMSS-3D';
  } else if (RegExp(r'sbx[ _-]?(\d+)').firstMatch(p) case final m?) {
    name = 'SBX Surround ${m[1]}%';
  } else if (RegExp(r'sbc[ _-]?(\d+)').firstMatch(p) case final m?) {
    name = 'Sound Blaster SBC ${m[1]}%';
  }
  if (name != null) return '$name$qualifiers';
  final file = relativePath.split('/').last;
  final dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(0, dot) : file;
}

/// The channel count of a WAV (read from its header), or 0 if it is not one.
int wavChannels(File f) {
  try {
    final raf = f.openSync();
    try {
      final h = raf.readSync(24);
      final wav =
          h.length == 24 &&
          String.fromCharCodes(h.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(h.sublist(8, 12)) == 'WAVE';
      return wav ? h[22] | (h[23] << 8) : 0;
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return 0;
  }
}

/// The HRIRs on this machine: HeSuVi WAVs (14 or 7 channels) and SOFA files under `~/.local/share/openblaster/hrtf`
/// and `/usr/share/openblaster/hrtf` (the packages install theirs there), plus the SOFA files of `~/.local/share/sofa` and the system's libmysofa sample.
/// Sorted by label; identical files (links) once.
List<Hrir> findHrirs({List<String>? dirs}) {
  final home = Platform.environment['HOME'];
  final search =
      dirs ??
      [
        if (home != null) '$home/.local/share/openblaster/hrtf',
        '/usr/share/openblaster/hrtf', // what the packages install
        '/usr/local/share/openblaster/hrtf',
        if (home != null) '$home/.local/share/sofa',
        '/usr/share/libmysofa',
        '/usr/share/sofa',
      ];
  final seen = <String>{};
  final out = <Hrir>[];
  for (final d in search) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File && e is! Link) continue;
      final f = File(e.path);
      final lower = f.path.toLowerCase();
      final sofa = lower.endsWith('.sofa');
      if (!sofa && !lower.endsWith('.wav')) continue;
      String real;
      try {
        real = f.resolveSymbolicLinksSync();
      } on FileSystemException {
        continue;
      }
      if (!seen.add(real)) continue;
      final channels = sofa ? 0 : wavChannels(File(real));
      if (!sofa && channels != 14 && channels != 7) continue; // some other WAV
      final rel = f.path.substring(d.length + 1);
      final kind = sofa
          ? HrirKind.sofa
          : (channels == 7 ? HrirKind.hesuvi7 : HrirKind.hesuvi);
      out.add(Hrir(f.path, kind, profileLabel(rel)));
    }
  }
  // the four families first (CMSS-3D, SBX and Sound Blaster, Dolby Atmos, DTS), the plain profile before its variants
  int rank(String label) {
    const order = [
      'CMSS',
      'SBX',
      'Sound Blaster',
      'Dolby Atmos',
      'DTS',
      'Dolby',
    ];
    final i = order.indexWhere(label.startsWith);
    return i < 0 ? order.length : i;
  }

  out.sort((a, b) {
    final r = rank(a.label).compareTo(rank(b.label));
    if (r != 0) return r;
    final l = a.label.length.compareTo(b.label.length);
    return l != 0 ? l : a.label.compareTo(b.label);
  });
  // two files with one label (several sample rates): tell them apart by file name
  final count = <String, int>{};
  for (final h in out) {
    count[h.label] = (count[h.label] ?? 0) + 1;
  }
  return [
    for (final h in out)
      count[h.label]! > 1
          ? Hrir(h.path, h.kind, '${h.label} (${h.path.split('/').last})')
          : h,
  ];
}

/// What the backend needs from PipeWire. The real one runs `pipewire` and `pactl`; the tests use a fake.
abstract class PipeWireHost {
  /// Whether PipeWire (with its pulse layer) is there to use.
  bool get available;

  /// The stereo analog output of the PCI device at [pciAddress] (e.g. 0000:0b:00.0), or null.
  String? sinkFor(String pciAddress);

  /// Runs a PipeWire process hosting [conf]; true once its virtual sink exists. Replaces any earlier one.
  Future<bool> start(String conf);
  Future<void> stop();
  String? defaultSink();
  void setDefaultSink(String name);

  /// A sink's volume in percent (of its first channel), or null.
  int? sinkVolume(String name);
  void setSinkVolume(String name, int percent);
}

/// `pipewire -c FILE` as a child process, `pactl` for the default output.
class ProcessPipeWire implements PipeWireHost {
  ProcessPipeWire(this.runtimeDir);

  /// Where the generated configuration is written.
  final String runtimeDir;
  Process? _child;

  String get _confPath => '$runtimeDir/openblaster-virtual-surround.conf';

  static String? _run(String exe, List<String> args) {
    try {
      final r = Process.runSync(exe, args);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  @override
  bool get available =>
      _run('pipewire', ['--version']) != null &&
      _run('pactl', ['info']) != null;

  @override
  String? sinkFor(String pciAddress) {
    final key = 'pci-${pciAddress.replaceAll(':', '_')}';
    final sinks = [
      for (final line
          in (_run('pactl', ['list', 'short', 'sinks']) ?? '').split('\n'))
        if (line.split('\t').length > 1 && line.split('\t')[1].contains(key))
          line.split('\t')[1],
    ];
    return sinks.where((s) => s.contains('analog-stereo')).firstOrNull ??
        sinks.firstOrNull;
  }

  @override
  Future<bool> start(String conf) async {
    await stop();
    Directory(runtimeDir).createSync(recursive: true);
    File(_confPath).writeAsStringSync(conf);
    try {
      _child = await Process.start('pipewire', ['-c', _confPath]);
    } on ProcessException {
      return false;
    }
    _child!.stdout.drain<void>();
    _child!.stderr.drain<void>();
    for (var i = 0; i < 40; i++) {
      // up to 4 s for the sink to appear
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if ((_run('pactl', ['list', 'short', 'sinks']) ?? '').contains(
        virtualSinkName,
      ))
        return true;
    }
    await stop();
    return false;
  }

  @override
  Future<void> stop() async {
    _child?.kill();
    _child = null;
    // one left over by an earlier run of the app (a crash, or Quit)
    _run('pkill', ['-f', 'openblaster-virtual-surround.conf']);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  String? defaultSink() => _run('pactl', ['get-default-sink']);

  @override
  void setDefaultSink(String name) => _run('pactl', ['set-default-sink', name]);

  @override
  int? sinkVolume(String name) {
    final m = RegExp(r'(\d+)%')
        .firstMatch(_run('pactl', ['get-sink-volume', name]) ?? '');
    return m == null ? null : int.parse(m[1]!);
  }

  @override
  void setSinkVolume(String name, int percent) =>
      _run('pactl', ['set-sink-volume', name, '$percent%']);
}

/// An in-memory PipeWire for the tests and `--demo`.
class MemoryPipeWire implements PipeWireHost {
  MemoryPipeWire({this.isAvailable = true, this.failStart = false});
  bool isAvailable;
  bool failStart;
  final started = <String>[]; // every configuration handed to start()
  int stops = 0;
  bool running = false;
  String? def = 'alsa_output.demo.analog-stereo';
  final defaultChanges = <String>[];
  final volumes = <String, int>{'alsa_output.demo.analog-stereo': 14};

  @override
  bool get available => isAvailable;

  @override
  String? sinkFor(String pciAddress) =>
      'alsa_output.pci-${pciAddress.replaceAll(':', '_')}.analog-stereo';

  @override
  Future<bool> start(String conf) async {
    await stop();
    started.add(conf);
    running = !failStart;
    return running;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  String? defaultSink() => def;

  @override
  void setDefaultSink(String name) {
    def = name;
    defaultChanges.add(name);
  }

  @override
  int? sinkVolume(String name) => volumes[name];

  @override
  void setSinkVolume(String name, int percent) => volumes[name] = percent;
}
