
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../transfer/transfer_models.dart';
import '../utils/file_utils.dart';
import 'file_saver.dart';

class WindowsFileSaver implements FileSaver {
  WindowsFileSaver({Future<String?> Function()? folderPicker})
      : _folderPicker = folderPicker ?? _pickWithDialog;

  final Future<String?> Function() _folderPicker;
  Directory? _destination;

  static Future<String?> _pickWithDialog() {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose where to save received files',
    );
  }

  @override
  bool get needsDestinationFolder => true;

  @override
  String? get destinationPath => _destination?.path;

  /// Useful for automated tests.
  void setDestination(String path) {
    _destination = Directory(path);
  }

  @override
  Future<bool> chooseDestination() async {
    final String? picked = await _folderPicker();

    if (picked == null || picked.isEmpty) {
      return false;
    }

    final Directory directory = Directory(picked);

    if (!await directory.exists()) {
      throw const TransferException(
        'The selected destination folder does not exist.',
      );
    }

    _destination = directory;
    return true;
  }

  @override
  Future<StagedFile> createStagedFile(String safeName) async {
    final Directory? destination = _destination;

    if (destination == null) {
      throw const TransferException(
        'Choose a destination folder first.',
      );
    }

    final String stamp =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    final String stagingName =
        '.$safeName.$stamp.sharecare-part';

    return StagedFile(
      file: File(_join(destination.path, stagingName)),
    );
  }

  @override
  Future<SaveResult> commit(
    StagedFile staged,
    String safeName,
  ) async {
    final Directory? destination = _destination;

    if (destination == null) {
      throw const TransferException(
        'Choose a destination folder first.',
      );
    }

    for (int attempt = 0; attempt < 10000; attempt++) {
      final String candidate = numberedFileName(safeName, attempt);
      final File target = File(_join(destination.path, candidate));

      // Reserve the destination name without overwriting existing files.
      try {
        await target.create(exclusive: true);
      } on FileSystemException {
        final FileSystemEntityType type =
            await FileSystemEntity.type(target.path);

        if (type != FileSystemEntityType.notFound) {
          continue;
        }

        rethrow;
      }

      try {
        try {
          await staged.file.rename(target.path);
        } on FileSystemException {
          // Some platforms cannot rename over the reserved empty file.
          await staged.file.copy(target.path);
        }
      } catch (_) {
        try {
          await target.delete();
        } catch (_) {
          // Best-effort cleanup.
        }
        rethrow;
      }

      return SaveResult.saved(
        name: candidate,
        location: target.path,
      );
    }

    throw const TransferException(
      'Could not find a free file name in the chosen folder.',
    );
  }

  String _join(String directory, String name) {
    final bool hasSeparator =
        directory.endsWith('\\') || directory.endsWith('/');

    return hasSeparator
        ? '$directory$name'
        : '$directory${Platform.pathSeparator}$name';
  }
}
