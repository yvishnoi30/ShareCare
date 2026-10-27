import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

import '../utils/file_utils.dart';

/// Receives ShareCare folder archives and restores them as regular folders.
///
/// The sender creates archives with the special `.sharecare-folder.zip`
/// suffix and without an extra root directory in the archive. The receiver
/// creates a uniquely named output folder and extracts the contents there.
class FolderArchiveReceiver {
  FolderArchiveReceiver._();

  static const String archiveSuffix = '.sharecare-folder.zip';

  // Protect receivers from unexpectedly huge/decompression-bomb archives.
  static const int maxExpandedBytes = 20 * 1024 * 1024 * 1024;

  static bool isFolderArchiveName(String name) =>
      name.toLowerCase().endsWith(archiveSuffix);

  static String folderNameFromArchiveName(String name) {
    String result = name;
    if (result.toLowerCase().endsWith(archiveSuffix)) {
      result = result.substring(0, result.length - archiveSuffix.length);
    }
    return _safeFolderName(result);
  }

  /// Extracts a folder archive into [destinationDirectory] on Windows.
  /// Returns the full path to the newly created folder.
  static Future<String> extractOnWindows({
    required String zipPath,
    required String destinationDirectory,
    required String suggestedFolderName,
  }) async {
    final File zip = File(zipPath);
    if (!await zip.exists()) {
      throw FileSystemException(
        'The downloaded folder archive is missing.',
        zipPath,
      );
    }

    final Directory destination = Directory(destinationDirectory);
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    final String folderName = _safeFolderName(suggestedFolderName);
    final Directory output = await _nextAvailableDirectory(
      destination,
      folderName,
    );
    await output.create(recursive: false);

    try {
      await extractFileToDisk(zip.path, output.path, maxSize: maxExpandedBytes);
      return output.path;
    } catch (_) {
      try {
        if (await output.exists()) await output.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  /// Extracts an archive on Android. The user selects a destination directory
  /// using SAF; extracted files and subfolders are copied into a new folder
  /// within that directory. Returns the created folder name, or null when the
  /// user cancels the destination picker.
  static Future<String?> extractOnAndroid({
    required String zipPath,
    required String suggestedFolderName,
  }) async {
    final File zip = File(zipPath);
    if (!await zip.exists()) {
      throw FileSystemException(
        'The downloaded folder archive is missing.',
        zipPath,
      );
    }

    final Saf saf = Saf();
    final SafDocumentFile? destination = await saf.pickDirectory();
    if (destination == null) return null;

    final Directory tempRoot = await getTemporaryDirectory();
    final Directory extractionRoot = await Directory(
      '${tempRoot.path}${Platform.pathSeparator}sharecare_extract_${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);

    SafDocumentFile? outputFolder;

    try {
      await extractFileToDisk(
        zip.path,
        extractionRoot.path,
        maxSize: maxExpandedBytes,
      );

      final String baseName = _safeFolderName(suggestedFolderName);
      final String uniqueName = await _nextAvailableSafFolderName(
        saf,
        destination.uri,
        baseName,
      );
      outputFolder = await saf.mkdirp(destination.uri, <String>[uniqueName]);

      await for (final FileSystemEntity entity in extractionRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        final String relative = entity.path
            .substring(extractionRoot.path.length)
            .replaceFirst(RegExp(r'^[\\/]+'), '');
        final List<String> segments = relative
            .split(RegExp(r'[\\/]+'))
            .where((String part) => part.isNotEmpty && part != '.')
            .toList();
        if (segments.isEmpty) continue;
        if (segments.any((String part) => part == '..')) {
          throw const FormatException(
            'The folder archive contains an unsafe path.',
          );
        }

        if (entity is Link) {
          // Do not recreate symbolic links on Android storage.
          continue;
        }

        if (entity is Directory) {
          await saf.mkdirp(outputFolder.uri, segments);
          continue;
        }

        if (entity is File) {
          final List<String> parentSegments = segments
              .take(segments.length - 1)
              .toList();
          final SafDocumentFile targetDirectory = parentSegments.isEmpty
              ? outputFolder
              : await saf.mkdirp(outputFolder.uri, parentSegments);

          await saf.pasteLocalFile(
            entity.path,
            targetDirectory.uri,
            segments.last,
            _mimeType(segments.last),
            overwrite: false,
          );
        }
      }

      return uniqueName;
    } catch (_) {
      final SafDocumentFile? created = outputFolder;
      if (created != null) {
        try {
          await saf.delete(created.uri);
        } catch (_) {}
      }
      rethrow;
    } finally {
      try {
        if (await extractionRoot.exists()) {
          await extractionRoot.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<Directory> _nextAvailableDirectory(
    Directory parent,
    String baseName,
  ) async {
    var candidate = Directory(
      '${parent.path}${Platform.pathSeparator}$baseName',
    );
    var number = 1;
    while (await FileSystemEntity.type(candidate.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      candidate = Directory(
        '${parent.path}${Platform.pathSeparator}$baseName ($number)',
      );
      number++;
    }
    return candidate;
  }

  static Future<String> _nextAvailableSafFolderName(
    Saf saf,
    String destinationUri,
    String baseName,
  ) async {
    var candidate = baseName;
    var number = 1;
    while (await saf.child(destinationUri, <String>[candidate]) != null) {
      candidate = '$baseName ($number)';
      number++;
    }
    return candidate;
  }

  static String _safeFolderName(String name) {
    final String cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'SharedFolder';
    }
    return cleaned;
  }

  static String _mimeType(String name) => mimeTypeForFile(name);
}
