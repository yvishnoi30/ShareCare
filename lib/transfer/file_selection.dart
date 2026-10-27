import 'dart:collection';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Manages files selected for sending.
/// Duplicate file paths are ignored.
class FileSelection extends ChangeNotifier {
  final List<PlatformFile> _files = <PlatformFile>[];

  UnmodifiableListView<PlatformFile> get files =>
      UnmodifiableListView<PlatformFile>(_files);

  int get count => _files.length;

  bool get isEmpty => _files.isEmpty;

  bool get isNotEmpty => _files.isNotEmpty;

  int get totalBytes {
    int total = 0;

    for (final PlatformFile file in _files) {
      total += file.size;
    }

    return total;
  }

  String _keyOf(PlatformFile file) => file.path ?? file.name;

  /// Adds new files and returns the number added.
  int addAll(Iterable<PlatformFile> picked) {
    final Set<String> existing = _files.map(_keyOf).toSet();
    int added = 0;

    for (final PlatformFile file in picked) {
      if (existing.add(_keyOf(file))) {
        _files.add(file);
        added++;
      }
    }

    if (added > 0) {
      notifyListeners();
    }

    return added;
  }

  void removeAt(int index) {
    if (index < 0 || index >= _files.length) {
      return;
    }

    _files.removeAt(index);
    notifyListeners();
  }

  void clear() {
    if (_files.isEmpty) {
      return;
    }

    _files.clear();
    notifyListeners();
  }
}