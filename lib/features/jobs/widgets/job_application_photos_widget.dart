// Gene - Oct 24, 2026: Widget for displaying customer application photos (Front House, Landmark, KYC documents) from Application API.
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url.dart';
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
import '../models/application_images_model.dart';
import '../models/job_order_model.dart';
import '../services/applications_api.dart';

/// Renders Front House Image, Installation Landmark, and customer KYC proofs
/// using data from the Job Order and the Applications Image API.
class JobApplicationPhotosWidget extends StatefulWidget {
  final JobOrderDto job;
  final bool isDark;
  final ApplicationsApi? api;

  const JobApplicationPhotosWidget({
    super.key,
    required this.job,
    required this.isDark,
    this.api,
  });

  @override
  State<JobApplicationPhotosWidget> createState() =>
      _JobApplicationPhotosWidgetState();
}

class _JobApplicationPhotosWidgetState
    extends State<JobApplicationPhotosWidget> {
  ApplicationImagesDto? _appImages;
  bool _kycExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadApplicationImages();
  }

  @override
  void didUpdateWidget(covariant JobApplicationPhotosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.applicationId != widget.job.applicationId ||
        oldWidget.job.id != widget.job.id) {
      _loadApplicationImages();
    }
  }

  Future<void> _loadApplicationImages() async {
    final appId = widget.job.applicationId;
    if (appId == null || appId.trim().isEmpty) return;

    final api = widget.api ?? ApplicationsApi.instance;
    try {
      final res = await api.getApplicationImages(appId);
      if (mounted) {
        setState(() {
          _appImages = res;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final isDark = widget.isDark;

    final houseFrontFile = _appImages?.houseFrontPictureFile;
    final houseBytes = houseFrontFile?.bytes;
    final hasHouseFront = (job.houseFront != null &&
            job.houseFront!.trim().isNotEmpty) ||
        houseBytes != null;

    final landmarkFile = _appImages?.landmarkFile;
    final landmarkBytes = landmarkFile?.bytes;
    final hasLandmark = (job.installationLandmark != null &&
            job.installationLandmark!.trim().isNotEmpty &&
            job.installationLandmark != job.houseFront) ||
        landmarkBytes != null;

    final secLandmarkFile = _appImages?.secondNearestLandmarkFile;
    final secLandmarkBytes = secLandmarkFile?.bytes;

    final hasKyc = _appImages != null && _appImages!.hasKycDocuments;

    if (!hasHouseFront && !hasLandmark && secLandmarkBytes == null && !hasKyc) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Front House Image
        if (hasHouseFront) ...[
          const SizedBox(height: 10),
          _buildPhotoCard(
            context,
            title: 'Front House Image',
            icon: CupertinoIcons.house_fill,
            pathOrUrl: job.houseFront,
            directBytes: houseBytes,
            isDark: isDark,
          ),
        ],

        // Primary Installation Landmark
        if (hasLandmark) ...[
          const SizedBox(height: 10),
          _buildPhotoCard(
            context,
            title: 'Installation Landmark',
            icon: Icons.photo_camera_outlined,
            pathOrUrl: job.installationLandmark,
            directBytes: landmarkBytes,
            isDark: isDark,
          ),
        ],

        // Secondary Landmark (if present in application)
        if (secLandmarkBytes != null) ...[
          const SizedBox(height: 10),
          _buildPhotoCard(
            context,
            title: 'Secondary Landmark',
            icon: Icons.assistant_direction_outlined,
            pathOrUrl: null,
            directBytes: secLandmarkBytes,
            isDark: isDark,
          ),
        ],

        // Subscriber KYC & Verification Proofs
        if (hasKyc) ...[
          const SizedBox(height: 14),
          _buildKycSection(context, isDark),
        ],
      ],
    );
  }

  Widget _buildPhotoCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String? pathOrUrl,
    required Uint8List? directBytes,
    required bool isDark,
  }) {
    final clean = pathOrUrl?.trim() ?? '';
    final bytes = directBytes ??
        (clean.isNotEmpty
            ? (PhotoStorageService.instance.resolveBytes(clean) ??
                DataUrl.decode(clean))
            : null);
    final isHttp = clean.startsWith('http://') || clean.startsWith('https://');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: context.text.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              if (bytes != null) {
                showPhotoViewer(context, bytes, title: title);
              } else if (isHttp) {
                launchUrl(Uri.parse(clean),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                    )
                  else if (isHttp)
                    Image.network(
                      clean,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.link,
                                size: 28, color: AppTheme.primary),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to view cloud image',
                              style: context.text.labelSmall!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          clean.isNotEmpty ? clean : 'Photo pending upload',
                          style: context.text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (bytes != null || isHttp)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.zoom_in,
                                size: 20, color: Colors.white),
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
        ],
      ),
    );
  }

  Widget _buildKycSection(BuildContext context, bool isDark) {
    final docs = <({String title, ApplicationImageFileDto file})>[
      if (_appImages?.governmentValidIdFile?.hasImage == true)
        (
          title: 'Primary Valid ID',
          file: _appImages!.governmentValidIdFile!,
        ),
      if (_appImages?.secondGovernmentValidIdFile?.hasImage == true)
        (
          title: 'Secondary Valid ID',
          file: _appImages!.secondGovernmentValidIdFile!,
        ),
      if (_appImages?.proofOfBillingFile?.hasImage == true)
        (
          title: 'Proof of Billing',
          file: _appImages!.proofOfBillingFile!,
        ),
      if (_appImages?.documentPictureFile?.hasImage == true)
        (
          title: 'Application Document',
          file: _appImages!.documentPictureFile!,
        ),
      if (_appImages
              ?.pictureOfStatementBillingFromOtherProviderFile?.hasImage ==
          true)
        (
          title: 'Other Provider SOA',
          file: _appImages!.pictureOfStatementBillingFromOtherProviderFile!,
        ),
    ];

    if (docs.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _kycExpanded = !_kycExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.doc_person_fill,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Applicant KYC & Proof Documents (${docs.length})',
                      style: context.text.labelMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _kycExpanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 18,
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ],
              ),
            ),
          ),
          if (_kycExpanded) ...[
            Divider(
              height: 1,
              color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final doc in docs)
                    _buildKycThumbnail(context, doc.title, doc.file, isDark),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKycThumbnail(
    BuildContext context,
    String label,
    ApplicationImageFileDto file,
    bool isDark,
  ) {
    final bytes = file.bytes;
    if (bytes == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () => showPhotoViewer(context, bytes, title: label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardElevated : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 90,
              width: 140,
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 24),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                label,
                style: context.text.labelSmall!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
