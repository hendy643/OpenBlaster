// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

import 'client.dart';
import 'hw/alsa_backend.dart';
import 'hw/alsa_io.dart';
import 'hw/backend.dart';
import 'hw/bar2.dart';
import 'hw/discovery.dart';
import 'hw/led_port.dart';
import 'hw/lighting_backend.dart';
import 'hw/persistent_backend.dart';
import 'hw/snd_alsa_io.dart';
import 'hw/store.dart';
import 'hw/sysfs_bar2.dart';
import 'hw/virtual_surround.dart';
import 'hw/virtual_surround_backend.dart';
import 'models.dart';

typedef CardFinder = List<CardInfo> Function();

/// Opens a card's backend; null (after saying why through [LocalClient.notices] or the log) if it cannot.
typedef BackendFactory = Backend? Function(CardInfo card);

/// Controls the cards directly, from inside the app: ALSA controls through libasound, the LEDs through
/// the BAR2 window. Also runs the lighting animation and saves its settings.
class LocalClient implements OpenBlasterClient {
  LocalClient({
    required this.finder,
    required this.factory,
    this.rescanEvery = const Duration(seconds: 10),
    this.pollEvery = const Duration(seconds: 1),
    this.saveAfter = const Duration(milliseconds: 500),
  });

  /// The real cards. Settings are kept in [stateDir] (default ~/.local/state/openblaster).
  factory LocalClient.real({String? stateDir, void Function(String)? log}) {
    late final LocalClient client;
    final dir = stateDir ?? _defaultStateDir();
    client = LocalClient(
      finder: findCards,
      factory: (card) {
        final SndAlsaIo io;
        try {
          io = SndAlsaIo.open(card.card);
        } on AlsaOpenError catch (e) {
          log?.call('cannot open card ${card.card}: $e');
          return null;
        }
        final id = card.subsystemDevice.toRadixString(16).padLeft(4, '0');
        // every control's value is kept and put back the next time the app starts
        final alsa = PersistentBackend(
          AlsaBackend(io),
          FileStore('$dir/controls-$id.conf'),
        );
        final parts = <Backend>[alsa];
        if (card.hasLighting) {
          try {
            final bar = SysfsBar2.open(
              '/sys/class/sound/card${card.card}/device/resource2',
            );
            parts.add(
              LightingBackend(
                LedPort(bar),
                FileStore('$dir/lighting-$id.conf'),
              ),
            );
          } on Object catch (e) {
            client.notices.add('Lighting is unavailable: $e');
            log?.call('lighting unavailable on card ${card.card}: $e');
          }
        }
        final surround = _virtualSurround(card, id, dir, log);
        if (surround != null) parts.add(surround);
        return parts.length == 1 ? alsa : CompositeBackend(parts);
      },
    );
    return client;
  }

  /// Virtual surround, if PipeWire and at least one HRTF file are there.
  static Backend? _virtualSurround(
    CardInfo card,
    String id,
    String dir,
    void Function(String)? log,
  ) {
    final profiles = findHrirs();
    final host = ProcessPipeWire(
      '${Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path}/openblaster',
    );
    if (profiles.isEmpty || !host.available) {
      log?.call('virtual surround unavailable: no PipeWire or no HRIR file');
      return null;
    }
    // the card's PCI address, for finding its analog output in PipeWire
    String? pci;
    try {
      pci = Directory('/sys/class/sound/card${card.card}/device')
          .resolveSymbolicLinksSync()
          .split('/')
          .last;
    } on FileSystemException {
      return null;
    }
    return VirtualSurroundBackend(
      host: host,
      store: FileStore('$dir/virtual-surround-$id.conf'),
      profiles: profiles,
      targetSink: () => host.sinkFor(pci!),
    );
  }

  /// A made-up AE-5 Plus: nothing on a real card changes.
  factory LocalClient.demo() => LocalClient(
    finder: () => const [
      CardInfo(
        card: 99,
        subsystemVendor: 0x1102,
        subsystemDevice: 0x0191,
        name: 'Sound BlasterX AE-5 Plus (demo)',
      ),
    ],
    factory: (_) => CompositeBackend([
      AlsaBackend(makeDemoCard()),
      LightingBackend(LedPort(MemoryBar2()), MemoryStore()),
      VirtualSurroundBackend(
        host: MemoryPipeWire(),
        store: MemoryStore(),
        profiles: const [
          Hrir(
            '/demo/atmos.wav',
            HrirKind.hesuvi,
            'Dolby Atmos for Headphones',
          ),
          Hrir('/demo/cmss_game.wav', HrirKind.hesuvi, 'CMSS-3D Game'),
          Hrir('/demo/dtshx.wav', HrirKind.hesuvi, 'DTS Headphone:X'),
          Hrir('/demo/sbx33.wav', HrirKind.hesuvi, 'SBX Surround 33%'),
          Hrir('/demo/sbx67.wav', HrirKind.hesuvi, 'SBX Surround 67%'),
          Hrir('/demo/sbx100.wav', HrirKind.hesuvi, 'SBX Surround 100%'),
        ],
        targetSink: () => 'alsa_output.demo.analog-stereo',
      ),
    ]),
  );

