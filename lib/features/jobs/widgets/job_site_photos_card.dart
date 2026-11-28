// Gene - Nov 5, 2026: Site Photo Proofs card in Job Order details fetching from GET /api/JobOrders/{id}/GetJobOrderImage with zoomable viewer and refresh.
// Gene - Nov, 8, 2026: Added dart:async and ApiClient for periodic background photo auto-sync and in-app remote URL photo preview.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
// Gene - Nov, 28, 2026: Added PowerSyncService to skip 15-second photo polling in replicated mode.
import '../../../core/sync/powersync_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url.dart';
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
import '../models/job_order_images_model.dart';
import '../models/job_order_model.dart';
import '../signals/jobs_signals.dart';

/// Interactive Site Photo Proofs gallery card for Job Order details.
///
/// Fetches remote photo proofs from `GET /api/JobOrders/{id}/GetJobOrderImage`,
/// caches them in-memory in the repository, and provides thumbnail inspection,
/// pull-to-refresh, and full-screen zoomable lightbox previews.
class JobSitePhotosCard extends StatefulWidget {
  final JobOrderDto job;
  final JobsSignals jobsSignals;
  final JobOrderImagesDto? initialImagesForTesting;

  const JobSitePhotosCard({
    super.key,
    required this.job,
    required this.jobsSignals,
    this.initialImagesForTesting,
  });

  @override
  State<JobSitePhotosCard> createState() => _JobSitePhotosCardState();
}

class _JobSitePhotosCardState extends State<JobSitePhotosCard> {
  bool _isLoading = false;
  JobOrderImagesDto? _sitePhotos;
  // Gene - Nov, 8, 2026: Periodic auto-sync timer for Job Order site photos.
  Timer? _photoAutoSyncTimer;

