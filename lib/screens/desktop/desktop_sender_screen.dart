import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../transfer/sender_service.dart';
import '../../ui/instruction_card.dart';
import '../../ui/qr_tile.dart';
import '../../ui/ui.dart';
import '../../utils/file_utils.dart';

enum _Phase { stopped, starting, noNetwork, waiting, connected, error }

const String _stoppedMessage =
    'Choose Start sharing to show the QR code and pairing code.';

class _FileProgress {
  const _FileProgress({
    required this.state,
    required this.sent,
    required this.total,
  });

  final SendState state;
  final int sent;
  final int total;

  double get fraction => total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0;
}

/// Desktop sender: starts the local server and shows everything a receiver
/// needs. Android receivers scan the QR code; Windows receivers paste the
/// pairing code or type the details.
class DesktopSenderScreen extends StatefulWidget {
  const DesktopSenderScreen({super.key, required this.files});

  final List<PlatformFile> files;

  @override
  State<DesktopSenderScreen> createState() => _DesktopSenderScreenState();
}

class _DesktopSenderScreenState extends State<DesktopSenderScreen> {
  late final LocalSenderService _service;
  StreamSubscription<String>? _pairingSubscription;
  StreamSubscription<SendEvent>? _sendSubscription;

  final Map<int, _FileProgress> _progress = <int, _FileProgress>{};

  bool _isStarting = false;
  bool _isChecking = false;
  bool? _healthPassed;

  String _status = _stoppedMessage;
  String? _pairedAddress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _service = LocalSenderService(files: widget.files);

    _pairingSubscription = _service.pairingUpdates.listen((String address) {
      if (!mounted) return;
      setState(() {
        _pairedAddress = address;
        _status = 'A device is connected and can now download your files.';
      });
    });

