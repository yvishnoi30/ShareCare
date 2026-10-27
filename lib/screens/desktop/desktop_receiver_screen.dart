import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

import '../../platform/file_saver.dart';
import '../../platform/windows_file_saver.dart';
import '../../transfer/receiver_service.dart';
import '../../transfer/transfer_models.dart';
import '../../transfer/folder_archive_receiver.dart';
import '../../ui/instruction_card.dart';
import '../../ui/ui.dart';
import '../../utils/file_utils.dart';

enum _PairMode { code, manual }

enum _ItemPhase { idle, queued, downloading, saved, failed }

class _ItemStatus {
  const _ItemStatus(this.phase, {this.message});

  final _ItemPhase phase;
  final String? message;
}

/// Desktop receiver with webcam QR scanning, pairing-code paste, and manual details.
class DesktopReceiverScreen extends StatefulWidget {
  const DesktopReceiverScreen({super.key});

  @override
  State<DesktopReceiverScreen> createState() =>
      _DesktopReceiverScreenState();
}

class _DesktopReceiverScreenState extends State<DesktopReceiverScreen> {
  final WindowsFileSaver _saver = WindowsFileSaver();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  _PairMode _mode = _PairMode.code;

  ReceiverService? _service;
  PairingInfo? _pairing;
  List<ReceivedFile> _files = <ReceivedFile>[];
  final Set<String> _selectedIds = <String>{};
  final Map<String, _ItemStatus> _items = <String, _ItemStatus>{};

  bool _isConnecting = false;
  bool _isRefreshing = false;
  bool _isDownloading = false;
  bool _cancelRequested = false;

  /// Changes on every connect/disconnect so a download loop that belongs to an
  /// old connection can tell it should stop touching the screen.
  int _sessionId = 0;

  double _progress = 0;

  String _status = 'Paste the pairing code from the sending device.';
  String? _errorMessage;