  /*
  @override
  void initState() {
    super.initState();
    _sitePhotos = widget.initialImagesForTesting;
    if (_sitePhotos == null) {
      _loadPhotos();
    }
  }

  Future<void> _loadPhotos({bool forceRefresh = false}) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final res = await widget.jobsSignals
          .getJobOrderImages(widget.job.id, forceRefresh: forceRefresh);
      if (mounted && res != null) {
        setState(() => _sitePhotos = res);
      }
    } catch (_) {
      // Offline fallback
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  */
  // Gene - Nov, 8, 2026: Auto-sync Job Order site photos periodically and when widget.job updates.
  @override
  void initState() {
    super.initState();
    _sitePhotos = widget.initialImagesForTesting;
    if (_sitePhotos == null) {
      _loadPhotos();
    }
    /*
    if (!ApiClient.blockNetworkForTesting) {
    */
    // Gene - Nov, 8, 2026: Use ApiClient.isNetworkBlocked getter to avoid visibleForTesting analyzer warning.
    // Gene - Nov, 28, 2026: Skip 15s polling timer when PowerSync replicated mode is active.
    if (!ApiClient.isNetworkBlocked &&
        !PowerSyncService.instance.isReplicatedMode) {
      _photoAutoSyncTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadPhotos(forceRefresh: true, silent: true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant JobSitePhotosCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.id != widget.job.id ||
        oldWidget.job.updatedAt != widget.job.updatedAt) {
      _loadPhotos(forceRefresh: true, silent: true);
    }
  }

  @override
  void dispose() {
    _photoAutoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPhotos({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    // Gene - Nov, 28, 2026: Halt network retries gracefully when gateway returns 403 NOT_ASSIGNED.
    if (widget.jobsSignals.isJobNotAssigned(widget.job.id) && !forceRefresh) {
      _photoAutoSyncTimer?.cancel();
      return;
    }
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final res = await widget.jobsSignals
          .getJobOrderImages(widget.job.id, forceRefresh: forceRefresh);
      if (widget.jobsSignals.isJobNotAssigned(widget.job.id)) {
        _photoAutoSyncTimer?.cancel();
      }
      if (mounted && res != null) {
        setState(() => _sitePhotos = res);
      } else if (mounted &&
          widget.jobsSignals.isJobNotAssigned(widget.job.id)) {
        setState(() => _sitePhotos = null);
      }
    } catch (_) {
      // Offline fallback
    } finally {
      if (!silent && mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Resolve proofs in official AppSheet physical sequence:
    // 1. Front House
    // 2. Set Up (Installed ONT & router)
    // 3. Router Reading (Rx Optical Power)
    // 4. Box Reading (NAP Box Meter)
    // 5. Signed Contract
    // 6. Subscriber Signature
    final items = _resolvePhotoItems();
    final attachedCount = items.where((it) => it.hasImage).length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header: Title + count + Refresh button
            Row(
              children: [
                const Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                // Gene - Nov 5, 2026: Wrapped title in Flexible to prevent RenderFlex overflow in narrow viewport/tests
                /*
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Site Photo Proofs',
                        style: context.text.titleSmall!.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: attachedCount > 0
                              ? AppTheme.primary.withValues(alpha: 0.12)
                              : (isDark
                                  ? AppTheme.darkInput
                                  : AppTheme.lightBg),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$attachedCount / ${items.length}',
                          style: context.text.labelSmall!.copyWith(
                            color: attachedCount > 0
                                ? AppTheme.primary
                                : AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                */
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Site Photo Proofs',
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall!.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: attachedCount > 0
                              ? AppTheme.primary.withValues(alpha: 0.12)
                              : (isDark
                                  ? AppTheme.darkInput
                                  : AppTheme.lightBg),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$attachedCount / ${items.length}',
                          style: context.text.labelSmall!.copyWith(
                            color: attachedCount > 0
                                ? AppTheme.primary
                                : AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh photos from server',
                    onPressed: () => _loadPhotos(forceRefresh: true),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            if (widget.jobsSignals.isJobNotAssigned(widget.job.id)) ...[
              Container(
                key: const ValueKey('job_photos_not_assigned_notice'),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_shield,
                        size: 20, color: AppTheme.warningInkOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Order reassigned — photos are no longer available for your account.',
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (attachedCount == 0 && !_isLoading) ...[
              // Empty state
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.camera,
                        size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No site photos attached yet. Tap refresh to check server.',
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Grid of photo proofs
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _PhotoProofTile(
                    item: item,
                    isDark: isDark,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_PhotoProofItem> _resolvePhotoItems() {
    final storage = PhotoStorageService.instance;

    _PhotoProofItem makeItem({
      required String label,
      required IconData icon,
      JobOrderImageFileDto? serverFile,
      String? localValue,
    }) {
      /*
      Uint8List? bytes = serverFile?.bytes;
      String? httpUrl;

      if (bytes == null && localValue != null && localValue.trim().isNotEmpty) {
        final clean = localValue.trim();
        if (clean.startsWith('http://') || clean.startsWith('https://')) {
          httpUrl = clean;
        } else {
          bytes = storage.resolveBytes(clean) ?? DataUrl.decode(clean);
        }
      }
      */
      // Gene - Nov, 13, 2026: Treat _sitePhotos from GetJobOrderImage as authoritative once loaded for synced jobs so photos deleted on live do not fall back to stale local job_orders columns.
      Uint8List? bytes = serverFile?.bytes;
      String? httpUrl;

      final canFallbackToLocal = _sitePhotos == null || !widget.job.isSynced;
      if (bytes == null &&
          canFallbackToLocal &&
          localValue != null &&
          localValue.trim().isNotEmpty) {
        final clean = localValue.trim();
        if (clean.startsWith('http://') || clean.startsWith('https://')) {
          httpUrl = clean;
        } else {
          bytes = storage.resolveBytes(clean) ?? DataUrl.decode(clean);
        }
      }

      return _PhotoProofItem(
        label: label,
        icon: icon,
        bytes: bytes,
        httpUrl: httpUrl,
        isServerSynced: serverFile?.hasImage == true,
      );
    }

    return [
      makeItem(
        label: 'Front House',
        icon: CupertinoIcons.house_fill,
        serverFile: _sitePhotos?.houseFront,
        localValue: widget.job.houseFront,
      ),
      makeItem(
        label: 'Set Up',
        icon: CupertinoIcons.wrench_fill,
        serverFile: _sitePhotos?.setupImage,
        localValue: widget.job.setupImage,
      ),
      makeItem(
        label: 'Router Rx',
        icon: CupertinoIcons.waveform_path_ecg,
        serverFile: _sitePhotos?.routerReadingImage,
        localValue: widget.job.routerReadingImage,
      ),
      makeItem(
        label: 'Box Reading',
        icon: CupertinoIcons.gauge,
        serverFile: _sitePhotos?.boxReadingImage,
        localValue: widget.job.boxReadingImage,
      ),
      makeItem(
        label: 'Signed Contract',
        icon: CupertinoIcons.doc_text_fill,
        serverFile: _sitePhotos?.signedContractImage,
        localValue: widget.job.signedContractImage,
      ),
      makeItem(
        label: 'Signature',
        icon: CupertinoIcons.pencil_outline,
        serverFile: _sitePhotos?.clientSignature,
        localValue: widget.job.clientSignature,
      ),
    ];
  }
}

class _PhotoProofItem {
  final String label;
  final IconData icon;
  final Uint8List? bytes;
  final String? httpUrl;
  final bool isServerSynced;

  const _PhotoProofItem({
    required this.label,
    required this.icon,
    this.bytes,
    this.httpUrl,
    this.isServerSynced = false,
  });

  bool get hasImage =>
      bytes != null || (httpUrl != null && httpUrl!.isNotEmpty);
}

class _PhotoProofTile extends StatelessWidget {
  final _PhotoProofItem item;
  final bool isDark;

  const _PhotoProofTile({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasImg = item.hasImage;

    /*
    return InkWell(
      onTap: hasImg
          ? () {
              if (item.bytes != null) {
                showPhotoViewer(context, item.bytes!, title: item.label);
              } else if (item.httpUrl != null) {
                launchUrl(Uri.parse(item.httpUrl!),
                    mode: LaunchMode.externalApplication);
              }
            }
          : null,
    */
    // Gene - Nov, 8, 2026: Open both inline bytes and remote HTTP URLs in the closeable full-screen photo viewer.
    return InkWell(
      onTap: hasImg
          ? () {
              if (item.bytes != null) {
                showPhotoViewer(context, item.bytes!, title: item.label);
              } else if (item.httpUrl != null) {
                showPhotoViewer(
                  context,
                  Uint8List(0),
                  title: item.label,
                  imageUrl: item.httpUrl,
                );
              }
            }
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImg
                ? (item.isServerSynced
                    ? AppTheme.primary.withValues(alpha: 0.5)
                    : (isDark ? AppTheme.borderDark : AppTheme.borderLight))
                : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            width: hasImg && item.isServerSynced ? 1.0 : 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.bytes != null)
                    Image.memory(
                      item.bytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                    )
                  else if (item.httpUrl != null)
                    Image.network(
                      item.httpUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildCloudLink(context),
                    )
                  else
                    _buildPlaceholder(context),
                  if (item.isServerSynced)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        // Gene - Nov 5, 2026: Badge icon size 20 respects the 20px floor in ui_standard_guard_test
                        child: const Icon(
                          Icons.cloud_done_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              color: isDark ? AppTheme.darkCard : Colors.white,
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Gene - Nov 5, 2026: Typography styled using context.text.labelSmall per ui_standard_guard_test
                style: context.text.labelSmall!.copyWith(
                  fontWeight: hasImg ? FontWeight.w600 : FontWeight.normal,
                  color: hasImg
                      ? (isDark ? Colors.white : Colors.black87)
                      : AppTheme.secondaryInkOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.icon,
            size: 22,
            color: AppTheme.secondaryInkOf(context).withValues(alpha: 0.6),
          ),
          const SizedBox(height: 2),
          // Gene - Nov 5, 2026: Styled with context.text.labelSmall per ui_standard_guard_test
          Text(
            'Not attached',
            style: context.text.labelSmall!.copyWith(
              color: AppTheme.secondaryInkOf(context).withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLink(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.link, size: 20, color: AppTheme.primary),
          const SizedBox(height: 2),
          // Gene - Nov 5, 2026: Styled with context.text.labelSmall per ui_standard_guard_test
          Text(
            'Cloud Link',
            style: context.text.labelSmall!.copyWith(
              color: AppTheme.primary.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
