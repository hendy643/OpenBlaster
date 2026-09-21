// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'renderer.dart';

/// The bytes the strip clocks in: 4 zero bytes, per LED `0xFF, B, G, R`, then ones to flush it through.
/// (Verified against the real card's LEDs.)
Uint8List encodeFrame(Frame frame) {
  final out = BytesBuilder()..add(List.filled(4, 0));
  for (final c in frame) {
    out.add([0xff, c.b, c.g, c.r]);
  }
  out.add(List.filled((frame.length + 15) ~/ 16 + 3, 0xff));
  return out.toBytes();
}
