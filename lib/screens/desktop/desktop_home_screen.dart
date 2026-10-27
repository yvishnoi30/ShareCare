import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../transfer/file_selection.dart';
import '../../transfer/folder_archive_service.dart';
import '../../ui/instruction_card.dart';
import '../../ui/ui.dart';
import '../../utils/file_utils.dart';
import 'desktop_receiver_screen.dart';
import 'desktop_sender_screen.dart';

/// Home screen for Windows (and other desktops).
///
/// Wide windows show two panes (actions on the left, files on the right);
/// narrow windows stack them.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  final FileSelection _selection = FileSelection();
  bool _isPicking = false;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
    });

    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result == null || !mounted) return;

      _selection.addAll(result.files);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select files: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _pickFolder() async {
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
    });

    try {
      final PlatformFile? archive =
          await FolderArchiveService.pickAndCreateZip();
      if (archive == null || !mounted) return;

      _selection.addAll(<PlatformFile>[archive]);
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Folder packaged and added: ${archive.name}'),
          ),
        );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not package folder: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _openSender() {
    if (_selection.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopSenderScreen(
          files: List<PlatformFile>.of(_selection.files),
        ),
      ),
    );
  }

  void _openReceiver() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DesktopReceiverScreen(),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    if (_selection.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Clear all files?'),
          content: Text(
            'This removes ${fileCountLabel(_selection.count)} from your '
            'list. The files stay on your computer.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep files'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear all'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      _selection.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickFiles,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _openReceiver,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                BrandMark(size: 32),
                SizedBox(width: AppSpacing.md),
                Text('ShareCare'),
              ],
            ),
            actions: const <Widget>[
              ThemeToggleButton(),
              SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: _selection,
              builder: (BuildContext context, Widget? child) {
                return LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool wide = constraints.maxWidth >= 960;
                    final Widget left = _buildLeftPane(context);
                    final Widget right = _buildSelectionCard(context);

                    final Widget content = wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(flex: 5, child: left),
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(flex: 6, child: right),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              left,
                              const SizedBox(height: AppSpacing.lg),
                              right,
                            ],
                          );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: content,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPane(BuildContext context) {
    final ColorScheme scheme = context.colors;
    final bool hasFiles = _selection.isNotEmpty;

    final Widget sendTile = ActionTile(
      icon: Icons.upload_file_rounded,
      title: 'Send files',
      subtitle: _isPicking
          ? 'Selecting files...'
          : hasFiles
              ? 'Add more files'
              : 'Choose files to share',
      onPressed: _isPicking ? null : _pickFiles,
      loading: _isPicking,
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );

    final Widget receiveTile = ActionTile(
      icon: Icons.download_rounded,
      title: 'Receive files',
      subtitle: 'Connect to a sending device',
      onPressed: _openReceiver,
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'Share files. Simply.',
            style: context.text.headlineMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Send files directly between your Windows PC and other devices on '
          'your local network. Nothing goes through the internet.',
          style: context.text.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 420) {
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
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Shortcuts: Ctrl+O adds files, Ctrl+R opens Receive files.',
          style: context.text.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionHeader(title: 'How sharing works'),
              SizedBox(height: AppSpacing.lg),
              StepRow(
                number: 1,
                title: 'Choose your files',
                description: 'Add the files you want to share.',
              ),
              SizedBox(height: AppSpacing.lg),
              StepRow(
                number: 2,
                title: 'Start sharing',
                description:
                    'ShareCare shows a QR code and a pairing code for the '
                    'other device.',
              ),
              SizedBox(height: AppSpacing.lg),
              StepRow(
                number: 3,
                title: 'Connect and save',
                description:
                    'Android phones scan the QR code. Windows computers '
                    'paste the pairing code and pick a save folder.',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const InstructionCard(
          icon: Icons.wifi,
          title: 'Use the same network',
          description:
              'Connect both devices to the same Wi-Fi network or hotspot. '
              'The first time you share, Windows may ask to allow ShareCare '
              'through Windows Defender Firewall: choose Allow access for '
              'private networks.',
        ),
      ],
    );
  }

  Widget _buildSelectionCard(BuildContext context) {
    final bool hasFiles = _selection.isNotEmpty;
    final List<PlatformFile> files = _selection.files;

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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                ),
                onPressed: _isPicking ? null : _pickFiles,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add files (Ctrl+O)'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                ),
                onPressed: _isPicking ? null : _pickFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Send folder'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasFiles)
            const EmptyState(
              icon: Icons.folder_open_outlined,
              title: 'No files selected',
              message: 'Choose Add files to pick what you want to share.',
            )
          else ...<Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                InfoChip(
                  icon: Icons.attach_file_rounded,
                  label: '${fileCountLabel(_selection.count)} selected',
                ),
                InfoChip(
                  icon: Icons.data_usage_rounded,
                  label: 'Total size: ${formatBytes(_selection.totalBytes)}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...List<Widget>.generate(files.length, (int index) {
              final PlatformFile file = files[index];

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
                    onPressed: () => _selection.removeAt(index),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            onPressed: hasFiles ? _openSender : null,
            icon: const Icon(Icons.qr_code_2),
            label: Text(
              hasFiles
                  ? 'Continue with ${fileCountLabel(_selection.count)}'
                  : 'Continue to connect',
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