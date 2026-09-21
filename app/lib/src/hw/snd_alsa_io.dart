// SPDX-License-Identifier: Apache-2.0
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'alsa_io.dart';

// The parts of libasound's high-level control API we use, bound from Dart: no native code of ours.
typedef _P = Pointer<Void>;
final _lib = DynamicLibrary.open('libasound.so.2');

final _hctlOpen = _lib
    .lookupFunction<
      Int32 Function(Pointer<_P>, Pointer<Utf8>, Int32),
      int Function(Pointer<_P>, Pointer<Utf8>, int)
    >('snd_hctl_open');
final _hctlClose = _lib.lookupFunction<Int32 Function(_P), int Function(_P)>(
  'snd_hctl_close',
);
final _hctlLoad = _lib.lookupFunction<Int32 Function(_P), int Function(_P)>(
  'snd_hctl_load',
);
final _firstElem = _lib.lookupFunction<_P Function(_P), _P Function(_P)>(
  'snd_hctl_first_elem',
);
final _nextElem = _lib.lookupFunction<_P Function(_P), _P Function(_P)>(
  'snd_hctl_elem_next',
);
final _elemInfo = _lib
    .lookupFunction<Int32 Function(_P, _P), int Function(_P, _P)>(
      'snd_hctl_elem_info',
    );
final _elemRead = _lib
    .lookupFunction<Int32 Function(_P, _P), int Function(_P, _P)>(
      'snd_hctl_elem_read',
    );
final _elemWrite = _lib
    .lookupFunction<Int32 Function(_P, _P), int Function(_P, _P)>(
      'snd_hctl_elem_write',
    );
final _strerror = _lib
    .lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>(
      'snd_strerror',
    );

final _infoMalloc = _lib
    .lookupFunction<Int32 Function(Pointer<_P>), int Function(Pointer<_P>)>(
      'snd_ctl_elem_info_malloc',
    );
final _infoFree = _lib.lookupFunction<Void Function(_P), void Function(_P)>(
  'snd_ctl_elem_info_free',
);
final _valueMalloc = _lib
    .lookupFunction<Int32 Function(Pointer<_P>), int Function(Pointer<_P>)>(
      'snd_ctl_elem_value_malloc',
    );
final _valueFree = _lib.lookupFunction<Void Function(_P), void Function(_P)>(
  'snd_ctl_elem_value_free',
);

int Function(_P) _infoInt(String name) =>
    _lib.lookupFunction<Int32 Function(_P), int Function(_P)>(name);
int Function(_P) _infoLong(String name) =>
    _lib.lookupFunction<Long Function(_P), int Function(_P)>(name);

final _getInterface = _infoInt('snd_ctl_elem_info_get_interface');
final _getIndex = _infoInt('snd_ctl_elem_info_get_index');
final _getType = _infoInt('snd_ctl_elem_info_get_type');
final _getCount = _infoInt('snd_ctl_elem_info_get_count');
final _isWritable = _infoInt('snd_ctl_elem_info_is_writable');
final _getItems = _infoInt('snd_ctl_elem_info_get_items');
final _getMin = _infoLong('snd_ctl_elem_info_get_min');
final _getMax = _infoLong('snd_ctl_elem_info_get_max');
final _getStep = _infoLong('snd_ctl_elem_info_get_step');
final _getName = _lib
    .lookupFunction<Pointer<Utf8> Function(_P), Pointer<Utf8> Function(_P)>(
      'snd_ctl_elem_info_get_name',
    );
final _getItemName = _lib
    .lookupFunction<Pointer<Utf8> Function(_P), Pointer<Utf8> Function(_P)>(
      'snd_ctl_elem_info_get_item_name',
    );
final _setItem = _lib
    .lookupFunction<Void Function(_P, Uint32), void Function(_P, int)>(
      'snd_ctl_elem_info_set_item',
    );

final _getBool = _lib
    .lookupFunction<Int32 Function(_P, Uint32), int Function(_P, int)>(
      'snd_ctl_elem_value_get_boolean',
    );
final _getInt = _lib
    .lookupFunction<Long Function(_P, Uint32), int Function(_P, int)>(
      'snd_ctl_elem_value_get_integer',
    );
final _getEnum = _lib
    .lookupFunction<Uint32 Function(_P, Uint32), int Function(_P, int)>(
      'snd_ctl_elem_value_get_enumerated',
    );
final _setBool = _lib
    .lookupFunction<
      Void Function(_P, Uint32, Int32),
      void Function(_P, int, int)
    >('snd_ctl_elem_value_set_boolean');
final _setInt = _lib
    .lookupFunction<
      Void Function(_P, Uint32, Long),
      void Function(_P, int, int)
    >('snd_ctl_elem_value_set_integer');
