
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/file_saver.dart';
import '../utils/file_utils.dart';
import 'transfer_models.dart';

typedef TransferProgressCallback = void Function(
  int bytes,
  int totalBytes,
);

/// Handles pairing, listing files and downloading from a ShareCare sender.
/// Saving is delegated to the platform-specific FileSaver.
class ReceiverService {
  ReceiverService({
    required this.pairing,
    required this.fileSaver,
    this.connectTimeout = const Duration(seconds: 8),
    this.responseTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
  });

  final PairingInfo pairing;
  final FileSaver fileSaver;

  final Duration connectTimeout;
  final Duration responseTimeout;
  final Duration idleTimeout;

  HttpClient? _downloadClient;
  bool _cancelRequested = false;

  bool get isDownloading => _downloadClient != null;

  Uri _uri(String path, [Map<String, String>? extra]) {
    return Uri(
      scheme: 'http',
      host: pairing.host,
      port: pairing.port,
      path: path,
      queryParameters: <String, String>{
        'token': pairing.token,
        ...?extra,
      },
    );
  }

  /// Verifies that the sender accepts the pairing information.
  Future<void> pair() async {
    final Map<String, dynamic> result = await _getJson('/pair');

    if (result['status'] != 'paired') {
      throw const TransferException(
        'The sending device did not confirm pairing.',
      );
    }
  }

  /// Retrieves files available from the paired sender.
  Future<List<ReceivedFile>> fetchFiles() async {
    final Map<String, dynamic> result = await _getJson('/files');
    final dynamic rawFiles = result['files'];

    if (rawFiles is! List) {
      throw const TransferException(
        'The sending device returned an invalid file list.',
      );
    }

    final List<ReceivedFile> files = <ReceivedFile>[];

    for (final dynamic item in rawFiles) {
      if (item is Map<String, dynamic>) {
        try {
          files.add(ReceivedFile.fromJson(item));
        } catch (_) {
          throw const TransferException(
            'The sending device returned an invalid file list.',
          );
        }
      }
    }

    return files;
  }

  /// Downloads a file, verifies the byte count and saves it using FileSaver.
  Future<SaveResult> receiveFile(
    ReceivedFile file, {
    TransferProgressCallback? onProgress,
    void Function(String safeName)? onDownloaded,
  }) async {
    if (_downloadClient != null) {
      throw const TransferException(
        'Another download is already in progress.',
      );
    }

    _cancelRequested = false;

    final String safeName = safeReceivedFileName(file.name);

    final HttpClient client = HttpClient()
      ..connectionTimeout = connectTimeout;

    _downloadClient = client;

    StagedFile? staged;

    try {
      staged = await fileSaver.createStagedFile(safeName);

      await _download(
        client,
        file,
        staged.file,
        onProgress,
      );

      onDownloaded?.call(safeName);

      return await fileSaver.commit(staged, safeName);
    } on TransferException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        throw const TransferCancelledException();
      }

      throw _toTransferException(error);
    } finally {
      _downloadClient = null;
      client.close(force: true);
      await staged?.discard();
    }
  }

  /// Requests cancellation of the current download.
  void cancelDownload() {
    _cancelRequested = true;
    _downloadClient?.close(force: true);
  }

  void dispose() {
    cancelDownload();
  }

  Future<void> _download(
    HttpClient client,
    ReceivedFile file,
    File target,
    TransferProgressCallback? onProgress,
  ) async {
    final HttpClientRequest request = await client.getUrl(
      _uri('/download', <String, String>{
        'id': file.id,
      }),
    );

    final HttpClientResponse response =
        await request.close().timeout(responseTimeout);

    if (response.statusCode != HttpStatus.ok) {
      final String body =
          await response.transform(utf8.decoder).join();

      throw TransferException(
        _statusMessage(
          response.statusCode,
          _extractError(body),
        ),
      );
    }

    final int expected = file.size;
    final int announced = response.contentLength;

    if (announced >= 0 && announced != expected) {
      throw const TransferException(
        'The file changed on the sending device after it was selected. '
        'Ask the sender to select it again.',
      );
    }

    int received = 0;
    final Stopwatch clock = Stopwatch()..start();
    int lastReport = -1000;

    void report({bool force = false}) {
      if (onProgress == null) return;

      final int now = clock.elapsedMilliseconds;

      if (force || now - lastReport >= 80) {
        lastReport = now;
        onProgress(received, expected);
      }
    }

    final IOSink sink = target.openWrite();
    bool completed = false;

    try {
      // Stream to disk instead of loading the entire file into memory.
      final Stream<List<int>> counted =
          response.timeout(idleTimeout).map((List<int> chunk) {
        received += chunk.length;
        report();
        return chunk;
      });

      await sink.addStream(counted);
      await sink.flush();
      completed = true;
    } finally {
      try {
        await sink.close();
      } catch (_) {
        if (completed) rethrow;
      }
    }

    report(force: true);

    final int actualSize = await target.length();

    if (received != expected || actualSize != expected) {
      throw TransferException(
        'File size mismatch. Expected $expected bytes, '
        'received $received bytes.',
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = connectTimeout;

    try {
      final HttpClientRequest request = await client.getUrl(
        _uri(path),
      );

      final HttpClientResponse response =
          await request.close().timeout(responseTimeout);

      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(responseTimeout);

      dynamic decoded;

      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }

      if (response.statusCode != HttpStatus.ok) {
        final String reason = decoded is Map<String, dynamic>
            ? (decoded['error']?.toString() ?? 'Request failed')
            : 'Request failed (${response.statusCode})';

        throw TransferException(
          _statusMessage(response.statusCode, reason),
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const TransferException(
          'The sending device sent an unexpected response.',
        );
      }

      return decoded;
    } on TransferException {
      rethrow;
    } catch (error) {
      throw _toTransferException(error);
    } finally {
      client.close(force: true);
    }
  }

  String _extractError(String body) {
    try {
      final dynamic decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic> &&
          decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // The response wasn't JSON.
    }

    return 'Request failed';
  }

  String _statusMessage(int statusCode, String reason) {
    if (statusCode == HttpStatus.unauthorized) {
      return 'The sending device rejected the pairing code. '
          'Start sharing again and use the new code.';
    }

    if (statusCode == HttpStatus.forbidden) {
      return 'The sending device has not accepted this connection yet. '
          'Connect again.';
    }

    return 'The sending device reported an error '
        '($statusCode): $reason';
  }

  TransferException _toTransferException(Object error) {
    if (error is TransferException) {
      return error;
    }

    if (error is TimeoutException) {
      return TransferException(
        'The sending device stopped responding. Check that both devices '
        'are on the same network and that sharing is still running.',
        cause: error,
      );
    }

    if (error is SocketException) {
      return TransferException(
        'Could not reach the sending device. Check the network, confirm '
        'that sharing is running, and check Windows Firewall permissions.',
        cause: error,
      );
    }

    if (error is HttpException) {
      return TransferException(
        'The connection was interrupted: ${error.message}',
        cause: error,
      );
    }

    if (error is FileSystemException) {
      final int? code = error.osError?.errorCode;

      if (code == 112 || code == 39 || code == 28) {
        return TransferException(
          'There is not enough free space to save this file.',
          cause: error,
        );
      }

      return TransferException(
        'Could not write the file: ${error.message}',
        cause: error,
      );
    }

    return TransferException(
      'The transfer failed: $error',
      cause: error,
    );
  }
}
