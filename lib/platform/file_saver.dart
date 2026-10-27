
import 'dart:io';

enum SaveStatus { saved, cancelled }

class SaveResult {
  const SaveResult._(
    this.status,
    this.savedName,
    this.location,
  );

  const SaveResult.saved({
    required String name,
    String? location,
  }) : this._(SaveStatus.saved, name, location);

  const SaveResult.cancelled()
      : this._(SaveStatus.cancelled, null, null);

  final SaveStatus status;
  final String? savedName;
  final String? location;

  bool get wasSaved => status == SaveStatus.saved;
}

/// A downloaded file that has not yet been committed to its final location.
class StagedFile {
  StagedFile({
    required this.file,
    this.ownedDirectory,
  });

  final File file;
  final Directory? ownedDirectory;

  /// Cleans up the staged file and, when owned, its temporary directory.
  Future<void> discard() async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup.
    }

    final Directory? directory = ownedDirectory;

    if (directory != null) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}

/// Platform-specific destination and saving behaviour.
abstract class FileSaver {
  /// Whether the user must select a destination folder first.
  bool get needsDestinationFolder;

  /// The currently selected destination path, if applicable.
  String? get destinationPath;

  /// Opens the platform's destination-selection dialog.
  /// Returns false if the user cancels.
  Future<bool> chooseDestination();

  /// Creates a staging file for the incoming download.
  Future<StagedFile> createStagedFile(String safeName);

  /// Commits a completed download to its final destination.
  Future<SaveResult> commit(
    StagedFile staged,
    String safeName,
  );
}