    _sendSubscription = _service.sendEvents.listen(_onSendEvent);
  }

  @override
  void dispose() {
    _pairingSubscription?.cancel();
    _sendSubscription?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onSendEvent(SendEvent event) {
    if (!mounted) return;

    setState(() {
      _progress[event.fileId] = _FileProgress(
        state: event.state,
        sent: event.sentBytes,
        total: event.totalBytes,
      );
    });
  }

  Future<void> _start() async {
    if (_isStarting || _service.isRunning) return;

    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _healthPassed = null;
      _pairedAddress = null;
      _progress.clear();
      _status = 'Getting ready to share your files...';
    });

    try {
      await _service.start();
      if (!mounted) return;

      setState(() {
        _status = _service.localAddress == null
            ? 'Sharing started, but no Wi-Fi or hotspot address was found. '
                'Connect to a network, then choose Refresh network.'
            : 'Waiting for a device to scan the QR code or use the pairing '
                'code.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _status = 'Sharing could not be started. Check your network and '
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

  Future<void> _stop() async {
    await _service.stop();
    if (!mounted) return;

    setState(() {
      _status = _stoppedMessage;
      _healthPassed = null;
      _pairedAddress = null;
      _errorMessage = null;
      _progress.clear();
    });
  }

  Future<void> _test() async {
    if (!_service.isRunning || _isChecking) return;

    setState(() {
      _isChecking = true;
      _healthPassed = null;
    });

    final bool result = await _service.checkHealth();
    if (!mounted) return;

    setState(() {
      _healthPassed = result;
      _status = result
          ? 'ShareCare is listening on this computer.'
          : 'ShareCare is not answering on this computer. Stop sharing and '
              'start again.';
      _isChecking = false;
    });
  }

  Future<void> _refreshNetwork() async {
    await _service.refreshAddresses();
    if (!mounted) return;

    setState(() {
      if (_service.isRunning && _service.localAddress == null) {
        _status = 'No Wi-Fi or hotspot address found. Connect to a network '
            'and try again.';
      }
    });
  }

  void _selectAddress(String? address) {
    if (address == null) return;

    if (_service.selectAddress(address)) {
      setState(() {});
    }
  }

  Future<void> _copy(String label, String? value) async {
    if (value == null || value.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  _Phase _phaseFor(bool running) {
    if (_errorMessage != null) return _Phase.error;
    if (_isStarting) return _Phase.starting;
    if (!running) return _Phase.stopped;
    if (_pairedAddress != null) return _Phase.connected;
    if (_service.localAddress == null) return _Phase.noNetwork;
    return _Phase.waiting;
  }

  Widget _buildBanner(_Phase phase) {
    switch (phase) {
      case _Phase.error:
        return StatusBanner(
          tone: StatusTone.error,
          title: 'Could not start sharing',
          message: _status,
          details: 'Details: $_errorMessage',
        );
      case _Phase.starting:
        return StatusBanner(
          tone: StatusTone.progress,
          title: 'Starting',
          message: _status,
        );
      case _Phase.noNetwork:
        return StatusBanner(
          tone: StatusTone.warning,
          title: 'No network found',
          message: _status,
        );
      case _Phase.connected:
        return StatusBanner(
          tone: StatusTone.success,
          title: 'Device connected',
          message: _status,
        );
      case _Phase.waiting:
        return StatusBanner(
          tone: StatusTone.info,
          icon: Icons.qr_code_scanner,
          title: 'Ready to connect',
          message: _status,
        );
      case _Phase.stopped:
        return StatusBanner(
          tone: StatusTone.info,
          icon: Icons.pause_circle_outline_rounded,
          title: 'Not sharing yet',
          message: _status,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool running = _service.isRunning;
    final _Phase phase = _phaseFor(running);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send files'),
        actions: const <Widget>[
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 920;

            final Widget banner = _buildBanner(phase);
            final Widget qrCard = _buildQrCard(context, running);
            final Widget filesCard = _buildFilesCard(context, running);
            const Widget helpCard = InstructionCard(
              icon: Icons.shield_outlined,
              title: 'If the other device cannot connect',
              description:
                  'The first time you start sharing, Windows may ask to allow '
                  'ShareCare through Windows Defender Firewall. Choose Allow '
                  'access for private networks. You can change this later in '
                  'Windows Security, under Firewall & network protection, '
                  'Allow an app through firewall. Both devices must be on '
                  'the same Wi-Fi network or hotspot.',
            );

            final Widget content;

            if (wide) {
              content = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        banner,
                        const SizedBox(height: AppSpacing.lg),
                        qrCard,
                        const SizedBox(height: AppSpacing.lg),
                        helpCard,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (running) ...<Widget>[
                          _buildDetailsCard(context),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        filesCard,
                      ],
                    ),
                  ),
                ],
              );
            } else {
              content = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  banner,
                  const SizedBox(height: AppSpacing.lg),
                  qrCard,
                  if (running) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    _buildDetailsCard(context),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  filesCard,
                  const SizedBox(height: AppSpacing.lg),
                  helpCard,
                ],
              );
            }

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
        ),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, bool running) {
    final String? qrData = _service.pairingData;
    final bool? healthPassed = _healthPassed;

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
            'Android: open Receive files and scan this code. '
            'Windows: copy the pairing code from the details panel.',
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // 284 = the 260 px QR code plus 12 px of padding on each side.
          SizedBox(
            height: 284,
            child: AnimatedSwitcher(
              duration:
                  motionDuration(context, const Duration(milliseconds: 250)),
              child: qrData != null && _service.localAddress != null
                  ? QrTile(
                      key: const ValueKey<String>('qr'),
                      data: qrData,
                      size: 260,
                    )
                  : const QrPlaceholder(
                      key: ValueKey<String>('placeholder'),
                    ),
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
          ],
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.icon(
                autofocus: true,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(170, 48),
                ),
                onPressed: _isStarting || running ? null : _start,
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
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(150, 48),
                ),
                onPressed: running ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop sharing'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(170, 48),
                ),
                onPressed: running && !_isChecking ? _test : null,
                icon: _isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                label: Text(_isChecking ? 'Testing...' : 'Test connection'),
              ),
            ],
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
                      ? 'Listening on this computer'
                      : 'Not answering on this computer',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This test only checks this computer. It cannot tell whether '
              'Windows Firewall will let other devices in.',
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

  Widget _buildDetailsCard(BuildContext context) {
    final ColorScheme scheme = context.colors;
    final String? code = _service.pairingData;
    final List<LocalAddress> addresses = _service.candidateAddresses;
    final String? selected = _service.localAddress;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Connection details'),
          const SizedBox(height: AppSpacing.md),
          Text(
            'For a Windows receiver: copy the pairing code, send it to the '
            'other computer, and paste it on its Receive files screen.',
            style: context.text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SelectableText(
              code ?? 'No address available yet.',
              style: context.text.bodySmall?.copyWith(
                fontFamilyFallback: const <String>[
                  'Consolas',
                  'Courier New',
                  'monospace',
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(180, 44)),
              onPressed:
                  code == null ? null : () => _copy('Pairing code', code),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy pairing code'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (addresses.length > 1) ...<Widget>[
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Network address to use',
                helperText:
                    'This PC has several network adapters. Pick the one '
                    'on the same Wi-Fi as the other device.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selected,
                  items: addresses
                      .map(
                        (LocalAddress a) => DropdownMenuItem<String>(
                          value: a.address,
                          child: Text(
                            a.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _selectAddress,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _DetailRow(
            label: 'Sender address',
            value: selected ?? 'Not found',
            onCopy: selected == null
                ? null
                : () => _copy('Sender address', selected),
          ),
          _DetailRow(
            label: 'Port',
            value: '${_service.port}',
            onCopy: () => _copy('Port', '${_service.port}'),
          ),
          _DetailRow(
            label: 'Session token',
            value: _service.token ?? '',
            onCopy: () => _copy('Session token', _service.token),
          ),
          if (_pairedAddress != null)
            _DetailRow(label: 'Connected device', value: _pairedAddress!),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Anyone who has the pairing code or token can download the files '
            'you are sharing while sharing is on. Only give it to your own '
            'devices.',
            style: context.text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _refreshNetwork,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh network'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesCard(BuildContext context, bool running) {
    final ColorScheme scheme = context.colors;
    final StatusColors status = context.statusColors;

    int totalBytes = 0;
    for (final PlatformFile file in widget.files) {
      totalBytes += file.size;
    }

    final int completed = _progress.values
        .where((_FileProgress p) => p.state == SendState.completed)
        .length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Files ready to send'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              InfoChip(
                icon: Icons.attach_file_rounded,
                label: fileCountLabel(widget.files.length),
              ),
              InfoChip(
                icon: Icons.data_usage_rounded,
                label: 'Total size: ${formatBytes(totalBytes)}',
              ),
              if (running && _progress.isNotEmpty)
                InfoChip(
                  tone: StatusTone.success,
                  icon: Icons.check_circle_rounded,
                  label: '$completed of ${widget.files.length} sent',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...List<Widget>.generate(widget.files.length, (int index) {
            final PlatformFile file = widget.files[index];
            final _FileProgress? progress = _progress[index];

            Widget? statusLine;
            Widget? trailing;

            if (progress != null) {
              switch (progress.state) {
                case SendState.started:
                case SendState.progress:
                  statusLine = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      LinearProgressIndicator(value: progress.fraction),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Sending ${(progress.fraction * 100).round()}%',
                        style: context.text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                  break;
                case SendState.completed:
                  trailing = Icon(
                    Icons.check_circle_rounded,
                    color: status.success,
                  );
                  statusLine = Text(
                    'Sent',
                    style: context.text.bodyMedium?.copyWith(
                      color: status.success,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                  break;
                case SendState.failed:
                  trailing = Icon(Icons.error_outline, color: scheme.error);
                  statusLine = Text(
                    'Interrupted. The receiver can try again.',
                    style: context.text.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  );
                  break;
              }
            }

            return Padding(
              key: ValueKey<String>(file.path ?? file.name),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: FileTile(
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
            );
          }),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy $label',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 20),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}