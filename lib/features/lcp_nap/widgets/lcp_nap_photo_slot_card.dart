// Gene - Nov, 12, 2026: Created standalone LcpNapPhotoSlotCard so each of the 3 LCP/NAP site images renders as its own top-level Card (even when empty) with 1-tap Camera/Gallery upload and Calm Utility styling.

import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/services/exif_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url.dart';

/// Standalone Calm Utility card for one LCP/NAP site photo slot:
/// - `enc1`: Enclosure Exterior
/// - `enc2`: Enclosure Interior
/// - `reading`: Optical Power Reading
///
/// Always renders as its own top-level [Card] (no nested cards per DESIGN.md).
/// When empty, technicians can capture from the camera or choose from the
/// gallery in a single tap and immediately upload onto this slot.
class LcpNapPhotoSlotCard extends StatelessWidget {
  final String slotKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? bytes;
  final String? remoteUrl;
  final bool isBusy;
  final String? busyLabel;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFromGallery;
  final VoidCallback onViewPhoto;
  final VoidCallback onDeletePhoto;

  const LcpNapPhotoSlotCard({
    super.key,
    required this.slotKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bytes,
    required this.remoteUrl,
    this.isBusy = false,
    this.busyLabel,
    required this.onTakePhoto,
    required this.onPickFromGallery,
    required this.onViewPhoto,
    required this.onDeletePhoto,
  });

  bool get _hasPhoto =>
      (bytes != null && bytes!.isNotEmpty) ||
      (remoteUrl != null && remoteUrl!.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final hairline = AppTheme.hairlineOf(context);
    final statusColor = _hasPhoto
        ? AppTheme.successInkOf(context)
        : AppTheme.secondaryInkOf(context);

    final stamp = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
        border: Border.all(
          color: _hasPhoto ? statusColor : hairline,
          width: _hasPhoto ? 1.5 : 1,
        ),
      ),
      child: Text(
        _hasPhoto ? 'CAPTURED' : 'EMPTY',
        style: context.text.labelMedium!.copyWith(
          color: statusColor,
        ),
      ),
    );

    return Card(
      key: ValueKey('photoSlotCard_$slotKey'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Icon, Slot Title & Subtitle, Outline Status Stamp
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: scale > 1.5
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: _hasPhoto
                                ? AppTheme.successInkOf(context)
                                : AppTheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: context.text.titleMedium),
                                const SizedBox(height: 2),
                                Text(subtitle, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      stamp,
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: _hasPhoto
                            ? AppTheme.successInkOf(context)
                            : AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: context.text.titleMedium),
                            const SizedBox(height: 2),
                            Text(subtitle, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      stamp,
                    ],
                  ),
          ),
          Divider(height: 1, thickness: 1, color: hairline),
          if (isBusy)
            _buildBusyBody(context)
          else if (_hasPhoto)
            _buildFilledBody(context, scale, hairline)
          else
            _buildEmptyBody(context, scale),
        ],
      ),
    );
  }

  Widget _buildBusyBody(BuildContext context) {
    return Container(
      color: AppTheme.fillOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            busyLabel ?? 'Uploading photo...',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBody(BuildContext context, double scale) {
    final cameraBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: FilledButton.icon(
        key: ValueKey('btnTakePhoto_$slotKey'),
        onPressed: onTakePhoto,
        icon: const Icon(CupertinoIcons.camera_fill, size: 20),
        label: const Text('Take Photo'),
      ),
    );

    final galleryBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: OutlinedButton.icon(
        key: ValueKey('btnPickGallery_$slotKey'),
        onPressed: onPickFromGallery,
        icon: const Icon(CupertinoIcons.photo, size: 20),
        label: const Text('Gallery'),
      ),
    );

    return Container(
      color: AppTheme.fillOf(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_camera_back_outlined,
                size: 22,
                color: AppTheme.secondaryInkOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No $title photo uploaded yet.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (scale > 1.3)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cameraBtn,
                const SizedBox(height: 8),
                galleryBtn,
              ],
            )
          else
            Row(
              children: [
                Expanded(child: cameraBtn),
                const SizedBox(width: 10),
                Expanded(child: galleryBtn),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilledBody(
    BuildContext context,
    double scale,
    Color hairline,
  ) {
    final imageBytes = bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('btnViewPhoto_$slotKey'),
          onTap: onViewPhoto,
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageBytes != null && imageBytes.isNotEmpty)
                  Image.memory(
                    imageBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else if (remoteUrl != null)
                  Image.network(
                    remoteUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 32),
                    ),
                  ),
                if (imageBytes != null && imageBytes.isNotEmpty) ...[
                  Positioned(
                    top: 8,
                    left: 8,
                    child: FutureBuilder<ExifMetadata>(
                      future: ExifService.instance.extractExif(imageBytes),
                      builder: (context, snapshot) {
                        final hasGps = snapshot.data?.hasGps == true;
                        final badgeColor = hasGps
                            ? AppTheme.success.withValues(alpha: 0.88)
                            : AppTheme.darkSlate.withValues(alpha: 0.75);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasGps
                                    ? CupertinoIcons.location_fill
                                    : CupertinoIcons.location_slash,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasGps ? 'GPS' : 'No GPS',
                                style: context.text.labelSmall!.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        DataUrl.formatBytes(imageBytes.length),
                        style: context.text.labelSmall!.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.zoom_in,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pinch / Zoom',
                          style: context.text.labelSmall!.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: hairline),
        // Calm Utility 3-action strip (48dp minimum height; icon stacks above
        // label past 1.2x text scale per DESIGN.md so 200% font never overflows).
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SlotStripAction(
                  actionKey: ValueKey('btnRetakePhoto_$slotKey'),
                  icon: CupertinoIcons.camera,
                  label: 'Retake',
                  tooltip: 'Retake $title',
                  color: AppTheme.inkOf(context),
                  stackVertically: scale > 1.2,
                  onTap: onTakePhoto,
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: hairline),
              Expanded(
                child: _SlotStripAction(
                  actionKey: ValueKey('btnReplaceGallery_$slotKey'),
                  icon: CupertinoIcons.photo,
                  label: 'Gallery',
                  tooltip: 'Replace $title from gallery',
                  color: AppTheme.inkOf(context),
                  stackVertically: scale > 1.2,
                  onTap: onPickFromGallery,
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: hairline),
              Expanded(
                child: _SlotStripAction(
                  actionKey: ValueKey('btnDeletePhoto_$slotKey'),
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
                  tooltip: 'Delete $title',
                  color: AppTheme.dangerInkOf(context),
                  stackVertically: scale > 1.2,
                  onTap: onDeletePhoto,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotStripAction extends StatelessWidget {
  final Key? actionKey;
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final bool stackVertically;
  final VoidCallback onTap;

  const _SlotStripAction({
    this.actionKey,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.stackVertically,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      style: context.text.labelMedium!.copyWith(color: color),
    );

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          key: actionKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: stackVertically
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(height: 4),
                        labelWidget,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 6),
                        Flexible(child: labelWidget),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
