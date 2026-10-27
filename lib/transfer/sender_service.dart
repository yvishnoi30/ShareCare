import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';

import 'transfer_models.dart';

/// Where one file is in its transfer to the receiver.
enum SendState { started, progress, completed, failed }

/// One progress update for one file.
///
/// [fileId] is the index of the file in the list given to
/// [LocalSenderService]. It is also the `id` the receiver sees in `/files`.
class SendEvent {
  const SendEvent({
    required this.fileId,
    required this.state,
    required this.sentBytes,
    required this.totalBytes,
  });

  final int fileId;
  final SendState state;
  final int sentBytes;
  final int totalBytes;
}

/// A usable IPv4 address of this device and the adapter it belongs to.
class LocalAddress {
  const LocalAddress({required this.address, required this.interfaceName});

  final String address;
  final String interfaceName;

  /// Text for the address picker, for example `192.168.1.20 (Wi-Fi)`.
  String get label => '$address ($interfaceName)';
}

class _RankedAddress {
  const _RankedAddress(this.address, this.rank, this.order);

  final LocalAddress address;
  final int rank;
  final int order;
}

/// Local HTTP server that offers the selected files to one receiver.
///
/// Protocol (unchanged): every request carries `?token=...`.
///   GET /health    -> {"app":"ShareCare","status":"ready"}
///   GET /pair      -> {"status":"paired",...}   (unlocks the two routes below)
///   GET /files     -> {"files":[{"id","name","size"}, ...]}
///   GET /download  -> raw bytes of file `id`
class LocalSenderService {
  LocalSenderService({
    required List<PlatformFile> files,
  }) : _selectedFiles = List<PlatformFile>.unmodifiable(files);

  static const Duration _progressInterval = Duration(milliseconds: 100);

  // Adapter names that are usually not the Wi-Fi / Ethernet the other device
  // is on (virtual switches, VPNs, mobile data). They are listed last.
  static const List<String> _virtualContains = <String>[
    'vethernet',
    'vmware',
    'virtualbox',
    'vbox',
    'hyper-v',
    'docker',
    'bluetooth',
    'tailscale',
    'zerotier',
    'vpn',
  ];

  static const List<String> _virtualPrefixes = <String>[
    'rmnet',
    'ccmni',
    'veth',
    'docker',
    'virbr',
    'br-',
    'tun',
    'tap',
    'utun',
  ];

  final List<PlatformFile> _selectedFiles;

  HttpServer? _server;
  String? _token;
  String? _localAddress;
  List<LocalAddress> _candidates = const <LocalAddress>[];
  bool _isPaired = false;

  final StreamController<String> _pairingController =
      StreamController<String>.broadcast();
  final StreamController<SendEvent> _sendController =
      StreamController<SendEvent>.broadcast();

  int? get port => _server?.port;
  String? get token => _token;
  String? get localAddress => _localAddress;
  bool get isRunning => _server != null;
  bool get isPaired => _isPaired;

  /// Every usable IPv4 address found on this device, best guess first.
  List<LocalAddress> get candidateAddresses =>
      List<LocalAddress>.unmodifiable(_candidates);

  Stream<String> get pairingUpdates => _pairingController.stream;

  /// Progress of each file while a receiver downloads it.
  Stream<SendEvent> get sendEvents => _sendController.stream;

