import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'ui.dart';

class QrTile extends StatelessWidget {
  const QrTile({
    super.key,
    required this.data,
    this.size = 230,
  });

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'QR code for connecting another device',
        image: true,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: context.colors.outlineVariant,
            ),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

class QrPlaceholder extends StatelessWidget {
  const QrPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              Icons.qr_code_2,
              size: 72,
              color: scheme.outline,
            ),
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