// Gene - Nov, 25, 2026: Site Photo Proofs card in Service Order details fetching from GET /api/ServiceOrders/{id}/GetServiceOrderImage with zoomable viewer and periodic/manual refresh.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url.dart';
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
import '../models/service_order_images_model.dart';
import '../models/service_order_model.dart';
import '../signals/service_orders_signals.dart';

/// Interactive Site Photo Proofs gallery card for Service Order details.
///
/// Fetches remote photo proofs from `GET /api/ServiceOrders/{id}/GetServiceOrderImage`,
/// caches them in-memory in [ServiceOrdersSignals], and provides thumbnail
/// inspection, manual/periodic refresh, and full-screen zoomable lightbox previews.
class ServiceOrderSitePhotosCard extends StatefulWidget {
  final ServiceOrderDto order;
  final ServiceOrdersSignals signals;
  final ServiceOrderImagesDto? initialImagesForTesting;
  final ValueChanged<ServiceOrderImagesDto>? onImagesLoaded;

  const ServiceOrderSitePhotosCard({
    super.key,
    required this.order,
    required this.signals,
    this.initialImagesForTesting,
    this.onImagesLoaded,
  });

  @override
  State<ServiceOrderSitePhotosCard> createState() =>
      _ServiceOrderSitePhotosCardState();
}

class _ServiceOrderSitePhotosCardState
    extends State<ServiceOrderSitePhotosCard> {
  bool _isLoading = false;
  ServiceOrderImagesDto? _sitePhotos;
  Timer? _photoAutoSyncTimer;

  @override
  void initState() {
    super.initState();
    _sitePhotos = widget.initialImagesForTesting;
    if (_sitePhotos == null) {
      _loadPhotos();
    }
    if (!ApiClient.isNetworkBlocked) {
      _photoAutoSyncTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadPhotos(forceRefresh: true, silent: true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ServiceOrderSitePhotosCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.updatedAt != widget.order.updatedAt) {
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
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final res = await widget.signals.getServiceOrderImages(
        widget.order.id,
        forceRefresh: forceRefresh,
      );
      if (mounted && res != null) {
        setState(() => _sitePhotos = res);
        widget.onImagesLoaded?.call(res);
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
    final items = _resolvePhotoItems();
    final attachedCount = items.where((it) => it.hasImage).length;
    final largeText = (MediaQuery.textScalerOf(context).scale(16) / 16) > 1.2;

    return Card(
      key: const ValueKey('service_order_site_photos_card'),
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
            Row(
              children: [
                const Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
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
                    key: const ValueKey('service_order_refresh_photos_button'),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh photos from server',
                    onPressed: () => _loadPhotos(forceRefresh: true),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (attachedCount == 0 && !_isLoading)
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
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: largeText ? 2 : 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: largeText ? 0.78 : 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => _ServiceOrderPhotoTile(
                  item: items[index],
                  isDark: isDark,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_ServiceOrderPhotoItem> _resolvePhotoItems() {
    final storage = PhotoStorageService.instance;

    _ServiceOrderPhotoItem makeItem({
      required String label,
      required IconData icon,
      ServiceOrderImageFileDto? serverFile,
      String? localValue,
    }) {
      Uint8List? bytes = serverFile?.bytes;
      String? httpUrl;

      // Once server images load on a synced order, treat _sitePhotos as
      // authoritative so photos deleted on live don't fall back to stale columns.
      final canFallbackToLocal = _sitePhotos == null || !widget.order.isSynced;
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

      return _ServiceOrderPhotoItem(
        label: label,
        icon: icon,
        bytes: bytes,
        httpUrl: httpUrl,
        isServerSynced: serverFile?.hasImage == true,
      );
    }

    return [
      makeItem(
        label: 'House Front',
        icon: CupertinoIcons.house_fill,
        serverFile: _sitePhotos?.houseFrontPicture,
        localValue: widget.order.houseFrontPicture,
      ),
      makeItem(
        label: 'Modem Setup',
        icon: Icons.router_rounded,
        serverFile: _sitePhotos?.image1,
        localValue: widget.order.image1,
      ),
      makeItem(
        label: 'Drop / NAP',
        icon: Icons.alt_route_rounded,
        serverFile: _sitePhotos?.image2,
        localValue: widget.order.image2,
      ),
      makeItem(
        label: 'Repair Proof',
        icon: CupertinoIcons.wrench_fill,
        serverFile: _sitePhotos?.image3,
        localValue: widget.order.image3,
      ),
      makeItem(
        label: 'Signature',
        icon: CupertinoIcons.pencil_outline,
        serverFile: _sitePhotos?.clientSignature,
        localValue: widget.order.clientSignature,
      ),
    ];
  }
}

class _ServiceOrderPhotoItem {
  final String label;
  final IconData icon;
  final Uint8List? bytes;
  final String? httpUrl;
  final bool isServerSynced;

  const _ServiceOrderPhotoItem({
    required this.label,
    required this.icon,
    this.bytes,
    this.httpUrl,
    this.isServerSynced = false,
  });

  bool get hasImage =>
      bytes != null || (httpUrl != null && httpUrl!.isNotEmpty);
}

class _ServiceOrderPhotoTile extends StatelessWidget {
  final _ServiceOrderPhotoItem item;
  final bool isDark;

  const _ServiceOrderPhotoTile({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasImg = item.hasImage;

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
