// SPDX-License-Identifier: Apache-2.0
// Reads (never writes) the real card, if this machine has one, to prove the libasound bindings work.
import 'package:flutter_test/flutter_test.dart';
import 'package:openblaster/src/hw/alsa_backend.dart';
import 'package:openblaster/src/hw/discovery.dart';
import 'package:openblaster/src/hw/snd_alsa_io.dart';

void main() {
  final cards = findCards();
  test('the real card can be opened and read', () {
    final io = SndAlsaIo.open(cards.first.card);
    addTearDown(io.close);
    final backend = AlsaBackend(io);
    final controls = backend.controls();
    expect(controls, isNotEmpty);
    for (final c in controls) {
      expect(c.value, isNotNull, reason: c.id);
      // (a value outside min..max does happen: mic.wedge_angle reads 10 on a card whose range is 20..180)
    }
    // ignore: avoid_print
    print('${cards.first.name}: ${controls.length} controls');
  }, skip: cards.isEmpty ? 'no Creative card in this machine' : false);
}