final _setEnum = _lib
    .lookupFunction<
      Void Function(_P, Uint32, Uint32),
      void Function(_P, int, int)
    >('snd_ctl_elem_value_set_enumerated');

const _ifaceMixer = 2;
const _typeBoolean = 1, _typeInteger = 2, _typeEnumerated = 3;
const _nonblock = 1;

class AlsaOpenError implements Exception {
  AlsaOpenError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Elem {
  _Elem(this.ptr, this.type, this.count);
  final _P ptr;
  final RawType type;
  final int count;
}

/// The real card, through libasound's control API. Element pointers stay valid while the handle is
/// open (we never process events, only read and write on request).
class SndAlsaIo implements AlsaIo {
  SndAlsaIo._(this._hctl, this._info, this._value);

  final _P _hctl;
  final _P _info, _value; // scratch structures, reused
  final _elems = <String, _Elem>{};
  bool _closed = false;

  /// Opens `hw:N` for card N. Throws [AlsaOpenError] if it cannot.
  factory SndAlsaIo.open(int card) {
    final name = 'hw:$card'.toNativeUtf8();
    final out = calloc<_P>();
    try {
      var err = _hctlOpen(out, name, _nonblock);
      if (err < 0)
        throw AlsaOpenError('hw:$card: ${_strerror(err).toDartString()}');
      final hctl = out.value;
      err = _hctlLoad(hctl);
      if (err < 0) {
        _hctlClose(hctl);
        throw AlsaOpenError('hw:$card: ${_strerror(err).toDartString()}');
      }
      _infoMalloc(out);
      final info = out.value;
      _valueMalloc(out);
      final io = SndAlsaIo._(hctl, info, out.value);
      io._scan();
      return io;
    } finally {
      calloc.free(name);
      calloc.free(out);
    }
  }

  static RawType _typeOf(int t) => switch (t) {
    _typeBoolean => RawType.boolean,
    _typeInteger => RawType.integer,
    _typeEnumerated => RawType.enumerated,
    _ => RawType.other,
  };

  void _scan() {
    for (var e = _firstElem(_hctl); e != nullptr; e = _nextElem(e)) {
      if (_elemInfo(e, _info) < 0) continue;
      if (_getInterface(_info) != _ifaceMixer || _getIndex(_info) != 0)
        continue;
      _elems[_getName(_info).toDartString()] = _Elem(
        e,
        _typeOf(_getType(_info)),
        _getCount(_info),
      );
    }
  }

  @override
  List<RawControl> list() {
    final out = <RawControl>[];
    for (final MapEntry(key: name, value: el) in _elems.entries) {
      if (_elemInfo(el.ptr, _info) < 0) continue;
      var min = 0, max = 0, step = 0;
      final items = <String>[];
      if (el.type == RawType.integer) {
        min = _getMin(_info);
        max = _getMax(_info);
        step = _getStep(_info);
      } else if (el.type == RawType.enumerated) {
        final n = _getItems(_info);
        for (var i = 0; i < n; i++) {
          _setItem(_info, i);
          if (_elemInfo(el.ptr, _info) < 0) break;
          items.add(_getItemName(_info).toDartString());
        }
      }
      out.add(
        RawControl(
          name: name,
          type: el.type,
          count: el.count,
          min: min,
          max: max,
          step: step,
          items: items,
          writable: _isWritable(_info) != 0,
        ),
      );
    }
    return out;
  }

  @override
  List<int>? read(String name) {
    final el = _elems[name];
    if (_closed || el == null || _elemRead(el.ptr, _value) < 0) return null;
    return [
      for (var i = 0; i < el.count; i++)
        switch (el.type) {
          RawType.boolean => _getBool(_value, i),
          RawType.integer => _getInt(_value, i),
          RawType.enumerated => _getEnum(_value, i),
          RawType.other => -1,
        },
    ];
  }

  @override
  bool write(String name, List<int> values) {
    final el = _elems[name];
    if (_closed ||
        el == null ||
        values.length != el.count ||
        el.type == RawType.other) {
      return false;
    }
    // Read first so the id and any channels we do not touch are filled in.
    if (_elemRead(el.ptr, _value) < 0) return false;
    for (var i = 0; i < values.length; i++) {
      switch (el.type) {
        case RawType.boolean:
          _setBool(_value, i, values[i] != 0 ? 1 : 0);
        case RawType.integer:
          _setInt(_value, i, values[i]);
        case RawType.enumerated:
          _setEnum(_value, i, values[i]);
        case RawType.other:
          return false;
      }
    }
    return _elemWrite(el.ptr, _value) >= 0;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _infoFree(_info);
    _valueFree(_value);
    _hctlClose(_hctl);
  }
}
