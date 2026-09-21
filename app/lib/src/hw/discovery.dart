// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'catalog.dart';

const kCreativeVendor = 0x1102;
const kSoundCore3dDevice = 0x0012; // PCI 1102:0012, the CA0132 family

/// A sound card on the HDA bus that is Creative's.
class CardInfo {
  const CardInfo({
    required this.card,
    required this.subsystemVendor,
    required this.subsystemDevice,
    required this.name,
  });
  final int card; // the ALSA card number
  final int subsystemVendor, subsystemDevice;
  final String name; // the marketing name

  /// The AE-5 and AE-5 Plus have the five-LED strip; the other models do not.
  bool get hasLighting =>
      subsystemVendor == 0x1102 &&
      (subsystemDevice == 0x0051 || subsystemDevice == 0x0191);

  @override
  bool operator ==(Object other) =>
      other is CardInfo && other.card == card && other.name == name;

  @override
  int get hashCode => Object.hash(card, name);
}

// sysfs prints these as "0x1102\n".
int? _readId(String file) {
  try {
    final text = File(file).readAsStringSync().trim();
    if (!RegExp(r'^0x[0-9a-fA-F]{1,4}$').hasMatch(text)) return null;
    return int.parse(text.substring(2), radix: 16);
  } on FileSystemException {
    return null;
  }
}

/// Scans [sysClassSound] (normally /sys/class/sound) for Creative Sound Core3D cards.
List<CardInfo> findCards([String sysClassSound = '/sys/class/sound']) {
  final dir = Directory(sysClassSound);
  if (!dir.existsSync()) return const [];
  final cards = <CardInfo>[];
  for (final entry in dir.listSync(followLinks: false)) {
    // "card1", not "controlC1", "pcmC1D0p" or "hwC1D0"
    final m = RegExp(r'^card(\d+)$')
        .firstMatch(entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty));
    if (m == null) continue;
    final dev = '${entry.path}/device';
    final vendor = _readId('$dev/vendor');
    final device = _readId('$dev/device');
    final subVendor = _readId('$dev/subsystem_vendor');
    final subDevice = _readId('$dev/subsystem_device');
    if (vendor == null ||
        device == null ||
        subVendor == null ||
        subDevice == null)
      continue;
    if (vendor != kCreativeVendor || device != kSoundCore3dDevice) continue;
    cards.add(
      CardInfo(
        card: int.parse(m[1]!),
        subsystemVendor: subVendor,
        subsystemDevice: subDevice,
        name: modelName(subVendor, subDevice),
      ),
    );
  }
  cards.sort((a, b) => a.card.compareTo(b.card));
  return cards;
}
