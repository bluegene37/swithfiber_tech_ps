import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet that provides a live camera barcode / QR scanner
/// specifically tuned for router, modem, and ONT serial numbers.
class SerialScannerSheet extends StatefulWidget {
  const SerialScannerSheet({super.key});

  /// Displays the scanner sheet and returns the scanned serial number string,
  /// or null if dismissed without a scan.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SerialScannerSheet(),
    );
  }

  @override
  State<SerialScannerSheet> createState() => _SerialScannerSheetState();
}

class _SerialScannerSheetState extends State<SerialScannerSheet> {
  late final MobileScannerController _controller;
  bool _hasDetected = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 350,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.itf14,
        BarcodeFormat.codabar,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected || !mounted) return;

    for (final barcode in capture.barcodes) {
      final val = barcode.rawValue?.trim() ?? barcode.displayValue?.trim();
      if (val != null && val.isNotEmpty) {
        _hasDetected = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(val);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Serial Number',
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Align router or ONT barcode within frame',
                        style: context.text.bodySmall?.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('close_serial_scanner_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Camera Viewport
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.videocam_off_rounded,
                                color: Colors.white70,
                                size: 44,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Camera Unavailable',
                                style: context.text.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Please check camera permissions in Settings or enter serial manually.',
                                textAlign: TextAlign.center,
                                style: context.text.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Targeting Reticle Overlay
                  const _ScannerTargetReticle(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Controls Bar (Torch, Switch Camera, Cancel)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Torch toggle
                OutlinedButton.icon(
                  key: const ValueKey('scanner_torch_button'),
                  onPressed: () async {
                    try {
                      await _controller.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    } catch (_) {}
                  },
                  icon: Icon(
                    _torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    size: 18,
                    color: _torchOn ? Colors.amber : null,
                  ),
                  label: Text(_torchOn ? 'Flash On' : 'Flash Off'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // Switch Camera
                OutlinedButton.icon(
                  key: const ValueKey('scanner_flip_camera_button'),
                  onPressed: () async {
                    try {
                      await _controller.switchCamera();
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.flip_camera_ios_rounded, size: 18),
                  label: const Text('Flip'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay box with corner markers to guide the technician when scanning.
class _ScannerTargetReticle extends StatelessWidget {
  const _ScannerTargetReticle();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth * 0.82;
        final boxHeight = boxWidth * 0.58;

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: boxWidth,
              height: boxHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.85),
                  width: 2.2,
                ),
              ),
            ),
            Positioned(
              bottom: (constraints.maxHeight - boxHeight) / 2 - 32,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Barcode / QR Code',
                  style: context.text.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
