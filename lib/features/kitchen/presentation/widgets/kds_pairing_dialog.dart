import 'dart:async';

import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_remote_qr_parser.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class KdsPairingDialog extends StatefulWidget {
  const KdsPairingDialog({
    required this.screen,
    required this.initialCode,
    required this.onRegenerate,
    super.key,
  });

  final KdsScreen screen;
  final KdsPairingCode initialCode;
  final Future<KdsPairingCode?> Function() onRegenerate;

  @override
  State<KdsPairingDialog> createState() => _KdsPairingDialogState();
}

class _KdsPairingDialogState extends State<KdsPairingDialog> {
  late KdsPairingCode _code;
  bool _expired = false;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _code = widget.initialCode;
  }

  void _handleExpired() {
    if (!mounted) {
      return;
    }
    setState(() => _expired = true);
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    final result = await widget.onRegenerate();
    if (!mounted) {
      return;
    }
    setState(() {
      _regenerating = false;
      if (result != null) {
        _code = result;
        _expired = false;
      }
    });
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code.code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CODE COPIÉ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrData = _code.pairingPayload.trim().isEmpty
        ? _code.code
        : buildKdsRemotePairingQrData(_code.pairingPayload);

    return AlertDialog(
      title: const Text('ASSOCIER UN TÉLÉPHONE'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.screen.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _PairingQr(data: qrData),
            const SizedBox(height: AppSpacing.md),
            Text(
              'CODE MANUEL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              formatPairingCodeDisplay(_code.code),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_expired) ...[
              Text(
                'CODE EXPIRÉ',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _regenerating ? null : _regenerate,
                icon: _regenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('GÉNÉRER UN NOUVEAU CODE'),
              ),
            ] else ...[
              _PairingCountdown(
                expiresAt: _code.expiresAt,
                onExpired: _handleExpired,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('COPIER'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('FERMER'),
        ),
      ],
    );
  }
}

class _PairingQr extends StatelessWidget {
  const _PairingQr({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR remote',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.adminBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox.square(
            dimension: 216,
            child: QrImageView(
              key: const Key('kds-pairing-qr'),
              data: data,
              version: QrVersions.auto,
              size: 216,
              gapless: false,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PairingCountdown extends StatefulWidget {
  const _PairingCountdown({
    required this.expiresAt,
    required this.onExpired,
  });

  final DateTime expiresAt;
  final VoidCallback onExpired;

  @override
  State<_PairingCountdown> createState() => _PairingCountdownState();
}

class _PairingCountdownState extends State<_PairingCountdown> {
  Timer? _timer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _notified) {
      return;
    }
    final remaining = widget.expiresAt.toLocal().difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _notified = true;
      _timer?.cancel();
      widget.onExpired();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.toLocal().difference(DateTime.now());
    final display = remaining.isNegative ? Duration.zero : remaining;
    return Text(
      'Expire dans ${formatPairingCountdown(display)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
    );
  }
}

String formatPairingCodeDisplay(String code) {
  if (code.length != 6) {
    return code;
  }
  return '${code.substring(0, 3)} ${code.substring(3)}';
}

String formatPairingCountdown(Duration remaining) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}';
}
