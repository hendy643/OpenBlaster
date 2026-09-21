// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

abstract class SettingsStore {
  String? load();

  /// False if it could not be written (it will be tried again).
  bool save(String text);
}

class MemoryStore implements SettingsStore {
  String? text;
  int saves = 0;
  bool failSaves = false;

  @override
  String? load() => text;

  @override
  bool save(String t) {
    saves++;
    if (failSaves) return false;
    text = t;
    return true;
  }
}

/// One text file. A save writes a temporary file and renames it over the old one, so a crash leaves
/// the old settings or the new, never half of each.
class FileStore implements SettingsStore {
  FileStore(this.path);
  final String path;

  @override
  String? load() {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null; // not text: as good as no file
    }
  }

  @override
  bool save(String text) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final tmp = File('$path.tmp')..writeAsStringSync(text, flush: true);
      tmp.renameSync(path);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