  static String _defaultStateDir() {
    final env = Platform.environment;
    final base = env['XDG_STATE_HOME'] ?? '${env['HOME']}/.local/state';
    return '$base/openblaster';
  }

  final CardFinder finder;
  final BackendFactory factory;
  final Duration rescanEvery, pollEvery, saveAfter;

  @override
  final notices = <String>[];

  final _devices = <int, _Dev>{};
  final _devicesChanged = StreamController<void>.broadcast();
  final _clock = Stopwatch()..start();
  Timer? _rescanTimer, _pollTimer;
  bool _closed = false;

  int get _nowMs => _clock.elapsedMilliseconds;

  /// Finds the cards, opens the new ones and drops the ones that are gone.
  void _scan() {
    final found = {for (final c in finder()) c.card: c};
    var changed = false;
    for (final card in _devices.keys.toList()) {
      if (!found.containsKey(card)) {
        _devices.remove(card)!.dispose();
        changed = true;
      }
    }
    for (final info in found.values) {
      if (_devices.containsKey(info.card)) continue;
      final backend = factory(info);
      if (backend == null) continue; // tried again at the next scan
      final dev = _Dev(this, info, backend);
      _devices[info.card] = dev;
      dev.start();
      changed = true;
    }
    if (changed && !_devicesChanged.isClosed) _devicesChanged.add(null);
  }

  void _ensureTimers() {
    _rescanTimer ??= Timer.periodic(rescanEvery, (_) => _scan());
    _pollTimer ??= Timer.periodic(pollEvery, (_) {
      for (final d in _devices.values) {
        d.backend.poll();
      }
    });
  }

  @override
  Future<List<DeviceRef>> devices() async {
    if (_closed) return const [];
    _scan();
    _ensureTimers();
    return [
      for (final d in _devices.values)
        DeviceRef(card: d.info.card, name: d.info.name),
    ];
  }

  @override
  Stream<void> get devicesChanged => _devicesChanged.stream;

  _Dev _dev(DeviceRef ref) {
    final d = _devices[ref.card];
    if (d == null) throw const ControlError('Failed', 'The sound card is gone');
    return d;
  }

  @override
  Future<List<Control>> controls(DeviceRef device) async =>
      _dev(device).backend.controls();

  @override
  Future<void> set(DeviceRef device, String id, int value) async {
    final result = _dev(device).backend.set(id, value);
    if (result == SetResult.ok) return;
    final name = switch (result) {
      SetResult.unknownControl => 'UnknownControl',
      SetResult.readOnly => 'ReadOnly',
      SetResult.outOfRange => 'OutOfRange',
      _ => 'Failed',
    };
    throw ControlError(name, '$id: ${result.message}');
  }

  @override
  Stream<ControlChange> changes(DeviceRef device) =>
      _dev(device).changes.stream;

  @override
  Future<void> close() async {
    _closed = true;
    _rescanTimer?.cancel();
    _pollTimer?.cancel();
    for (final d in _devices.values) {
      d.dispose();
    }
    _devices.clear();
    await _devicesChanged.close();
  }
}

/// One card: its backend, its change stream, and its animation and save timers.
class _Dev {
  _Dev(this.owner, this.info, this.backend);

  final LocalClient owner;
  final CardInfo info;
  final Backend backend;
  final changes = StreamController<ControlChange>.broadcast();
  Timer? _tick, _save;

  void start() {
    backend.onChange = (id, value) {
      if (!changes.isClosed) changes.add(ControlChange(id, value));
      _tickSoon(
        0,
      ); // show a change now, not at the next (slow, if nothing moves) tick
      _save ??= Timer(owner.saveAfter, () {
        _save = null;
        backend.flush();
      });
    };
    _tickSoon(0);
  }

  void _tickSoon(int ms) {
    _tick?.cancel();
    _tick = Timer(Duration(milliseconds: ms), () {
      backend.tick(owner._nowMs);
      final next = backend.tickIntervalMs;
      _tickSoon(
        next > 0 ? next : 1000,
      ); // a backend with nothing to animate is asked rarely
    });
  }

  void dispose() {
    _tick?.cancel();
    _save?.cancel();
    backend.flush();
    backend.close();
    changes.close();
  }
}
