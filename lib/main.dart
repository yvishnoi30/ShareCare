
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'transfer/sender_service.dart';

void main() {
  runApp(const ShareCareApp());
}

class ShareCareApp extends StatelessWidget {
  const ShareCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShareCare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4169E1),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8FC),
          centerTitle: false,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';

  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Returns an icon based on the filename extension.
IconData iconForFile(String name) {
  final String lower = name.toLowerCase();

  if ([
    '.jpg', '.jpeg', '.png', '.webp', '.gif',
    '.bmp', '.heic', '.heif', '.tif', '.tiff', '.svg'
  ].any(lower.endsWith)) {
    return Icons.image_outlined;
  }

  if ([
    '.mp4', '.mov', '.mkv', '.avi', '.webm',
    '.3gp', '.mpeg', '.mpg', '.wmv', '.m4v'
  ].any(lower.endsWith)) {
    return Icons.video_file_outlined;
  }

  if ([
    '.mp3', '.wav', '.aac', '.m4a', '.flac', '.ogg', '.opus'
  ].any(lower.endsWith)) {
    return Icons.audio_file_outlined;
  }

  if (lower.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }

  if (lower.endsWith('.apk')) {
    return Icons.android_outlined;
  }

  if ([
    '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'
  ].any(lower.endsWith)) {
    return Icons.folder_zip_outlined;
  }

  if ([
    '.doc', '.docx', '.odt', '.rtf'
  ].any(lower.endsWith)) {
    return Icons.description_outlined;
  }

  if ([
    '.xls', '.xlsx', '.csv', '.ods'
  ].any(lower.endsWith)) {
    return Icons.table_chart_outlined;
  }

  if ([
    '.ppt', '.pptx', '.odp'
  ].any(lower.endsWith)) {
    return Icons.slideshow_outlined;
  }

  if ([
    '.txt', '.md', '.json', '.xml', '.html', '.css',
    '.js', '.dart', '.java', '.py', '.kt', '.c', '.cpp', '.h'
  ].any(lower.endsWith)) {
    return Icons.code_outlined;
  }

  return Icons.insert_drive_file_outlined;
}

