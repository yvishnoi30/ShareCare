import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

/// Selects a folder and creates a temporary ZIP archive for ShareCare.
///
/// Windows reads the selected directory directly. Android uses SAF to request
/// access to the folder, copies its contents into app-private temporary storage,
/// then creates the ZIP there. The original folder is never modified.
class FolderArchiveService {
  const FolderArchiveService._();

  static Future<PlatformFile?> pickAndCreateZip() async {
    if (Platform.isAndroid) {
      return _pickAndZipAndroid();
    }

    return _pickAndZipPathBased();
  }

  static Future<PlatformFile?> _pickAndZipPathBased() async {
    final String? selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder to share',
    );
    if (selectedPath == null || selectedPath.isEmpty) return null;

    final Directory source = Directory(selectedPath);
    if (!await source.exists()) {
      throw FileSystemException(
        'The selected folder no longer exists.',
        selectedPath,
      );
    }

    final String folderName = _safeName(_basename(source.path));
    final Directory temp = await getTemporaryDirectory();
    final File zipFile = File(
      _join(
        temp.path,
        'sharecare_${DateTime.now().microsecondsSinceEpoch}_$folderName.zip',
      ),
    );

    await _writeZip(source, zipFile);
    return _asPlatformFile(zipFile, '$folderName.sharecare-folder.zip');
  }

  static Future<PlatformFile?> _pickAndZipAndroid() async {
    final Saf saf = Saf();
    final SafDocumentFile? selected = await saf.pickDirectory();
    if (selected == null) return null;

    final String folderName = _safeName(selected.name);
    final Directory temp = await getTemporaryDirectory();
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final Directory stageBase = Directory(
      _join(temp.path, 'sharecare_stage_$stamp'),
    );
    final Directory stagedFolder = Directory(_join(stageBase.path, folderName));
    final File zipFile = File(
      _join(temp.path, 'sharecare_${stamp}_$folderName.zip'),
    );

    try {
      await stagedFolder.create(recursive: true);

      await for (final SafWalkEntry entry in saf.walk(selected.uri)) {
        final String relative = entry.relativePath.replaceAll('\\', '/');
        final List<String> segments = relative.split('/');

        // Reject unsafe paths rather than allowing a provider-supplied path to
        // escape the temporary folder during staging.
        if (segments.isEmpty ||
            segments.any(
              (String part) => part.isEmpty || part == '.' || part == '..',
            )) {
          throw const FormatException(
            'The selected folder contains an invalid path.',
          );
        }

        String targetPath = stagedFolder.path;
        for (final String segment in segments) {
          targetPath = _join(targetPath, segment);
        }

        if (entry.file.isDir) {
          await Directory(targetPath).create(recursive: true);
        } else {
          await Directory(File(targetPath).parent.path).create(recursive: true);
          await saf.copyToLocalFile(entry.file.uri, targetPath);
        }
      }

      await _writeZip(stagedFolder, zipFile);
      return await _asPlatformFile(zipFile, '$folderName.sharecare-folder.zip');
    } catch (_) {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      rethrow;
    } finally {
      try {
        if (await stageBase.exists()) await stageBase.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup of the temporary staging directory.
      }
    }
  }

  static Future<void> _writeZip(Directory source, File zipFile) async {
    final ZipFileEncoder encoder = ZipFileEncoder();
    encoder.create(zipFile.path);

    try {
      await encoder.addDirectory(
        source,
        includeDirName: false,
        followLinks: false,
      );
      await encoder.close();
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<PlatformFile> _asPlatformFile(File file, String name) async {
    return PlatformFile(name: name, path: file.path, size: await file.length());
  }

  static String _basename(String path) {
    final String normalized = path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final int slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  static String _safeName(String name) {
    final String cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    return cleaned.isEmpty ? 'SharedFolder' : cleaned;
  }

  static String _join(String left, String right) {
    final String separator = Platform.pathSeparator;
    final String trimmedLeft = left.replaceFirst(RegExp(r'[\\/]+$'), '');
    final String trimmedRight = right.replaceAll(RegExp(r'^[\\/]+'), '');
    return '$trimmedLeft$separator$trimmedRight';
  }
}
