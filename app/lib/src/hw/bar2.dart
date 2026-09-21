// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

/// The card's BAR2 register window.
abstract class Bar2 {
  int read8(int offset);
  void write8(int offset, int value);
  int read16(int offset);
  void write16(int offset, int value);
}

class Bar2Access {
  const Bar2Access(this.write, this.offset, this.width, this.value);
  final bool write;
  final int offset;
  final int width; // 8 or 16
  final int value;
}

/// A BAR2 in memory with an APA102 strip on the two GPIO pins, for the tests and `--demo`: it logs
/// every access and records the bytes the strip would have clocked in.
class MemoryBar2 implements Bar2 {
  static const portOffset = 0x320;
  static const dataPin = 2;
  static const clockPin = 3;

  final regs = Uint8List(0x1000);
  final accesses = <Bar2Access>[];
  final level = List.filled(8, false); // what each pin was last driven to
  final received = <int>[]; // complete bytes the strip has clocked in
  final bitsLog = <int>[]; // every bit clocked in, in order
  int _acc = 0, _count = 0;

  @override
  int read8(int o) {
    accesses.add(Bar2Access(false, o, 8, regs[o]));
    return regs[o];
  }

  @override
  int read16(int o) {
    final v = regs[o] | (regs[o + 1] << 8);
    accesses.add(Bar2Access(false, o, 16, v));
    return v;
  }

  @override
  void write8(int o, int v) {
    accesses.add(Bar2Access(true, o, 8, v));
    regs[o] = v & 0xff;
  }

  @override
  void write16(int o, int v) {
    accesses.add(Bar2Access(true, o, 16, v));
    regs[o] = v & 0xff;
    regs[o + 1] = (v >> 8) & 0xff;
    if (o == portOffset) _port(v);
  }

  void _port(int v) {
    final pin = v & 0xff;
    final high = (v >> 8) & 1 == 1;
    if (pin >= 8) return;
    final wasHigh = level[pin];
    level[pin] = high;
    if (pin == clockPin && high && !wasHigh) {
      // rising edge: the strip samples the data pin
      final bit = level[dataPin] ? 1 : 0;
      bitsLog.add(bit);
      _acc = ((_acc << 1) | bit) & 0xff;
      if (++_count == 8) {
        received.add(_acc);
        _acc = 0;
        _count = 0;
      }
    }
  }
}