/// Cleans invalid filename characters without changing the extension.
///
/// Examples:
/// presentation.pptx -> presentation.pptx
/// report.pdf        -> report.pdf
/// movie.mp4         -> movie.mp4
/// archive.tar.gz    -> archive.tar.gz
String safeReceivedFileName(String originalName) {
  String cleaned = originalName
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
      .trim();

  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');

  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    return 'shared_file';
  }

  // Separate the base name from its final extension.
  // Hidden filenames such as ".env" are kept intact.
  final int dotIndex = cleaned.lastIndexOf('.');

  if (dotIndex <= 0 || dotIndex == cleaned.length - 1) {
    return cleaned;
  }

  final String baseName = cleaned.substring(0, dotIndex);
  final String extension = cleaned.substring(dotIndex);

  // Reconstruct with the extension exactly once.
  return '$baseName$extension';
}
/// MIME type for a file name. Android's "Save as" dialog needs it to know
/// where the extension starts, so a duplicate becomes "report (1).pdf"
/// instead of "report.pdf (1)".
String mimeTypeForFile(String name) {
  const Map<String, String> mimeTypes = <String, String>{
    // Documents
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
    'rtf': 'application/rtf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'html': 'text/html',
    // Images
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    // Video
    'mp4': 'video/mp4',
    'm4v': 'video/x-m4v',
    'mkv': 'video/x-matroska',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'webm': 'video/webm',
    '3gp': 'video/3gpp',
    'mpeg': 'video/mpeg',
    'mpg': 'video/mpeg',
    'wmv': 'video/x-ms-wmv',
    // Audio
    'mp3': 'audio/mpeg',
    'wav': 'audio/x-wav',
    'flac': 'audio/flac',
    // Archives and apps
    'zip': 'application/zip',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/x-rar-compressed',
    'apk': 'application/vnd.android.package-archive',
  };

  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return 'application/octet-stream';
  }

  return mimeTypes[name.substring(dot + 1).toLowerCase()] ??
      'application/octet-stream';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<PlatformFile> _selectedFiles = <PlatformFile>[];
  bool _isPickingFiles = false;

  int get _totalBytes {
    int total = 0;
    for (final PlatformFile file in _selectedFiles) {
      total += file.size;
    }
    return total;
  }

  Future<void> _pickFiles() async {
    if (_isPickingFiles) return;

    setState(() {
      _isPickingFiles = true;
    });

    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result == null || !mounted) return;

      final Set<String> existing = _selectedFiles
          .map((PlatformFile file) => file.path ?? file.name)
          .toSet();

      setState(() {
        for (final PlatformFile file in result.files) {
          final String key = file.path ?? file.name;
          if (!existing.contains(key)) {
            _selectedFiles.add(file);
            existing.add(key);
          }
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select files: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFiles = false;
        });
      }
    }
  }

  Future<void> _openSender() async {
    if (_selectedFiles.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectionScreen(
          files: List<PlatformFile>.of(_selectedFiles),
        ),
      ),
    );
  }

  void _openReceiver() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReceiverScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ShareCare',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Receive files',
            onPressed: _openReceiver,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const SizedBox(height: 8),
              const Icon(
                Icons.devices_rounded,
                size: 64,
                color: Color(0xFF4169E1),
              ),
              const SizedBox(height: 12),
              Text(
                'Share files. Simply.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Send files directly between devices on your local network.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _isPickingFiles ? null : _pickFiles,
                        icon: _isPickingFiles
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(
                          _isPickingFiles
                              ? 'Selecting files...'
                              : 'Select files to send',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _selectedFiles.isEmpty
                                  ? 'No files selected'
                                  : '${_selectedFiles.length} file(s) selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_selectedFiles.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedFiles.clear();
                                });
                              },
                              child: const Text('Clear all'),
                            ),
                        ],
                      ),
                      if (_selectedFiles.isNotEmpty) ...<Widget>[
                        Text('Total size: ${formatBytes(_totalBytes)}'),
                        const SizedBox(height: 8),
                        ...List<Widget>.generate(
                          _selectedFiles.length,
                          (int index) {
                            final PlatformFile file = _selectedFiles[index];

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(iconForFile(file.name)),
                              title: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(formatBytes(file.size)),
                              trailing: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedFiles.removeAt(index);
                                  });
                                },
                                icon: const Icon(Icons.close),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            _selectedFiles.isEmpty ? null : _openSender,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Continue to connect'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openReceiver,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Receive files on this device'),
              ),
              const SizedBox(height: 20),
              const InstructionCard(
                icon: Icons.wifi,
                title: 'Use the same network',
                description:
                    'Connect both devices to the same Wi-Fi network, '
                    'or connect both devices through a compatible hotspot.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.files,
  });

  final List<PlatformFile> files;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final LocalSenderService _senderService;
  StreamSubscription<String>? _pairingSubscription;

  bool _isStarting = false;
  bool _isChecking = false;
  bool? _healthCheckPassed;

  String _status = 'Sender is stopped.';
  String? _pairedDeviceAddress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _senderService = LocalSenderService(files: widget.files);
    _pairingSubscription = _senderService.pairingUpdates.listen(
      (String address) {
        if (!mounted) return;
        setState(() {
          _pairedDeviceAddress = address;
          _status = 'Device connected successfully.';
        });
      },
    );
  }

  @override
  void dispose() {
    _pairingSubscription?.cancel();
    _senderService.dispose();
    super.dispose();
  }

  Future<void> _startSender() async {
    if (_isStarting || _senderService.isRunning) return;

    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _healthCheckPassed = null;
      _pairedDeviceAddress = null;
      _status = 'Starting local sender...';
    });

    try {
      await _senderService.start();
      if (!mounted) return;

      setState(() {
        _status = _senderService.localAddress == null
            ? 'Server started, but no local IPv4 address was found.'
            : 'Waiting for a device to scan the QR code.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _status = 'Could not start the local sender.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stopSender() async {
    await _senderService.stop();
    if (!mounted) return;

    setState(() {
      _status = 'Sender is stopped.';
      _healthCheckPassed = null;
      _pairedDeviceAddress = null;
      _errorMessage = null;
    });
  }

  Future<void> _testSender() async {
    if (!_senderService.isRunning || _isChecking) return;

    setState(() {
      _isChecking = true;
      _healthCheckPassed = null;
    });

    final bool result = await _senderService.checkHealth();
    if (!mounted) return;

    setState(() {
      _healthCheckPassed = result;
      _status = result
          ? 'Local sender health check passed.'
          : 'Local sender health check failed.';
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? qrData = _senderService.pairingData;
    final bool running = _senderService.isRunning;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect device')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: <Widget>[
                      const Icon(
                        Icons.qr_code_2,
                        size: 48,
                        color: Color(0xFF4169E1),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Connect a device',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start the sender, then scan the generated QR '
                        'code using ShareCare on the receiving device.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (qrData != null &&
                          _senderService.localAddress != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.white,
                          child: QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 230,
                            backgroundColor: Colors.white,
                          ),
                        )
                      else
                        const SizedBox(
                          height: 180,
                          child: Center(
                            child: Text(
                              'Start the sender to generate QR',
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (running) ...<Widget>[
                        SelectableText(
                          'Sender address: '
                          '${_senderService.localAddress ?? "Not found"}',
                        ),
                        Text('Port: ${_senderService.port}'),
                        Text(
                          '${widget.files.length} file(s) ready to send',
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isStarting || running
                              ? null
                              : _startSender,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            _isStarting
                                ? 'Starting...'
                                : 'Start local sender',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: running ? _stopSender : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop local sender'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: running && !_isChecking
                              ? _testSender
                              : null,
                          icon: const Icon(Icons.network_check),
                          label: Text(
                            _isChecking
                                ? 'Testing...'
                                : 'Test sender connection',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Connection status',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(_status),
                      if (_pairedDeviceAddress != null)
                        Text('Connected device address: $_pairedDeviceAddress'),
                      if (_healthCheckPassed != null)
                        Text(
                          _healthCheckPassed!
                              ? 'Local server check: PASS'
                              : 'Local server check: FAIL',
                        ),
                      if (_errorMessage != null)
                        Text(
                          'Error: $_errorMessage',
                          style: const TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.size,
  });

  final String id;
  final String name;
  final int size;

  factory ReceivedFile.fromJson(Map<String, dynamic> json) {
    return ReceivedFile(
      id: json['id'] as String,
      name: json['name'] as String,
      size: (json['size'] as num).toInt(),
    );
  }
}

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final MobileScannerController _scannerController =
      MobileScannerController();

  bool _isConnecting = false;
  bool _hasProcessedCode = false;
  bool _isLoadingFiles = false;

  String _status = 'Scan the QR code shown on the sending device.';

  String? _host;
  int? _port;
  String? _token;
  String? _errorMessage;

  List<ReceivedFile> _files = <ReceivedFile>[];
  final Set<String> _savedFiles = <String>{};

  String? _downloadingId;
  double _downloadProgress = 0;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isConnecting || _hasProcessedCode) return;

    String? rawValue;

    for (final Barcode barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        rawValue = barcode.rawValue;
        break;
      }
    }

    if (rawValue == null) return;

    setState(() {
      _isConnecting = true;
      _hasProcessedCode = true;
      _errorMessage = null;
      _status = 'Reading pairing information...';
    });

    try {
      final dynamic decoded = jsonDecode(rawValue);

      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'ShareCare' ||
          decoded['version'] != 1 ||
          decoded['host'] is! String ||
          decoded['port'] is! int ||
          decoded['token'] is! String) {
        throw const FormatException('Invalid ShareCare QR code.');
      }

      final String host = decoded['host'] as String;
      final int port = decoded['port'] as int;
      final String token = decoded['token'] as String;

      if (host.isEmpty || port < 1 || port > 65535 || token.isEmpty) {
        throw const FormatException('Invalid connection details.');
      }

      final Map<String, dynamic> result =
          await _getJson(host, port, '/pair', token);

      if (result['status'] != 'paired') {
        throw const FormatException(
          'The sending device did not confirm pairing.',
        );
      }

      _host = host;
      _port = port;
      _token = token;

      await _loadFiles();

      if (!mounted) return;

      setState(() {
        _status = 'Paired successfully. Choose a file to receive.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _status = 'Pairing failed.';
        _hasProcessedCode = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String host,
    int port,
    String path,
    String token,
  ) async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      final Uri uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: <String, String>{'token': token},
      );

      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 20));

      final String body =
          await response.transform(utf8.decoder).join();

      final dynamic decoded = jsonDecode(body);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          decoded is Map<String, dynamic>
              ? (decoded['error']?.toString() ?? 'Request failed')
              : 'Request failed (${response.statusCode})',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected server response.');
      }

      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadFiles() async {
    final String? host = _host;
    final int? port = _port;
    final String? token = _token;

    if (host == null || port == null || token == null) return;

    setState(() {
      _isLoadingFiles = true;
    });

    try {
      final Map<String, dynamic> result =
          await _getJson(host, port, '/files', token);

      final dynamic rawFiles = result['files'];

      if (rawFiles is! List) {
        throw const FormatException(
          'The sending device returned an invalid file list.',
        );
      }

      final List<ReceivedFile> received = <ReceivedFile>[];

      for (final dynamic item in rawFiles) {
        if (item is Map<String, dynamic>) {
          received.add(ReceivedFile.fromJson(item));
        }
      }

      if (!mounted) return;

      setState(() {
        _files = received;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
      }
    }
  }

  Future<void> _receiveFile(ReceivedFile file) async {
    final String? host = _host;
    final int? port = _port;
    final String? token = _token;

    if (host == null || port == null || token == null) return;
    if (_downloadingId != null) return;

    setState(() {
      _downloadingId = file.id;
      _downloadProgress = 0;
      _errorMessage = null;
      _status = 'Downloading ${file.name}...';
    });

    final HttpClient client = HttpClient();
    String? temporaryPath;

    try {
      final Uri uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/download',
        queryParameters: <String, String>{
          'token': token,
          'id': file.id,
        },
      );

      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 30));

      if (response.statusCode != HttpStatus.ok) {
        final String errorBody =
            await response.transform(utf8.decoder).join();

        throw HttpException(
          'Download failed (${response.statusCode}): $errorBody',
        );
      }

      final Directory tempDirectory =
          await Directory.systemTemp.createTemp('sharecare_');

      final String safeName = safeReceivedFileName(file.name);
      final File temporaryFile =
          File('${tempDirectory.path}/$safeName');

      temporaryPath = temporaryFile.path;

      final IOSink sink = temporaryFile.openWrite();
      int received = 0;

      try {
        await for (final List<int> chunk in response) {
          sink.add(chunk);
          received += chunk.length;

          if (mounted) {
            setState(() {
              _downloadProgress = file.size > 0
                  ? (received / file.size).clamp(0.0, 1.0)
                  : 0;
            });
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final int actualSize = await temporaryFile.length();

      if (actualSize != received || received != file.size) {
        throw FileSystemException(
          'File size mismatch. Expected ${file.size} bytes, '
          'received $received bytes.',
        );
      }

      if (!mounted) return;

      setState(() {
        _status = 'Download complete. Choose where to save $safeName.';
      });

      final String? savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: temporaryFile.path,
          fileName: safeName,
          mimeTypesFilter: <String>[mimeTypeForFile(safeName)]
        ),
      );

      if (!mounted) return;

      if (savedPath == null) {
        setState(() {
          _status = 'Save cancelled for ${file.name}.';
        });
      } else {
        setState(() {
          _savedFiles.add(file.id);
          _status = 'Saved $safeName successfully.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
          _status = 'Could not receive ${file.name}.';
        });
      }
    } finally {
      client.close(force: true);

      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
          await File(temporaryPath).parent.delete();
        } catch (_) {
          // Best-effort temporary-file cleanup.
        }
      }

      if (mounted) {
        setState(() {
          _downloadingId = null;
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _hasProcessedCode = false;
      _isConnecting = false;
      _host = null;
      _port = null;
      _token = null;
      _files = <ReceivedFile>[];
      _savedFiles.clear();
      _errorMessage = null;
      _status = 'Scan the QR code shown on the sending device.';
    });

    await _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    final bool paired = _host != null && _token != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive files'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Toggle camera',
            onPressed: paired
                ? null
                : () => _scannerController.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          if (!paired)
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 360,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
              ),
            )
          else
            Card(
              child: SizedBox(
                height: 140,
                child: Center(
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green.shade600,
                    size: 84,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Icon(
                    paired
                        ? Icons.check_circle
                        : _isConnecting
                            ? Icons.sync
                            : Icons.qr_code_scanner,
                    size: 36,
                    color: paired ? Colors.green : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_isConnecting || _isLoadingFiles) ...<Widget>[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(),
                  ],
                  if (_downloadingId != null) ...<Widget>[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 6),
                    Text(
                      '${(_downloadProgress * 100).round()}% downloaded',
                    ),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    SelectableText(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (!paired && _hasProcessedCode && !_isConnecting)
                    FilledButton(
                      onPressed: _scanAgain,
                      child: const Text('Try scanning again'),
                    ),
                  if (paired)
                    TextButton.icon(
                      onPressed: _scanAgain,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          ),
          if (paired) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Files available (${_files.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_files.isEmpty && !_isLoadingFiles)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No files were selected on the sending device.'),
                ),
              ),
            ..._files.map((ReceivedFile file) {
              final bool downloading = _downloadingId == file.id;
              final bool saved = _savedFiles.contains(file.id);

              return Card(
                child: ListTile(
                  leading: Icon(iconForFile(file.name)),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(formatBytes(file.size)),
                  trailing: downloading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : saved
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            )
                          : IconButton(
                              tooltip: 'Receive file',
                              onPressed: _downloadingId == null
                                  ? () => _receiveFile(file)
                                  : null,
                              icon: const Icon(Icons.download),
                            ),
                ),
              );
            }),
            const SizedBox(height: 8),
            const Text(
              'Choose Receive beside a file. The receiving device will then ask '
              'where to save it.',
              textAlign: TextAlign.center,
            ),
          ],
          if (!paired) ...<Widget>[
            const SizedBox(height: 12),
            const InstructionCard(
              icon: Icons.wifi,
              title: 'Network required',
              description:
                  'Both devices must be able to communicate over the same local network '
                  'or connect both devices through a compatible hotspot. Mobile data alone is not enough.',
            ),
          ],
        ],
      ),
    );
  }
}

class InstructionCard extends StatelessWidget {
  const InstructionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 28,
              color: const Color(0xFF4169E1),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