  /// The text shown in the QR code and copied by "Copy pairing code".
  String? get pairingData {
    final String? address = _localAddress;
    final int? serverPort = port;
    final String? currentToken = _token;

    if (address == null || serverPort == null || currentToken == null) {
      return null;
    }

    return PairingInfo(
      host: address,
      port: serverPort,
      token: currentToken,
    ).toPayload();
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
    _candidates = const <LocalAddress>[];

    HttpServer? server;

    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;

      await _refreshCandidates();

      server.listen(
        _handleRequest,
        onError: (Object error, StackTrace stackTrace) {},
      );
    } catch (_) {
      _server = null;
      _token = null;
      _localAddress = null;
      _candidates = const <LocalAddress>[];
      await server?.close(force: true);
      rethrow;
    }
  }

  /// Looks at the network adapters again. Keeps the address the user picked
  /// if it is still there.
  Future<void> refreshAddresses() async {
    if (!isRunning) return;
    await _refreshCandidates();
  }

  /// Switches the address used in the QR code and pairing code. Returns false
  /// if [address] is not one of [candidateAddresses].
  bool selectAddress(String address) {
    if (!isRunning) return false;

    final bool known =
        _candidates.any((LocalAddress item) => item.address == address);
    if (!known) return false;

    _localAddress = address;
    return true;
  }

  Future<void> _refreshCandidates() async {
    final List<LocalAddress> found = await _discoverAddresses();

    // stop() may have run while the adapters were being listed.
    if (_server == null) return;

    _candidates = found;

    final String? current = _localAddress;
    final bool stillThere = current != null &&
        found.any((LocalAddress item) => item.address == current);

    if (!stillThere) {
      _localAddress = found.isEmpty ? null : found.first.address;
    }
  }

  Future<List<LocalAddress>> _discoverAddresses() async {
    final List<NetworkInterface> interfaces;

    try {
      interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
    } catch (_) {
      return const <LocalAddress>[];
    }

    final List<_RankedAddress> ranked = <_RankedAddress>[];
    final Set<String> seen = <String>{};

    for (final NetworkInterface networkInterface in interfaces) {
      for (final InternetAddress address in networkInterface.addresses) {
        if (address.type != InternetAddressType.IPv4 ||
            address.isLoopback ||
            address.isLinkLocal ||
            !seen.add(address.address)) {
          continue;
        }

        ranked.add(
          _RankedAddress(
            LocalAddress(
              address: address.address,
              interfaceName: networkInterface.name,
            ),
            _rank(address.address, networkInterface.name),
            ranked.length,
          ),
        );
      }
    }

    ranked.sort((_RankedAddress a, _RankedAddress b) {
      final int byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.order.compareTo(b.order);
    });

    return ranked
        .map((_RankedAddress item) => item.address)
        .toList(growable: false);
  }

  /// 0 = private range on a normal adapter (best), 3 = worst.
  int _rank(String address, String interfaceName) {
    final bool privateRange = _isPrivateRange(address);
    final bool virtual = _looksVirtual(interfaceName);

    if (privateRange && !virtual) return 0;
    if (privateRange) return 1;
    if (!virtual) return 2;
    return 3;
  }

  static bool _isPrivateRange(String address) {
    if (address.startsWith('192.168.') || address.startsWith('10.')) {
      return true;
    }

    final List<String> parts = address.split('.');
    if (parts.length != 4) return false;

    final int? first = int.tryParse(parts[0]);
    final int? second = int.tryParse(parts[1]);

    return first == 172 && second != null && second >= 16 && second <= 31;
  }

  static bool _looksVirtual(String interfaceName) {
    final String name = interfaceName.toLowerCase();

    return _virtualContains.any(name.contains) ||
        _virtualPrefixes.any(name.startsWith);
  }

  bool _tokenMatches(String? supplied) {
    final String? expected = _token;

    if (expected == null || supplied == null) return false;
    if (supplied.length != expected.length) return false;

    // Compares every character so the time taken does not reveal how much
    // of a guessed token was right.
    int difference = 0;
    for (int index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ supplied.codeUnitAt(index);
    }

    return difference == 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      await _route(request);
    } catch (_) {
      // A broken request must never take the server down.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers were already sent.
      }

      try {
        await request.response.close();
      } catch (_) {
        // The connection is gone.
      }
    }
  }

  Future<void> _route(HttpRequest request) async {
    if (!_tokenMatches(request.uri.queryParameters['token'])) {
      await _writeJson(
        request,
        HttpStatus.unauthorized,
        <String, Object>{'error': 'Invalid session token'},
      );
      return;
    }

    final bool isGet = request.method == 'GET';
    final String path = request.uri.path;

    if (isGet && path == '/health') {
      await _writeJson(
        request,
        HttpStatus.ok,
        <String, Object>{'app': 'ShareCare', 'status': 'ready'},
      );
      return;
    }

    if (isGet && path == '/pair') {
      _isPaired = true;

      final String remoteAddress =
          request.connectionInfo?.remoteAddress.address ?? 'Unknown device';

      if (!_pairingController.isClosed) {
        _pairingController.add(remoteAddress);
      }

      await _writeJson(
        request,
        HttpStatus.ok,
        <String, Object>{
          'app': 'ShareCare',
          'status': 'paired',
          'message': 'Device reached the sender successfully',
        },
      );
      return;
    }

    if (isGet && path == '/files') {
      if (!_isPaired) {
        await _writeJson(
          request,
          HttpStatus.forbidden,
          <String, Object>{'error': 'Pair this device first'},
        );
        return;
      }

      final List<Map<String, Object>> files = <Map<String, Object>>[];

      for (int index = 0; index < _selectedFiles.length; index++) {
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
        <String, Object>{'files': files},
      );
      return;
    }

    if (isGet && path == '/download') {
      if (!_isPaired) {
        await _writeJson(
          request,
          HttpStatus.forbidden,
          <String, Object>{'error': 'Pair this device first'},
        );
        return;
      }

      final int? fileId = int.tryParse(
        request.uri.queryParameters['id'] ?? '',
      );

      if (fileId == null || fileId < 0 || fileId >= _selectedFiles.length) {
        await _writeJson(
          request,
          HttpStatus.notFound,
          <String, Object>{'error': 'File not found'},
        );
        return;
      }

      await _sendFile(request, fileId);
      return;
    }

    await _writeJson(
      request,
      HttpStatus.notFound,
      <String, Object>{'error': 'Not found'},
    );
  }

  Future<void> _sendFile(HttpRequest request, int fileId) async {
    final PlatformFile selectedFile = _selectedFiles[fileId];
    final String? filePath = selectedFile.path;

    if (filePath == null || filePath.isEmpty) {
      await _writeJson(
        request,
        HttpStatus.badRequest,
        <String, Object>{'error': 'The selected file has no readable path'},
      );
      return;
    }

    final File file = File(filePath);

    if (!await file.exists()) {
      await _writeJson(
        request,
        HttpStatus.notFound,
        <String, Object>{'error': 'The selected file no longer exists'},
      );
      return;
    }

    final int length = await file.length();
    final HttpResponse response = request.response;

    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('application', 'octet-stream');
    response.headers.set(HttpHeaders.contentLengthHeader, length);
    response.headers.set(
      'Content-Disposition',
      'attachment; filename="${_safeFileName(selectedFile.name)}"',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    int sent = 0;
    int lastReport = 0;
    final Stopwatch clock = Stopwatch()..start();

    _emit(fileId, SendState.started, 0, length);

    try {
      await response.addStream(
        file.openRead().map((List<int> chunk) {
          sent += chunk.length;

          final int now = clock.elapsedMilliseconds;
          if (now - lastReport >= _progressInterval.inMilliseconds) {
            lastReport = now;
            _emit(fileId, SendState.progress, sent, length);
          }

          return chunk;
        }),
      );
      await response.close();
    } catch (_) {
      // The receiver cancelled, the network dropped, or the file changed
      // while it was being read.
      _emit(fileId, SendState.failed, sent, length);

      try {
        await response.close();
      } catch (_) {
        // The connection is already gone.
      }
      return;
    }

    _emit(fileId, SendState.completed, length, length);
  }

  void _emit(int fileId, SendState state, int sent, int total) {
    if (_sendController.isClosed) return;

    _sendController.add(
      SendEvent(
        fileId: fileId,
        state: state,
        sentBytes: sent,
        totalBytes: total,
      ),
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

  /// Asks this computer's own server whether it answers. It cannot tell
  /// whether a firewall lets other devices in.
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
        queryParameters: <String, String>{'token': currentToken},
      );

      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 5));
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));

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
    _candidates = const <LocalAddress>[];
    _isPaired = false;

    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _pairingController.close();
    await _sendController.close();
  }
}