  @override
  void dispose() {
    _sessionId++;
    _service?.dispose();
    _codeController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Pairing
  // -------------------------------------------------------------------------

  Future<void> _scanPairingCode() async {
    if (_isConnecting) return;

    try {
      final String? scannedCode = await UniversalBarcodeScanner.scan(
        context,
        scanFormat: ScanFormat.onlyQrCode,
        scanWindow: ScanWindow.square,
        bar: const ScannerBar(title: 'Scan ShareCare QR code'),
        beep: true,
      );

      if (!mounted || scannedCode == null || scannedCode.trim().isEmpty) {
        return;
      }

      final String payload = scannedCode.trim();

      try {
        PairingInfo.fromPayload(payload);
      } on TransferException catch (error) {
        setState(() {
          _errorMessage = error.message;
          _status = 'The scanned QR code is not a valid ShareCare pairing code.';
        });
        return;
      }

      _codeController.text = payload;
      setState(() {
        _mode = _PairMode.code;
        _errorMessage = null;
        _status = 'QR code scanned. Connecting...';
      });

      // Wait for the code-entry field to rebuild in code mode before validating
      // the form and starting the normal pairing flow.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _connect();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _status = 'Could not open the webcam scanner. Check camera access and try again.';
      });
    }
  }

  Future<void> _pasteCode() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;

    if (!mounted) return;

    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The clipboard does not contain text.')),
      );
      return;
    }

    setState(() {
      _codeController.text = text.trim();
      _errorMessage = null;
    });
  }

  String? _validateCode(String? value) {
    final String text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Paste the pairing code from the sending device.';
    }

    try {
      PairingInfo.fromPayload(text);
    } on TransferException catch (error) {
      return error.message;
    }

    return null;
  }

  PairingInfo? _readPairing() {
    try {
      if (_mode == _PairMode.code) {
        return PairingInfo.fromPayload(_codeController.text);
      }

      return PairingInfo.fromFields(
        host: _hostController.text,
        port: _portController.text,
        token: _tokenController.text,
      );
    } on TransferException catch (error) {
      setState(() {
        _errorMessage = error.message;
        _status = 'Check the pairing details.';
      });
      return null;
    }
  }

  Future<void> _connect() async {
    if (_isConnecting) return;

    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final PairingInfo? pairing = _readPairing();
    if (pairing == null) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _status = 'Connecting to ${pairing.host}:${pairing.port}...';
    });

    final ReceiverService service = ReceiverService(
      pairing: pairing,
      fileSaver: _saver,
    );

    try {
      await service.pair();
      final List<ReceivedFile> files = await service.fetchFiles();

      if (!mounted) {
        service.dispose();
        return;
      }

      setState(() {
        _sessionId++;
        _service = service;
        _pairing = pairing;
        _files = files;
        _items.clear();
        _selectedIds
          ..clear()
          ..addAll(files.map((ReceivedFile f) => f.id));
        _status = files.isEmpty
            ? 'Connected, but the sender has no files to share.'
            : 'Connected. Choose the files you want, then select Download.';
      });
    } catch (error) {
      service.dispose();
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _status = 'Could not connect.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _disconnect() {
    _sessionId++;
    _cancelRequested = true;
    _service?.dispose();

    setState(() {
      _service = null;
      _pairing = null;
      _files = <ReceivedFile>[];
      _selectedIds.clear();
      _items.clear();
      _isDownloading = false;
      _progress = 0;
      _errorMessage = null;
      _status = 'Disconnected. Paste a pairing code to connect again.';
    });
  }

  Future<void> _refreshFiles() async {
    final ReceiverService? service = _service;
    if (service == null || _isRefreshing || _isDownloading) return;

    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      final List<ReceivedFile> files = await service.fetchFiles();
      if (!mounted) return;

      setState(() {
        _files = files;
        final Set<String> ids = files.map((ReceivedFile f) => f.id).toSet();
        _selectedIds.removeWhere((String id) => !ids.contains(id));
        _items.removeWhere((String id, _ItemStatus _) => !ids.contains(id));
        _status = 'File list updated.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _status = 'Could not update the file list.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Destination folder
  // -------------------------------------------------------------------------

  Future<bool> _chooseFolder() async {
    try {
      final bool chosen = await _saver.chooseDestination();

      if (chosen && mounted) {
        setState(() {
          _errorMessage = null;
        });
      }

      return chosen;
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
          _status = 'Could not use that folder.';
        });
      }
      return false;
    }
  }

  Future<void> _openFolder() async {
    final String? path = _saver.destinationPath;
    if (path == null) return;

    try {
      await Process.start(
        'explorer.exe',
        <String>[path],
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the folder: $error')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Downloading
  // -------------------------------------------------------------------------

  void _toggleAll(bool selectAll) {
    setState(() {
      _selectedIds.clear();

      if (selectAll) {
        for (final ReceivedFile file in _files) {
          if (_items[file.id]?.phase != _ItemPhase.saved) {
            _selectedIds.add(file.id);
          }
        }
      }
    });
  }

  void _cancelDownload() {
    if (!_isDownloading) return;

    _cancelRequested = true;
    _service?.cancelDownload();

    setState(() {
      _status = 'Cancelling...';
    });
  }

  Future<void> _downloadSelected() async {
    final ReceiverService? service = _service;
    if (service == null || _isDownloading) return;

    final List<ReceivedFile> queue = _files
        .where((ReceivedFile f) =>
            _selectedIds.contains(f.id) &&
            _items[f.id]?.phase != _ItemPhase.saved)
        .toList();

    if (queue.isEmpty) return;

    if (_saver.destinationPath == null) {
      final bool chosen = await _chooseFolder();
      if (!chosen || !mounted) return;
    }

    // The connection may have been closed while the folder dialog was open.
    if (!identical(_service, service)) return;

    final int session = _sessionId;

    setState(() {
      _isDownloading = true;
      _cancelRequested = false;
      _errorMessage = null;

      for (final ReceivedFile file in queue) {
        _items[file.id] = const _ItemStatus(_ItemPhase.queued);
      }
    });

    int saved = 0;
    int failed = 0;
    String? lastError;
    bool cancelled = false;

    for (int index = 0; index < queue.length; index++) {
      final ReceivedFile file = queue[index];

      if (_cancelRequested || !mounted || session != _sessionId) {
        cancelled = true;
        break;
      }

      setState(() {
        _progress = 0;
        _items[file.id] = const _ItemStatus(_ItemPhase.downloading);
        _status = 'Downloading ${file.name} '
            '(${index + 1} of ${queue.length})...';
      });

      try {
        final SaveResult result = await service.receiveFile(
          file,
          onProgress: (int received, int total) {
            if (!mounted || session != _sessionId) return;

            setState(() {
              _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
            });
          },
        );

        if (!mounted || session != _sessionId) return;

        if (result.wasSaved) {
          if (FolderArchiveReceiver.isFolderArchiveName(file.name)) {
            final String? destinationPath = _saver.destinationPath;
            final String? savedName = result.savedName;

            if (destinationPath == null || savedName == null) {
              throw StateError(
                'The folder archive was downloaded, but its save location '
                'could not be determined.',
              );
            }

            String archivePath = result.location ??
                '$destinationPath${Platform.pathSeparator}$savedName';

            if (!await File(archivePath).exists()) {
              archivePath =
                  '$destinationPath${Platform.pathSeparator}$savedName';
            }

            try {
              final String extractedPath =
                  await FolderArchiveReceiver.extractOnWindows(
                zipPath: archivePath,
                destinationDirectory: destinationPath,
                suggestedFolderName:
                    FolderArchiveReceiver.folderNameFromArchiveName(file.name),
              );

              // The ZIP is temporary transport data. Keep it if extraction
              // fails, but remove it after the folder is restored successfully.
              try {
                await File(archivePath).delete();
              } catch (_) {
                // The extracted folder is already safe; ZIP cleanup is best effort.
              }

              final String extractedFolderName = extractedPath
                  .split(Platform.pathSeparator)
                  .last;
              saved++;
              if (!mounted || session != _sessionId) return;
              setState(() {
                _items[file.id] = _ItemStatus(
                  _ItemPhase.saved,
                  message: 'Extracted to $extractedFolderName',
                );
                _selectedIds.remove(file.id);
              });
            } catch (error) {
              failed++;
              lastError = 'Folder archive downloaded, but extraction failed. '
                  'The ZIP was kept at "$archivePath". Details: $error';
              if (!mounted || session != _sessionId) return;
              setState(() {
                _items[file.id] = _ItemStatus(
                  _ItemPhase.failed,
                  message: lastError,
                );
                _selectedIds.remove(file.id);
              });
            }
          } else {
            saved++;
            setState(() {
              _items[file.id] =
                  _ItemStatus(_ItemPhase.saved, message: result.savedName);
              _selectedIds.remove(file.id);
            });
          }
        } else {
          setState(() {
            _items[file.id] = const _ItemStatus(_ItemPhase.idle);
          });
        }
      } on TransferCancelledException {
        cancelled = true;

        if (mounted && session == _sessionId) {
          setState(() {
            _items[file.id] = const _ItemStatus(_ItemPhase.idle);
          });
        }
        break;
      } catch (error) {
        failed++;
        lastError = error.toString();

        if (!mounted || session != _sessionId) return;

        final String message = lastError;
        setState(() {
          _items[file.id] = _ItemStatus(_ItemPhase.failed, message: message);
        });
      }
    }

    if (!mounted || session != _sessionId) return;

    setState(() {
      _isDownloading = false;
      _progress = 0;

      for (final ReceivedFile file in queue) {
        if (_items[file.id]?.phase == _ItemPhase.queued) {
          _items[file.id] = const _ItemStatus(_ItemPhase.idle);
        }
      }

      if (cancelled) {
        _status = saved == 0
            ? 'Download cancelled.'
            : 'Download cancelled. ${fileCountLabel(saved)} saved.';
      } else if (failed > 0) {
        _errorMessage = lastError;
        _status = '$saved saved, $failed could not be received. '
            'See the list for details.';
      } else {
        _status = 'Saved ${fileCountLabel(saved)} to '
            '${_saver.destinationPath ?? 'the chosen folder'}.';
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool connected = _service != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive files'),
        actions: const <Widget>[
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: connected
            ? _buildConnectedView(context)
            : _buildPairingView(context),
      ),
    );
  }

  Widget _buildBanner(bool connected) {
    final String? error = _errorMessage;

    if (error != null) {
      return StatusBanner(
        tone: StatusTone.error,
        title: connected ? 'Something went wrong' : 'Could not connect',
        message: _status,
        details: 'Details: $error',
      );
    }

    if (_isDownloading) {
      return StatusBanner(
        tone: StatusTone.progress,
        title: 'Receiving files',
        message: _status,
        progress: _progress,
        progressLabel: '${(_progress * 100).round()}% of this file',
      );
    }

    if (_isConnecting || _isRefreshing) {
      return StatusBanner(
        tone: StatusTone.progress,
        title: _isConnecting ? 'Connecting' : 'Updating',
        message: _status,
      );
    }

    if (connected) {
      return StatusBanner(
        tone: StatusTone.success,
        title: 'Connected',
        message: _status,
      );
    }

    return StatusBanner(
      tone: StatusTone.info,
      icon: Icons.link_rounded,
      title: 'Ready to connect',
      message: _status,
    );
  }

  // ----- Pairing view -------------------------------------------------------

  Widget _buildPairingView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildBanner(false),
              const SizedBox(height: AppSpacing.lg),
              _buildPairingCard(context),
              const SizedBox(height: AppSpacing.lg),
              const InstructionCard(
                icon: Icons.help_outline_rounded,
                title: 'Where do I find the pairing code?',
                description:
                    'On the sending device, start sharing. On Windows, '
                    'choose Copy pairing code. On Android, open Connection '
                    'details and choose Copy pairing code. Send the code to '
                    'this computer in a message or email, then paste it '
                    'here.',
              ),
              const SizedBox(height: AppSpacing.lg),
              const InstructionCard(
                icon: Icons.wifi,
                title: 'Network required',
                description:
                    'Both devices must be on the same Wi-Fi network or '
                    'hotspot. If connecting fails, check that sharing is '
                    'still running on the sender and that its firewall '
                    'allows ShareCare.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPairingCard(BuildContext context) {
    final bool busy = _isConnecting;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _connect,
      },
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Connect to a sending device',
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Paste the pairing code from the sender, or type its '
                'details.',
                style: context.text.bodyLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<_PairMode>(
                segments: const <ButtonSegment<_PairMode>>[
                  ButtonSegment<_PairMode>(
                    value: _PairMode.code,
                    icon: Icon(Icons.content_paste_rounded),
                    label: Text('Paste code'),
                  ),
                  ButtonSegment<_PairMode>(
                    value: _PairMode.manual,
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Enter details'),
                  ),
                ],
                selected: <_PairMode>{_mode},
                onSelectionChanged: busy
                    ? null
                    : (Set<_PairMode> selection) {
                        setState(() {
                          _mode = selection.first;
                          _errorMessage = null;
                        });
                      },
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _scanPairingCode,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR with webcam'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_mode == _PairMode.code)
                TextFormField(
                  controller: _codeController,
                  enabled: !busy,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  validator: _validateCode,
                  decoration: InputDecoration(
                    labelText: 'Pairing code',
                    hintText: '{"app":"ShareCare","version":1,...}',
                    helperText: 'Press Ctrl+Enter to connect.',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Paste from clipboard',
                      onPressed: busy ? null : _pasteCode,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                )
              else ...<Widget>[
                TextFormField(
                  controller: _hostController,
                  enabled: !busy,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  validator: PairingInfo.validateHost,
                  decoration: const InputDecoration(
                    labelText: 'Sender address',
                    hintText: '192.168.1.20',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _portController,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: PairingInfo.validatePort,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '54321',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _tokenController,
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _connect(),
                  validator: PairingInfo.validateToken,
                  decoration: const InputDecoration(
                    labelText: 'Session token',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(180, 48),
                  ),
                  onPressed: busy ? null : _connect,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(busy ? 'Connecting...' : 'Connect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- Connected view -----------------------------------------------------

  Widget _buildConnectedView(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 960;

        final Widget banner = _buildBanner(true);
        final Widget connection = _buildConnectionCard(context);
        final Widget destination = _buildDestinationCard(context);
        final Widget files = _buildFilesCard(context);

        final Widget content = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        banner,
                        const SizedBox(height: AppSpacing.lg),
                        connection,
                        const SizedBox(height: AppSpacing.lg),
                        destination,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 6, child: files),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  banner,
                  const SizedBox(height: AppSpacing.lg),
                  connection,
                  const SizedBox(height: AppSpacing.lg),
                  destination,
                  const SizedBox(height: AppSpacing.lg),
                  files,
                ],
              );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    final StatusColors status = context.statusColors;
    final PairingInfo? pairing = _pairing;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                icon: Icons.check_rounded,
                size: 48,
                circular: true,
                background: status.successContainer,
                foreground: status.onSuccessContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Connected to the sending device',
                      style: context.text.titleMedium,
                    ),
                    if (pairing != null)
                      SelectableText('${pairing.host}:${pairing.port}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(150, 44),
                ),
                onPressed:
                    _isDownloading || _isRefreshing ? null : _refreshFiles,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh list'),
              ),
              TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationCard(BuildContext context) {
    final String? path = _saver.destinationPath;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Save to'),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.folder_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SelectableText(
                  path ?? 'No folder chosen yet. You will be asked when you '
                      'start a download.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(170, 44),
                ),
                onPressed: _isDownloading ? null : _chooseFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(path == null ? 'Choose folder' : 'Change folder'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(150, 44),
                ),
                onPressed: path == null ? null : _openFolder,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open folder'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Files that already exist are never overwritten. A new copy is '
            'saved as "name (1)".',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesCard(BuildContext context) {
    final ColorScheme scheme = context.colors;

    final List<ReceivedFile> selectable = _files
        .where((ReceivedFile f) => _items[f.id]?.phase != _ItemPhase.saved)
        .toList();
    final bool allSelected = selectable.isNotEmpty &&
        selectable.every((ReceivedFile f) => _selectedIds.contains(f.id));

    int selectedBytes = 0;
    int selectedCount = 0;
    for (final ReceivedFile file in _files) {
      if (_selectedIds.contains(file.id) &&
          _items[file.id]?.phase != _ItemPhase.saved) {
        selectedBytes += file.size;
        selectedCount++;
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: 'Available files (${_files.length})'),
          const SizedBox(height: AppSpacing.md),
          if (_files.isEmpty)
            const EmptyState(
              icon: Icons.folder_off_outlined,
              title: 'No files to receive',
              message: 'No files were selected on the sending device.',
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Tooltip(
                  message: 'Select all files',
                  child: Checkbox(
                    value: allSelected,
                    onChanged: _isDownloading || selectable.isEmpty
                        ? null
                        : (bool? _) => _toggleAll(!allSelected),
                  ),
                ),
                Expanded(
                  child: Text(
                    selectedCount == 0
                        ? 'Nothing selected'
                        : '${fileCountLabel(selectedCount)} selected, '
                            '${formatBytes(selectedBytes)}',
                    style: context.text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._files.map(
              (ReceivedFile file) => _buildFileRow(context, file),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.icon(
                  autofocus: true,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                  onPressed: _isDownloading || selectedCount == 0
                      ? null
                      : _downloadSelected,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    selectedCount == 0
                        ? 'Download selected'
                        : 'Download selected ($selectedCount)',
                  ),
                ),
                if (_isDownloading)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(130, 48),
                    ),
                    onPressed: _cancelDownload,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, ReceivedFile file) {
    final ColorScheme scheme = context.colors;
    final StatusColors status = context.statusColors;

    final _ItemStatus? item = _items[file.id];
    final _ItemPhase phase = item?.phase ?? _ItemPhase.idle;
    final String? message = item?.message;
    final bool saved = phase == _ItemPhase.saved;

    Widget? statusLine;
    Widget? trailing;

    switch (phase) {
      case _ItemPhase.idle:
        break;
      case _ItemPhase.queued:
        statusLine = Text(
          'Waiting...',
          style: context.text.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
        break;
      case _ItemPhase.downloading:
        statusLine = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Downloading ${(_progress * 100).round()}%',
              style: context.text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        break;
      case _ItemPhase.saved:
        trailing = Icon(Icons.check_circle_rounded, color: status.success);
        statusLine = Text(
          message != null && message != file.name
              ? 'Saved as $message'
              : 'Saved',
          style: context.text.bodyMedium?.copyWith(
            color: status.success,
            fontWeight: FontWeight.w700,
          ),
        );
        break;
      case _ItemPhase.failed:
        trailing = Tooltip(
          message: message ?? 'Could not be received',
          child: Icon(Icons.error_outline, color: scheme.error),
        );
        statusLine = Text(
          message ?? 'Could not be received',
          style: context.text.bodyMedium?.copyWith(color: scheme.error),
        );
        break;
    }

    return Padding(
      key: ValueKey<String>(file.id),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: 'Select ${file.name}',
            child: Checkbox(
              value: _selectedIds.contains(file.id),
              onChanged: _isDownloading || saved
                  ? null
                  : (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(file.id);
                        } else {
                          _selectedIds.remove(file.id);
                        }
                      });
                    },
            ),
          ),
          Expanded(
            child: FileTile(
              standalone: true,
              icon: iconForFile(file.name),
              name: file.name,
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    formatBytes(file.size),
                    style: context.text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  ?statusLine,
                ],
              ),
              trailing: trailing,
            ),
          ),
        ],
      ),
    );
  }
}