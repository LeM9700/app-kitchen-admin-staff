import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class KdsRemoteQrScannerPage extends StatefulWidget {
  const KdsRemoteQrScannerPage({super.key});

  @override
  State<KdsRemoteQrScannerPage> createState() => _KdsRemoteQrScannerPageState();
}

class _KdsRemoteQrScannerPageState extends State<KdsRemoteQrScannerPage> {
  final _controller = MobileScannerController(
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner remote'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleCapture,
            errorBuilder: (context, error) {
              return _ScannerError(message: _cameraErrorMessage(error));
            },
          ),
          const _ScannerFrame(),
          Positioned(
            left: 20,
            right: 20,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'CADREZ LE QR AFFICHÉ SUR L’ÉCRAN SERVICE, CUISINE OU COMPTOIR',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton.filledTonal(
                tooltip: 'Torche',
                onPressed: _controller.toggleTorch,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surface.withValues(alpha: 0.88),
                  foregroundColor: scheme.onSurface,
                ),
                icon: const Icon(Icons.flashlight_on_outlined),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IgnorePointer(
        child: Container(
          width: 248,
          height: 248,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: AppColors.danger,
                size: 46,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _cameraErrorMessage(MobileScannerException error) {
  if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
    return 'CAMÉRA REFUSÉE';
  }
  return 'SCANNER QR INDISPONIBLE';
}
