import 'transfer/folder_archive_service.dart';
import 'transfer/folder_archive_receiver.dart';
import 'platform/platform_info.dart';
import 'screens/desktop/desktop_home_screen.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'transfer/sender_service.dart';
import 'ui/app_theme.dart';
import 'ui/theme_controller.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved theme before the first frame so the app never flashes the
  // wrong theme on start-up.
  final ThemeController themeController = ThemeController();
  await themeController.restore();

  runApp(ShareCareApp(themeController: themeController));
}

class ShareCareApp extends StatefulWidget {
  const ShareCareApp({super.key, this.themeController});

  /// Optional. When omitted the app creates and owns its own controller.
  final ThemeController? themeController;

  @override
  State<ShareCareApp> createState() => _ShareCareAppState();
}

class _ShareCareAppState extends State<ShareCareApp> {
  late final ThemeController _themeController;
  late final bool _ownsController;

  final ThemeData _lightTheme = AppTheme.light();
  final ThemeData _darkTheme = AppTheme.dark();

  @override
  void initState() {
    super.initState();

    _ownsController = widget.themeController == null;
    _themeController = widget.themeController ?? ThemeController();

    if (_ownsController) {
      _themeController.restore();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _themeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            title: 'ShareCare',
            debugShowCheckedModeBanner: false,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: _themeController.mode,
            builder: (BuildContext context, Widget? child) {
              // Respect the user's text size, but keep layouts from breaking
              // at the extremes.
              return MediaQuery.withClampedTextScaling(
                minScaleFactor: 0.8,
                maxScaleFactor: 1.6,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: isDesktopPlatform
                ? const DesktopHomeScreen()
                : const HomeScreen(),
          );
        },
      ),
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
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.svg',
  ].any(lower.endsWith)) {
    return Icons.image_outlined;
  }

  if ([
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.3gp',
    '.mpeg',
    '.mpg',
    '.wmv',
    '.m4v',
  ].any(lower.endsWith)) {
    return Icons.video_file_outlined;
  }

  if ([
    '.mp3',
    '.wav',
    '.aac',
    '.m4a',
    '.flac',
    '.ogg',
    '.opus',
  ].any(lower.endsWith)) {
    return Icons.audio_file_outlined;
  }

  if (lower.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }

  if (lower.endsWith('.apk')) {
    return Icons.android_outlined;
  }

  if (['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'].any(lower.endsWith)) {
    return Icons.folder_zip_outlined;
  }

  if (['.doc', '.docx', '.odt', '.rtf'].any(lower.endsWith)) {
    return Icons.description_outlined;
  }

  if (['.xls', '.xlsx', '.csv', '.ods'].any(lower.endsWith)) {
    return Icons.table_chart_outlined;
  }

  if (['.ppt', '.pptx', '.odp'].any(lower.endsWith)) {
    return Icons.slideshow_outlined;
  }

  if ([
    '.txt',
    '.md',
    '.json',
    '.xml',
    '.html',
    '.css',
    '.js',
    '.dart',
    '.java',
    '.py',
    '.kt',
    '.c',
    '.cpp',
    '.h',
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
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
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

// ===========================================================================
// Home screen
// ===========================================================================

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
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
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

  Future<void> _pickFolder() async {
    if (_isPickingFiles) return;

    setState(() {
      _isPickingFiles = true;
    });

    try {
      final PlatformFile? archive =
          await FolderArchiveService.pickAndCreateZip();

      if (archive == null || !mounted) return;

      final String key = archive.path ?? archive.name;

      final bool alreadySelected = _selectedFiles.any(
        (PlatformFile existing) => (existing.path ?? existing.name) == key,
      );

      if (!alreadySelected) {
        setState(() {
          _selectedFiles.add(archive);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Folder packaged: ${archive.name}')),
          );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not package folder: $error')),
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
        builder: (_) =>
            ConnectionScreen(files: List<PlatformFile>.of(_selectedFiles)),
      ),
    );
  }

  void _openReceiver() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ReceiverScreen()));
  }

  /// Asks before removing every selected file from the list. The files on the
  /// device are never touched; only the selection is cleared.
  Future<void> _confirmClearAll() async {
    if (_selectedFiles.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Clear all files?'),
          content: Text(
            'This removes ${fileCountLabel(_selectedFiles.length)} from '
            'your list. The files stay on your device.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep files'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear all'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _selectedFiles.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShareCare'),
        actions: <Widget>[
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Receive files',
            onPressed: _openReceiver,
            icon: const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                FadeSlideIn(child: _buildHero(context)),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 90),
                  child: _buildActions(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: _buildSelectionCard(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 270),
                  child: _HowItWorksCard(),
                ),
                const SizedBox(height: AppSpacing.lg),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 270),
                  child: InstructionCard(
                    icon: Icons.wifi,
                    title: 'Use the same network',
                    description:
                        'Connect both devices to the same Wi-Fi network, '
                        'or connect both devices through a compatible hotspot.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const BrandMark(size: 64),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Share files. Simply.',
                  style: context.text.headlineMedium,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Send files directly between devices on your local network.',
          style: context.text.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final ColorScheme scheme = context.colors;
    final bool hasFiles = _selectedFiles.isNotEmpty;

    final Widget sendTile = ActionTile(
      icon: Icons.upload_file_rounded,
      title: 'Send files',
      subtitle: _isPickingFiles
          ? 'Selecting files...'
          : hasFiles
          ? 'Add more files'
          : 'Choose files to share',
      onPressed: _isPickingFiles ? null : _pickFiles,
      loading: _isPickingFiles,
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );

    final Widget receiveTile = ActionTile(
      icon: Icons.download_rounded,
      title: 'Receive files',
      subtitle: 'Scan the code on the sending device',
      onPressed: _openReceiver,
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Stack the two actions on very narrow screens or large text sizes.
        final bool stacked =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;

        if (stacked) {
          return Column(
            children: <Widget>[
              sendTile,
              const SizedBox(height: AppSpacing.md),
              receiveTile,
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: sendTile),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: receiveTile),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectionCard(BuildContext context) {
    final bool hasFiles = _selectedFiles.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'Files to send',
            trailing: hasFiles
                ? TextButton.icon(
                    onPressed: _confirmClearAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Clear all'),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasFiles)
            const EmptyState(
              icon: Icons.folder_open_outlined,
              title: 'No files selected',
              message: 'Tap Send files above to choose what you want to share.',
            )
          else ...<Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                InfoChip(
                  icon: Icons.attach_file_rounded,
                  label: '${fileCountLabel(_selectedFiles.length)} selected',
                ),
                InfoChip(
                  icon: Icons.data_usage_rounded,
                  label: 'Total size: ${formatBytes(_totalBytes)}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedSize(
              duration: motionDuration(
                context,
                const Duration(milliseconds: 220),
              ),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                children: List<Widget>.generate(_selectedFiles.length, (
                  int index,
                ) {
                  final PlatformFile file = _selectedFiles[index];

                  return Padding(
                    key: ValueKey<String>(file.path ?? file.name),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: FileTile(
                      icon: iconForFile(file.name),
                      name: file.name,
                      subtitle: Text(
                        formatBytes(file.size),
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${file.name}',
                        onPressed: () {
                          setState(() {
                            _selectedFiles.removeAt(index);
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PressableScale(
            enabled: hasFiles,
            child: FilledButton.icon(
              onPressed: hasFiles ? _openSender : null,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Continue to connect'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _isPickingFiles ? null : _pickFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(
              _isPickingFiles ? 'Preparing folder...' : 'Send a folder',
            ),
          ),
          if (!hasFiles) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Select at least one file to continue.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: 'How sharing works'),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 1,
            title: 'Choose your files',
            description: 'Tap Send files and pick what you want to share.',
          ),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 2,
            title: 'Show the QR code',
            description: 'Tap Continue to connect, then Start sharing to show a QR code.',
          ),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 3,
            title: 'Scan and save',
            description:
                'On the other device, tap Receive files, scan the code and '
                'choose where to save.',
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Connection (sender) screen
// ===========================================================================

enum _SenderPhase { stopped, starting, noNetwork, waiting, connected, error }

const String _senderStoppedMessage = 'Tap Start sharing to show the QR code.';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.files});

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

  String _status = _senderStoppedMessage;
  String? _pairedDeviceAddress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _senderService = LocalSenderService(files: widget.files);
    _pairingSubscription = _senderService.pairingUpdates.listen((
      String address,
    ) {
      if (!mounted) return;
      setState(() {
        _pairedDeviceAddress = address;
        _status =
            'The other device is connected and can now receive '
            'your files.';
      });
    });
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
      _status = 'Getting ready to share your files...';
    });

    try {
      await _senderService.start();
      if (!mounted) return;

      setState(() {
        _status = _senderService.localAddress == null
            ? 'Sharing started, but no Wi-Fi or hotspot address was found. '
                  'Connect to a network, then stop and start sharing again.'
            : 'Waiting for another device to scan the QR code.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _status =
            'Sharing could not be started. Check your network and '
            'try again.';
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
      _status = _senderStoppedMessage;
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
          ? 'Connection test passed. This device is ready to share.'
          : 'Connection test failed. Stop sharing, check your network, '
                'then start again.';
      _isChecking = false;
    });
  }

  _SenderPhase _phaseFor(bool running) {
    if (_errorMessage != null) return _SenderPhase.error;
    if (_isStarting) return _SenderPhase.starting;
    if (!running) return _SenderPhase.stopped;
    if (_pairedDeviceAddress != null) return _SenderPhase.connected;
    if (_senderService.localAddress == null) return _SenderPhase.noNetwork;
    return _SenderPhase.waiting;
  }

  Widget _buildStatusBanner(_SenderPhase phase) {
    if (phase == _SenderPhase.error) {
      return StatusBanner(
        tone: StatusTone.error,
        title: 'Could not start sharing',
        message: _status,
        details: 'Details: $_errorMessage',
      );
    }

    if (phase == _SenderPhase.starting) {
      return StatusBanner(
        tone: StatusTone.progress,
        title: 'Starting',
        message: _status,
      );
    }

    if (phase == _SenderPhase.noNetwork) {
      return StatusBanner(
        tone: StatusTone.warning,
        title: 'No network found',
        message: _status,
      );
    }

    if (phase == _SenderPhase.connected) {
      return StatusBanner(
        tone: StatusTone.success,
        title: 'Device connected',
        message: _status,
      );
    }

    if (phase == _SenderPhase.waiting) {
      return StatusBanner(
        tone: StatusTone.info,
        icon: Icons.qr_code_scanner,
        title: 'Ready to connect',
        message: _status,
      );
    }

    return StatusBanner(
      tone: StatusTone.info,
      icon: Icons.pause_circle_outline_rounded,
      title: 'Not sharing yet',
      message: _status,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? qrData = _senderService.pairingData;
    final bool running = _senderService.isRunning;
    final _SenderPhase phase = _phaseFor(running);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect device'),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                _buildStatusBanner(phase),
                const SizedBox(height: AppSpacing.lg),
                _buildQrCard(context, qrData, running),
                if (running) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _buildDetailsCard(context),
                ],
                const SizedBox(height: AppSpacing.lg),
                const _ConnectStepsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, String? qrData, bool running) {
    final bool? healthPassed = _healthCheckPassed;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Connect a device',
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Start sharing, then scan the QR code using ShareCare on the '
            'receiving device.',
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // 254 = the 230 px QR code plus 12 px of white padding on each
          // side. Reserving it keeps the layout still when the code appears.
          SizedBox(
            height: 254,
            child: AnimatedSwitcher(
              duration: motionDuration(
                context,
                const Duration(milliseconds: 250),
              ),
              child: qrData != null && _senderService.localAddress != null
                  ? _QrTile(key: const ValueKey<String>('qr'), data: qrData)
                  : const _QrPlaceholder(key: ValueKey<String>('placeholder')),
            ),
          ),
          if (running) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: InfoChip(
                icon: Icons.insert_drive_file_outlined,
                label: '${fileCountLabel(widget.files.length)} ready to send',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: qrData == null
                  ? null
                  : () async {
                      final String code = qrData;
                      await Clipboard.setData(ClipboardData(text: code));

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pairing code copied.')),
                      );
                    },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy pairing code'),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PressableScale(
            enabled: !(_isStarting || running),
            child: FilledButton.icon(
              onPressed: _isStarting || running ? null : _startSender,
              icon: _isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _errorMessage != null
                          ? Icons.refresh_rounded
                          : Icons.play_arrow,
                    ),
              label: Text(
                _isStarting
                    ? 'Starting...'
                    : _errorMessage != null
                    ? 'Try again'
                    : 'Start sharing',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PressableScale(
            enabled: running,
            child: OutlinedButton.icon(
              onPressed: running ? _stopSender : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop sharing'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PressableScale(
            enabled: running && !_isChecking,
            child: OutlinedButton.icon(
              onPressed: running && !_isChecking ? _testSender : null,
              icon: _isChecking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(_isChecking ? 'Testing...' : 'Test connection'),
            ),
          ),
          if (healthPassed != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Semantics(
                liveRegion: true,
                child: InfoChip(
                  tone: healthPassed ? StatusTone.success : StatusTone.error,
                  icon: healthPassed
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  label: healthPassed
                      ? 'Connection test passed'
                      : 'Connection test failed',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context) {
    final String? pairedAddress = _pairedDeviceAddress;
    final String? pairingData = _senderService.pairingData;
    String? sessionToken;

    if (pairingData != null) {
      try {
        final dynamic decoded = jsonDecode(pairingData);

        if (decoded is Map<String, dynamic>) {
          final dynamic value = decoded['token'];

          if (value is String && value.isNotEmpty) {
            sessionToken = value;
          }
        }
      } catch (_) {
        // Pairing data may not be available yet.
      }
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        expandedAlignment: Alignment.centerLeft,
        leading: const Icon(Icons.info_outline_rounded),
        title: Text('Connection details', style: context.text.titleMedium),
        subtitle: const Text('For troubleshooting'),
        children: <Widget>[
          SelectableText(
            'Sender address: '
            '${_senderService.localAddress ?? "Not found"}',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Port: ${_senderService.port}'),
          if (sessionToken != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Session token',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(sessionToken),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: sessionToken!));

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session token copied.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy session token'),
              ),
            ),
          ],
          if (pairedAddress != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            SelectableText('Connected device address: $pairedAddress'),
          ],
        ],
      ),
    );
  }
}

class _QrTile extends StatelessWidget {
  const _QrTile({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'QR code for connecting another device',
        image: true,
        excludeSemantics: true,
        // The code stays black on white in both themes so cameras can
        // always read it.
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 230,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(Icons.qr_code_2, size: 72, color: scheme.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Start sharing to show the QR code',
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectStepsCard extends StatelessWidget {
  const _ConnectStepsCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: 'How to connect'),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 1,
            title: 'Join the same network',
            description:
                'Connect both devices to the same Wi-Fi network or hotspot.',
          ),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 2,
            title: 'Open Receive files',
            description:
                'On the other device, open ShareCare and tap Receive files.',
          ),
          SizedBox(height: AppSpacing.lg),
          StepRow(
            number: 3,
            title: 'Scan this QR code',
            description:
                'Point the other device\u2019s camera at the code above.',
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Receiver screen
// ===========================================================================

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
  final MobileScannerController _scannerController = MobileScannerController();

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

      final Map<String, dynamic> result = await _getJson(
        host,
        port,
        '/pair',
        token,
      );

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
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );

      final String body = await response.transform(utf8.decoder).join();

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
      final Map<String, dynamic> result = await _getJson(
        host,
        port,
        '/files',
        token,
      );

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
        queryParameters: <String, String>{'token': token, 'id': file.id},
      );

      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != HttpStatus.ok) {
        final String errorBody = await response.transform(utf8.decoder).join();

        throw HttpException(
          'Download failed (${response.statusCode}): $errorBody',
        );
      }

      final Directory tempDirectory = await Directory.systemTemp.createTemp(
        'sharecare_',
      );

      final String safeName = safeReceivedFileName(file.name);
      final File temporaryFile = File('${tempDirectory.path}/$safeName');

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
      if (FolderArchiveReceiver.isFolderArchiveName(safeName)) {
        if (mounted) {
          setState(() {
            _status = 'Preparing to extract the received folder...';
          });
        }

        final String? extractedFolder =
            await FolderArchiveReceiver.extractOnAndroid(
              zipPath: temporaryFile.path,
              suggestedFolderName:
                  FolderArchiveReceiver.folderNameFromArchiveName(safeName),
            );

        if (!mounted) return;

        if (extractedFolder == null) {
          setState(() {
            _status = 'Folder extraction cancelled.';
          });
        } else {
          setState(() {
            _savedFiles.add(file.id);
            _status = 'Folder "$extractedFolder" received successfully.';
          });
        }

        return;
      }

      if (!mounted) return;

      setState(() {
        _status = 'Download complete. Choose where to save $safeName.';
      });

      final String? savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: temporaryFile.path,
          fileName: safeName,
          mimeTypesFilter: <String>[mimeTypeForFile(safeName)],
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

  Widget _buildStatusBanner(bool paired) {
    final String? error = _errorMessage;

    if (error != null) {
      return StatusBanner(
        tone: StatusTone.error,
        title: paired
            ? 'Connected, but something went wrong'
            : 'Could not connect',
        message: _status,
        details: 'Details: $error',
      );
    }

    if (_downloadingId != null) {
      return StatusBanner(
        tone: StatusTone.progress,
        title: 'Receiving file',
        message: _status,
        progress: _downloadProgress,
        progressLabel: '${(_downloadProgress * 100).round()}% downloaded',
      );
    }

    if (_isConnecting || _isLoadingFiles) {
      return StatusBanner(
        tone: StatusTone.progress,
        title: 'Connecting',
        message: _status,
      );
    }

    if (paired) {
      return StatusBanner(
        tone: StatusTone.success,
        title: 'Connected',
        message: _status,
      );
    }

    return StatusBanner(
      tone: StatusTone.info,
      icon: Icons.qr_code_scanner,
      title: 'Ready to scan',
      message: _status,
    );
  }

  Widget _buildScannerCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.xl,
      child: SizedBox(
        height: 360,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            MobileScanner(controller: _scannerController, onDetect: _onDetect),
            const IgnorePointer(child: _ScannerOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard(BuildContext context) {
    final StatusColors status = context.statusColors;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        children: <Widget>[
          IconBadge(
            icon: Icons.check_rounded,
            size: 72,
            circular: true,
            background: status.successContainer,
            foreground: status.onSuccessContainer,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Connected to the sending device',
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedFileTile(BuildContext context, ReceivedFile file) {
    final bool downloading = _downloadingId == file.id;
    final bool saved = _savedFiles.contains(file.id);
    final ColorScheme scheme = context.colors;
    final StatusColors status = context.statusColors;

    Widget? trailing;

    if (downloading) {
      trailing = SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              value: _downloadProgress,
              strokeWidth: 3,
              semanticsLabel: 'Downloading ${file.name}',
            ),
          ),
        ),
      );
    } else if (!saved) {
      trailing = IconButton.filledTonal(
        tooltip: 'Receive ${file.name}',
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: _downloadingId == null ? () => _receiveFile(file) : null,
        icon: const Icon(Icons.download_rounded),
      );
    }

    return Padding(
      key: ValueKey<String>(file.id),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FileTile(
        standalone: true,
        icon: iconForFile(file.name),
        name: file.name,
        subtitle: Wrap(
          spacing: AppSpacing.md,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              formatBytes(file.size),
              style: context.text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (saved)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: status.success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Saved',
                    style: context.text.bodyMedium?.copyWith(
                      color: status.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: trailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool paired = _host != null && _token != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive files'),
        actions: <Widget>[
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: paired ? null : () => _scannerController.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                if (!paired)
                  _buildScannerCard()
                else
                  _buildConnectedCard(context),
                const SizedBox(height: AppSpacing.lg),
                _buildStatusBanner(paired),
                if (!paired && _hasProcessedCode && !_isConnecting) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  PressableScale(
                    child: FilledButton.icon(
                      onPressed: _scanAgain,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try scanning again'),
                    ),
                  ),
                ],
                if (paired) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _scanAgain,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: 'Files available (${_files.length})'),
                  const SizedBox(height: AppSpacing.md),
                  if (_files.isEmpty && !_isLoadingFiles)
                    const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: 'No files to receive',
                      message: 'No files were selected on the sending device.',
                    ),
                  ..._files.map(
                    (ReceivedFile file) =>
                        _buildReceivedFileTile(context, file),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Tap the download button beside a file. This device will '
                    'then ask where to save it.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!paired) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  const InstructionCard(
                    icon: Icons.wifi,
                    title: 'Network required',
                    description:
                        'Both devices must be able to communicate over the '
                        'same local network, or connect both devices through '
                        'a compatible hotspot. Mobile data alone is not '
                        'enough.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Corner guides and a hint drawn over the live camera view.
///
/// Colors here are fixed on purpose: they sit on top of the camera image, not
/// on the app theme, so they must stay readable in both themes.
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const CustomPaint(painter: _ScannerCornersPainter()),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(150),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.qr_code_scanner, size: 18, color: Colors.white),
                  SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Point the camera at the QR code',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerCornersPainter extends CustomPainter {
  const _ScannerCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide * 0.62;
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 12),
      width: side,
      height: side,
    );
    final double arm = side * 0.22;

    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + arm)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + arm, rect.top),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - arm, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + arm),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - arm)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + arm, rect.bottom),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - arm, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// Shared instruction card
// ===========================================================================

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
    return AppCard(
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IconBadge(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
