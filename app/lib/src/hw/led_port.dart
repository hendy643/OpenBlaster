// SPDX-License-Identifier: Apache-2.0
import 'apa102.dart';
import 'bar2.dart';
import 'renderer.dart';

abstract class LedSink {
  /// False if the frame did not go out (try again later).
  bool show(Frame frame);
}

/// Drives the AE-5's LED strip by bit-banging two of the controller's GPIO pins through the BAR2 port
/// register: data on pin 2, clock on pin 3 (APA102 style). Only the enable byte and the port register
/// are touched; the pin direction register is left alone.
class LedPort implements LedSink {
  LedPort(this._bar2);

  static const kEnable = 0x304;
  static const kPort = 0x320;
  static const kDataPin = 2;
  static const kClockPin = 3;

  final Bar2 _bar2;
  bool _prepared = false;

  void _pin(int pin, bool level) {
    _bar2.write16(kPort, pin | (level ? 0x100 : 0));
    _bar2.read16(kPort); // reading back paces the clock
  }

  void _prepare() {
    const ours = (1 << kDataPin) | (1 << kClockPin);
    final enabled = _bar2.read8(kEnable);
    if (enabled & ours != ours) _bar2.write8(kEnable, enabled | ours);
    _pin(kClockPin, false);
    _pin(kDataPin, false);
    _prepared = true;
  }

  @override
  bool show(Frame frame) {
    if (!_prepared) _prepare();
    for (final byte in encodeFrame(frame)) {
      for (var bit = 7; bit >= 0; bit--) {
        _pin(kDataPin, (byte >> bit) & 1 == 1);
        _pin(kClockPin, true);
        _pin(kClockPin, false);
      }
    }
    _pin(kDataPin, false); // idle: both low
    return true;
  }
}
