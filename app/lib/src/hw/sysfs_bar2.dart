// SPDX-License-Identifier: Apache-2.0
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'bar2.dart';

final _libc = DynamicLibrary.process();
final _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)
    >('open');
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);
final _mmap = _libc
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        IntPtr,
        Int32,
        Int32,
        Int32,
        IntPtr,
      ),
      Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)
    >('mmap');
final _munmap = _libc
    .lookupFunction<
      Int32 Function(Pointer<Void>, IntPtr),
      int Function(Pointer<Void>, int)
    >('munmap');

const _oRdwr = 2, _oCloexec = 0x80000;
const _protReadWrite = 3, _mapShared = 1;

class Bar2OpenError implements Exception {
  Bar2OpenError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The card's BAR2 register window, mapped from sysfs (`.../device/resource2`). Writing it needs the
/// file to be writable by the user (see install/70-openblaster.rules). Accesses outside the window are
/// ignored (reads give all ones), never made.
class SysfsBar2 implements Bar2 {
  SysfsBar2._(this._base, this._size);

  final Pointer<Uint8> _base;
  final int _size;

  factory SysfsBar2.open(String path) {
    final size = File(path).lengthSync(); // a resource file's size is the BAR's
    if (size <= 0) throw Bar2OpenError('$path: empty');
    final p = path.toNativeUtf8();
    final fd = _open(p, _oRdwr | _oCloexec);
    calloc.free(p);
    if (fd < 0) throw Bar2OpenError('cannot open $path (not writable by you?)');
    final map = _mmap(nullptr, size, _protReadWrite, _mapShared, fd, 0);
    _close(fd); // the mapping outlives the descriptor
    if (map.address == -1) throw Bar2OpenError('cannot map $path');
    return SysfsBar2._(map.cast(), size);
  }

  bool _fits(int offset, int width) => offset >= 0 && offset <= _size - width;

  @override
  int read8(int o) => _fits(o, 1) ? _base[o] : 0xff;

  @override
  void write8(int o, int v) {
    if (_fits(o, 1)) _base[o] = v;
  }

  @override
  int read16(int o) => _fits(o, 2) ? (_base + o).cast<Uint16>().value : 0xffff;

  @override
  void write16(int o, int v) {
    if (_fits(o, 2)) (_base + o).cast<Uint16>().value = v;
  }

  void close() => _munmap(_base.cast(), _size);
}
