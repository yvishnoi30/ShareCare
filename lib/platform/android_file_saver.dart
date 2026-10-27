
import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../utils/file_utils.dart';
import 'file_saver.dart';

/// Preserves the existing Android save-dialog workflow.
/// Only use this implementation on Android.
class AndroidFileSaver implements FileSaver {
  @override
  bool get needsDestinationFolder => false;

  @override
  String? get destinationPath => null;

  @override
  Future<bool> chooseDestination() async => true;

  @override
  Future<StagedFile> createStagedFile(String safeName) async {
    final Directory directory =
        await Directory.systemTemp.createTemp('sharecare_');

    return StagedFile(
      file: File('${directory.path}/$safeName'),
      ownedDirectory: directory,
    );
  }

  @override
  Future<SaveResult> commit(
    StagedFile staged,
    String safeName,
  ) async {
    final String? savedPath = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: staged.file.path,
        fileName: safeName,
        mimeTypesFilter: <String>[
          mimeTypeForFile(safeName),
        ],
      ),
    );

    if (savedPath == null) {
      return const SaveResult.cancelled();
    }

    return SaveResult.saved(
      name: safeName,
      location: savedPath,
    );
  }
}
