
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';

class LocalSenderService {
  LocalSenderService({
    required List<PlatformFile> files,
  }) : _selectedFiles = List<PlatformFile>.unmodifiable(files);

  final List<PlatformFile> _selectedFiles;

  HttpServer? _server;
  String? _token;
  String? _localAddress;

  final StreamController<String> _pairingController =
      StreamController<String>.broadcast();

  bool _isPaired = false;

  int? get port => _server?.port;
  String? get token => _token;
  String? get localAddress => _localAddress;
  bool get isRunning => _server != null;
  bool get isPaired => _isPaired;

  Stream<String> get pairingUpdates => _pairingController.stream;

  String? get pairingData {
    final String? address = _localAddress;
    final int? serverPort = port;
    final String? currentToken = _token;

    if (address == null ||
        serverPort == null ||
        currentToken == null) {
      return null;
    }

    return jsonEncode(<String, Object>{
      'app': 'ShareCare',
      'version': 1,
      'host': address,
      'port': serverPort,
      'token': currentToken,
    });
  }

  Future<void> start() async {
    if (isRunning) {
      return;
    }

    final Random random = Random.secure();
    final List<int> tokenBytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    );

    _token = base64UrlEncode(tokenBytes).replaceAll('=', '');
    _isPaired = false;
    _localAddress = null;

    try {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
      );

      _server = server;
      _localAddress = await _findLocalIPv4Address();

      server.listen(
        _handleRequest,
        onError: (Object error, StackTrace stackTrace) {},
      );
    } catch (_) {
      _server = null;
      _token = null;
      _localAddress = null;
      rethrow;
    }
  }

  Future<String?> _findLocalIPv4Address() async {
    final List<NetworkInterface> interfaces =
        await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final List<String> addresses = <String>[];

    for (final NetworkInterface networkInterface in interfaces) {
      for (final InternetAddress address
          in networkInterface.addresses) {
        if (address.type == InternetAddressType.IPv4 &&
            !address.isLoopback) {
          addresses.add(address.address);
        }
      }
    }

    for (final String address in addresses) {
      if (address.startsWith('192.168.') ||
          address.startsWith('10.') ||
          _is172Private(address)) {
        return address;
      }
    }

    if (addresses.isNotEmpty) {
      return addresses.first;
    }

    return null;
  }

  bool _is172Private(String address) {
    final List<String> parts = address.split('.');

    if (parts.length != 4) {
      return false;
    }

    final int? first = int.tryParse(parts[0]);
    final int? second = int.tryParse(parts[1]);

    return first == 172 &&
        second != null &&
        second >= 16 &&
        second <= 31;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final String? suppliedToken =
        request.uri.queryParameters['token'];

    if (_token == null || suppliedToken != _token) {
      await _writeJson(
        request,
        HttpStatus.unauthorized,
        <String, Object>{
          'error': 'Invalid session token',
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        request.uri.path == '/health') {
      await _writeJson(
        request,
        HttpStatus.ok,
        <String, Object>{
          'app': 'ShareCare',
          'status': 'ready',
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        request.uri.path == '/pair') {
      _isPaired = true;

      final String remoteAddress =
          request.connectionInfo?.remoteAddress.address ??
              'Unknown device';

      if (!_pairingController.isClosed) {
        _pairingController.add(remoteAddress);
      }

      await _writeJson(
        request,
        HttpStatus.ok,
        <String, Object>{
          'app': 'ShareCare',
          'status': 'paired',
          'message': 'Phone reached the sender successfully',
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        request.uri.path == '/files') {
      if (!_isPaired) {
        await _writeJson(
          request,
          HttpStatus.forbidden,
          <String, Object>{
            'error': 'Pair this device first',
          },
        );
        return;
      }

      final List<Map<String, Object>> files =
          <Map<String, Object>>[];

      for (int index = 0;
          index < _selectedFiles.length;
          index++) {
        final PlatformFile file = _selectedFiles[index];

        files.add(<String, Object>{
          'id': '$index',
          'name': file.name,
          'size': file.size,
        });
      }

      await _writeJson(
        request,
        HttpStatus.ok,
        <String, Object>{
          'files': files,
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        request.uri.path == '/download') {
      if (!_isPaired) {
        await _writeJson(
          request,
          HttpStatus.forbidden,
          <String, Object>{
            'error': 'Pair this device first',
          },
        );
        return;
      }

      final int? fileId = int.tryParse(
        request.uri.queryParameters['id'] ?? '',
      );

      if (fileId == null ||
          fileId < 0 ||
          fileId >= _selectedFiles.length) {
        await _writeJson(
          request,
          HttpStatus.notFound,
          <String, Object>{
            'error': 'File not found',
          },
        );
        return;
      }

      final PlatformFile selectedFile =
          _selectedFiles[fileId];
      final String? filePath = selectedFile.path;

      if (filePath == null || filePath.isEmpty) {
        await _writeJson(
          request,
          HttpStatus.badRequest,
          <String, Object>{
            'error': 'The selected file has no readable path',
          },
        );
        return;
      }

      final File file = File(filePath);

      if (!await file.exists()) {
        await _writeJson(
          request,
          HttpStatus.notFound,
          <String, Object>{
            'error': 'The selected file no longer exists',
          },
        );
        return;
      }

      final int fileLength = await file.length();

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType =
          ContentType('application', 'octet-stream');
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        fileLength,
      );
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="${_safeFileName(selectedFile.name)}"',
      );
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store',
      );

      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }

    await _writeJson(
      request,
      HttpStatus.notFound,
      <String, Object>{
        'error': 'Not found',
      },
    );
  }

  String _safeFileName(String name) {
    return name.replaceAll(
      RegExp(r'[^a-zA-Z0-9._ -]'),
      '_',
    );
  }

  Future<void> _writeJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object> data,
  ) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'no-store',
    );
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<bool> checkHealth() async {
    final HttpServer? server = _server;
    final String? currentToken = _token;

    if (server == null || currentToken == null) {
      return false;
    }

    final HttpClient client = HttpClient();

    try {
      final Uri uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/health',
        queryParameters: <String, String>{
          'token': currentToken,
        },
      );

      final HttpClientRequest request =
          await client.getUrl(uri);
      final HttpClientResponse response =
          await request.close();
      final String body =
          await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final dynamic decoded = jsonDecode(body);

      return decoded is Map<String, dynamic> &&
          decoded['app'] == 'ShareCare' &&
          decoded['status'] == 'ready';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    final HttpServer? server = _server;

    _server = null;
    _token = null;
    _localAddress = null;
    _isPaired = false;

    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _pairingController.close();
  }
}
