// Gene - Oct 24, 2026: Commented out unnecessary dart:typed_data import as flutter/services.dart already exports it.
/*
import 'dart:typed_data';
*/
import 'dart:async';
// Gene - Nov, 8, 2026: Imported dart:convert for base64Encode when constructing optimistic LcpNapImagesDto after upload/delete.
import 'dart:convert';
/*
import 'package:flutter/cupertino.dart';
*/
// Gene - Nov, 12, 2026: Commented out unused cupertino import after moving photo slot icons into LcpNapPhotoSlotCard.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:signals_flutter/signals_flutter.dart';
// Gene - Nov, 8, 2026: Commented out unused url_launcher import since remote photos now open in the in-app full-screen viewer.
// import 'package:url_launcher/url_launcher.dart';
// Gene - Nov, 8, 2026: Imported ApiClient to guard background photo auto-sync timer during widget tests.
import '../../../core/network/api_client.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url.dart';
/*
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
*/
// Gene - Oct 29, 2026: Import image_picker, PhotoCaptureTile and ImageCaptureService to support capturing and uploading site photos.
import 'package:image_picker/image_picker.dart';
import '../../../core/services/image_capture_service.dart';
/*
import '../../reports/widgets/photo_capture_tile.dart';
*/
// Gene - Nov, 12, 2026: Show only showPhotoViewer from photo_capture_tile.dart and import LcpNapPhotoSlotCard for standalone per-slot upload cards.
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
import '../models/lcp_nap_images_model.dart';
import '../models/lcp_nap_model.dart';
import '../services/map_clustering.dart';
import '../services/map_tiles.dart';
import '../signals/lcp_nap_signals.dart';
// Gene - Oct 31, 2026: Imported LocationService, PlaceLookup, geocoding, and LcpNapLocationPickerSheet for mapping LCP NAP coordinates.
import 'package:geocoding/geocoding.dart' as geo;
import '../../../core/services/location_service.dart';
import '../widgets/lcp_nap_location_picker_sheet.dart';
import '../widgets/lcp_nap_photo_slot_card.dart';
import '../widgets/map_search_bar.dart' show PlaceLookup;

/// Screen displaying comprehensive details and status controls for an LCP NAP site with full Dark Mode support.
class LcpNapDetailScreen extends StatefulWidget {
  final int locationId;
  final LcpNapSignals signals;
  final TileProvider? tileProvider;
  // Gene - Oct 24, 2026: Optional initial images parameter for testing.
  final LcpNapImagesDto? initialImagesForTesting;
  // Gene - Oct 29, 2026: Optional image picker callback for testing.
  final Future<String?> Function(ImageSource source)? pickImageForTesting;
  // Gene - Oct 31, 2026: Optional testing parameters for location mapping.
  final LocationService? locationServiceForTesting;
  final PlaceLookup? placeLookupForTesting;
  final Future<List<geo.Placemark>> Function(double lat, double lng)?
      reverseGeocodeForTesting;

  /*
  // Gene - Oct 29, 2026: Added pickImageForTesting parameter.
  const LcpNapDetailScreen({
    super.key,
    required this.locationId,
    required this.signals,
    this.tileProvider,
    this.initialImagesForTesting,
    this.pickImageForTesting,
  });
  */
  // Gene - Oct 31, 2026: Added locationServiceForTesting, placeLookupForTesting, and reverseGeocodeForTesting parameters.
  const LcpNapDetailScreen({
    super.key,
    required this.locationId,
    required this.signals,
    this.tileProvider,
    this.initialImagesForTesting,
    this.pickImageForTesting,
    this.locationServiceForTesting,
    this.placeLookupForTesting,
    this.reverseGeocodeForTesting,
  });

  @override
  State<LcpNapDetailScreen> createState() => _LcpNapDetailScreenState();
}

/*
class _LcpNapDetailScreenState extends State<LcpNapDetailScreen> {
*/
// Gene - Nov, 11, 2026: Mix in WidgetsBindingObserver and subscribe to photoSyncRevision so LCP NAP site photos & GPS auto-sync on resume, reconnect, background sync, screen re-entry, and pull-to-refresh without restarting the app.
class _LcpNapDetailScreenState extends State<LcpNapDetailScreen>
    with WidgetsBindingObserver {
  TileProvider? _tiles;
  // Gene - Oct 24, 2026: State variables for LCP NAP site enclosure and reading photos.
  LcpNapImagesDto? _sitePhotos;
  // Gene - Oct 31, 2026: Loading indicator for fetching site enclosure and reading photos.
  bool _isLoadingPhotos = false;
  // Gene - Nov, 8, 2026: Periodic auto-sync timer so LCP NAP photos auto-update when changed on the backend.
  Timer? _photoAutoSyncTimer;
  // Gene - Nov, 11, 2026: Reactive effect cleanup for signals.photoSyncRevision listener.
  EffectCleanup? _disposePhotoSyncEffect;
  // Gene - Nov, 12, 2026: Per-slot busy tracking so 1-tap upload or delete shows an inline spinner only on the active photo card.
  final Set<String> _busyPhotoSlots = <String>{};
  final Map<String, String> _busyPhotoLabels = <String, String>{};

  /*
  @override
  void initState() {
    super.initState();
    _tiles = widget.tileProvider;
    _sitePhotos = widget.initialImagesForTesting;
    if (_tiles == null) _loadTileProvider();
    if (_sitePhotos == null) _loadSitePhotos();
  }

  Future<void> _loadSitePhotos() async {
    if (mounted) setState(() => _isLoadingPhotos = true);
    try {
      final res = await widget.signals.repository
          .getLcpNapLocationImages(widget.locationId);
      if (mounted && res != null) {
        setState(() => _sitePhotos = res);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingPhotos = false);
    }
  }
  */
  /*
  // Gene - Nov, 8, 2026: Support forceRefresh/silent photo loading and start periodic auto-sync timer while screen is mounted.
  @override
  void initState() {
    super.initState();
    _tiles = widget.tileProvider;
    _sitePhotos = widget.initialImagesForTesting;
    if (_sitePhotos != null) {
      widget.signals.repository.seedImagesCache(widget.locationId, _sitePhotos!);
    }
    if (_tiles == null) _loadTileProvider();
    if (_sitePhotos == null) _loadSitePhotos();
    // Gene - Nov, 8, 2026: Use ApiClient.isNetworkBlocked getter to avoid visibleForTesting analyzer warning.
    if (!ApiClient.isNetworkBlocked) {
      _photoAutoSyncTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadSitePhotos(forceRefresh: true, silent: true),
      );
    }
  }

  @override
  void dispose() {
    _photoAutoSyncTimer?.cancel();
    super.dispose();
  }
  */
  // Gene - Nov, 11, 2026: Force-refresh server photos on screen entry (seeding any cached preview immediately), react to background photoSyncRevision updates, and refresh on app lifecycle resume.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tiles = widget.tileProvider;
    if (widget.initialImagesForTesting != null) {
      _sitePhotos = widget.initialImagesForTesting;
      widget.signals.repository
          .seedImagesCache(widget.locationId, _sitePhotos!);
    } else {
      _sitePhotos =
          widget.signals.repository.peekCachedImages(widget.locationId);
      _loadSitePhotos(
        forceRefresh: true,
        silent: _sitePhotos != null,
      );
    }
    if (_tiles == null) _loadTileProvider();

    var isInitialEffectRun = true;
    _disposePhotoSyncEffect = effect(() {
      widget.signals.photoSyncRevision.value;
      if (isInitialEffectRun) {
        isInitialEffectRun = false;
        return;
      }
      _loadSitePhotos(forceRefresh: true, silent: true);
    });

    if (!ApiClient.isNetworkBlocked) {
      _photoAutoSyncTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadSitePhotos(forceRefresh: true, silent: true),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !ApiClient.isNetworkBlocked) {
      widget.signals.fetchRemote();
      _loadSitePhotos(forceRefresh: true, silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposePhotoSyncEffect?.call();
    _photoAutoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSitePhotos({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (!silent && mounted) setState(() => _isLoadingPhotos = true);
    try {
      final res = await widget.signals.repository.getLcpNapLocationImages(
        widget.locationId,
        forceRefresh: forceRefresh,
      );
      if (mounted && res != null) {
        setState(() => _sitePhotos = res);
      }
    } catch (_) {
    } finally {
      if (!silent && mounted) setState(() => _isLoadingPhotos = false);
    }
  }

  Future<void> _loadTileProvider() async {
    final TileProvider provider;
    try {
      provider = await MapTiles.provider();
    } catch (_) {
      // No usable cache directory (a stripped-down host, or a test): the map
      // keeps its pins and simply shows no base tiles rather than crashing.
      return;
    }
    if (!mounted) return;
    setState(() => _tiles = provider);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SignalBuilder(
      builder: (context) {
        final all = widget.signals.allLocations.value;
        final location =
            all.where((l) => l.id == widget.locationId).firstOrNull;

        if (location == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Site Details')),
            body: Center(
              child: Text(
                'Location not found',
                style: context.text.bodyMedium!
                    .copyWith(color: AppTheme.secondaryInkOf(context)),
              ),
            ),
          );
        }

        final hue = lcpColorSeed(location.lcp);
        final cabinetColor = HSLColor.fromAHSL(1, hue, 0.62, 0.44).toColor();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              location.lcpNap,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              // Same sync glyph and tooltip as the job detail.
              Tooltip(
                message: location.isSynced
                    ? 'Synced with the server'
                    : 'Saved on phone, not yet synced',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    location.isSynced
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    size: 22,
                    color: location.isSynced
                        ? AppTheme.successInkOf(context)
                        : AppTheme.warningInkOf(context),
                  ),
                ),
              ),
              // Gene - Nov, 11, 2026: Added Edit Site Details action in the AppBar to edit LCP, NAP, PortTotal, address, and GPS.
              IconButton(
                key: const ValueKey('btnEditSiteDetails'),
                icon: const Icon(Icons.edit_outlined, size: 22),
                tooltip: 'Edit Site Details',
                onPressed: () => _showEditSiteDetailsSheet(context, location),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 24),
                tooltip: 'Copy Dispatch Summary',
                onPressed: () => _copySiteSummary(context, location, isDark),
              ),
            ],
          ),
          /*
          body: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
          */
          /*
          // Gene - Oct 31, 2026: Wrapped ListView in RefreshIndicator to allow technicians to pull-to-refresh photos and latest site data.
          body: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                widget.signals.fetchRemote(),
                _loadSitePhotos(),
              ]);
            },
          */
          // Gene - Nov, 11, 2026: Pass forceRefresh: true on pull-to-refresh so remote uploaded/deleted NAP images always sync live.
          body: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                widget.signals.fetchRemote(),
                _loadSitePhotos(forceRefresh: true),
              ]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
              children: [
                // 1. Overview Header Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // The name column takes whatever width the ports
                            // badge leaves. Without a flex factor the two sides
                            // only fit when the NAP name happens to be short;
                            // "CAR LCP 001 NAP 006" overflowed by 16px.
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          cabinetColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: cabinetColor.withValues(
                                              alpha: 0.3)),
                                    ),
                                    child: Icon(Icons.router_rounded,
                                        color: cabinetColor, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          location.lcpNap,
                                          style: context.text.titleMedium,
                                        ),
                                        Text(
                                          '${location.lcp} Distribution Point',
                                          style: context.text.labelMedium!
                                              .copyWith(color: cabinetColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF3F2327)
                                    : AppTheme.primarySubtleBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF882933)
                                      : AppTheme.primarySubtleBorder,
                                ),
                              ),
                              child: Text(
                                '${location.portTotal} ports',
                                style: context.text.labelLarge!.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.brandInkOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(
                            height: 1,
                            color: isDark
                                ? AppTheme.borderDark
                                : AppTheme.borderLight),
                        const SizedBox(height: 14),

                        // Location hierarchy
                        Row(
                          children: [
                            Icon(
                              Icons.location_city_rounded,
                              size: 20,
                              color: AppTheme.secondaryInkOf(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${location.street != null ? "${location.street}, " : ""}${location.barangay ?? "N/A"}, ${location.city ?? "Metro Manila"}',
                                style: context.text.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                /*
                // 2. Mini Interactive Map Card (if location is mappable)
                if (location.isMappable) ...[
                  _buildMiniMapCard(context, location, cabinetColor, isDark),
                  const SizedBox(height: 16),
                ],

                // 3. Port Matrix & Visual Grid
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Title wraps at large text; the total keeps
                            // its size.
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.hub_outlined,
                                      size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Port Matrix & Capacity',
                                      style: context.text.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${location.portTotal} ports total',
                              style: context.text.labelLarge!.copyWith(
                                color: AppTheme.brandInkOf(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Visual Ports Grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.8,
                          ),
                          itemCount: location.portTotal,
                          itemBuilder: (context, index) {
                            final portNumber = index + 1;
                            return Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.darkInput
                                    : AppTheme.lightBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.borderDark
                                      : AppTheme.borderLight,
                                ),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.circle_outlined,
                                      size: 20,
                                      color: AppTheme.secondaryInkOf(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'P$portNumber',
                                      style: context.text.labelSmall!.copyWith(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Standard NAP distribution box. Ready for drop cable splicing.',
                          style: context.text.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Site Enclosure & Reading Photos Card
                // Gene - Oct 24, 2026: Added _buildSitePhotosCard to display enclosure and optical power reading photos.
                _buildSitePhotosCard(context, location, isDark),
                const SizedBox(height: 16),

                // 5. GPS Geolocation Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pin_drop_outlined,
                                size: 18, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'GPS Geolocation Coordinates',
                                style: context.text.titleMedium,
                              ),
                            ),
                            // Gene - Oct 31, 2026: Added quick Map/Update button in GPS header.
                            OutlinedButton.icon(
                              key: const ValueKey('btnHeaderMapLocation'),
                              onPressed: () =>
                                  _showLocationMappingSheet(context, location),
                              icon: Icon(
                                location.isMappable
                                    ? Icons.edit_location_alt_outlined
                                    : Icons.add_location_alt_outlined,
                                size: 18,
                              ),
                              label: Text(location.isMappable
                                  ? 'Update GPS'
                                  : 'Map Site'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                minimumSize: const Size(0, 32),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                isDark ? AppTheme.darkInput : AppTheme.lightBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? AppTheme.borderDark
                                  : AppTheme.borderLight,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WGS84 Coordinates',
                                    style: context.text.labelSmall!
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    location.coordinates ??
                                        'No GPS fix recorded',
                                    style: context.text.titleSmall!
                                        .copyWith(fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                              if (location.coordinates != null)
                                IconButton(
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
                                  tooltip: 'Copy coordinates',
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(
                                          text: location.coordinates!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Copied: ${location.coordinates}'),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: isDark
                                            ? AppTheme.darkCard
                                            : AppTheme.darkSlate,
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                        // Gene - Oct 31, 2026: If site has no coordinates, show prominent Map This Site button.
                        if (!location.isMappable) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const ValueKey('btnMapUnmappedSite'),
                              onPressed: () =>
                                  _showLocationMappingSheet(context, location),
                              icon: const Icon(Icons.add_location_alt_rounded,
                                  size: 18),
                              label: const Text('Map This Site (Set GPS)'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                        if (location.isMappable) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                MapNavigationService.showNavigationChooser(
                                  context: context,
                                  latitude: location.latLng!.latitude,
                                  longitude: location.latLng!.longitude,
                                  title: location.lcpNap,
                                  subtitle:
                                      '${location.street ?? ""}, ${location.barangay ?? ""}, ${location.city ?? ""}',
                                );
                              },
                              icon: const Icon(Icons.navigation_rounded,
                                  size: 18),
                              label:
                                  const Text('Start Turn-by-Turn Navigation'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          // Gene - Oct 31, 2026: Added secondary button to update coordinates.
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey('btnUpdateSiteCoordinates'),
                              onPressed: () =>
                                  _showLocationMappingSheet(context, location),
                              icon: const Icon(Icons.edit_location_alt_outlined,
                                  size: 18),
                              label: const Text('Update GPS Coordinates'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                */
                // Gene - Nov, 12, 2026: Reordered detail layout to Overview -> Unified Location & GPS -> 3 Separate Site Photo Cards -> Port Matrix & Capacity per Calm Utility UX audit.
                _buildLocationAndGpsCard(
                    context, location, cabinetColor, isDark),
                const SizedBox(height: 16),

                ..._buildSitePhotosSection(context, location, isDark),
                const SizedBox(height: 16),

                _buildPortMatrixCard(context, location),
              ],
            ),
          ),
        );
      },
    );
  }

  /*
  Widget _buildMiniMapCard(
    BuildContext context,
    LcpNapDto location,
    Color cabinetColor,
    bool isDark,
  ) {
    final latLng = location.latLng!;
    final tiles = _tiles;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Title wraps at large text; the Navigate button keeps its
                // size.
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 18, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Site Map Location',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    MapNavigationService.showNavigationChooser(
                      context: context,
                      latitude: latLng.latitude,
                      longitude: latLng.longitude,
                      title: location.lcpNap,
                      subtitle:
                          '${location.street ?? ""}, ${location.barangay ?? ""}, ${location.city ?? ""}',
                    );
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 24),
                  label: const Text('Navigate'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: tiles == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                // Gene - Nov, 11, 2026: Key FlutterMap by location ID & coordinates so live GPS auto-sync updates re-center the mini-map immediately.
                : FlutterMap(
                    key: ValueKey(
                        'minimap_${location.id}_${location.coordinates}'),
                    options: MapOptions(
                      initialCenter: latLng,
                      initialZoom: 16,
                      // No drag: the preview sits inside the page's ListView,
                      // so a vertical drag over it panned the map (and lost
                      // the pin) instead of scrolling the page. Pinch and
                      // double-tap still zoom around the site.
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom,
                      ),
                    ),
                    children: [
                      // Gene - Nov, 11, 2026: Pass maxNativeZoom alongside maxZoom on detail screen mini-map TileLayer.
                      TileLayer(
                        urlTemplate: MapTiles.streetUrl,
                        maxNativeZoom: MapTiles.streetMaxNativeZoom,
                        maxZoom: MapTiles.streetMaxZoom,
                        userAgentPackageName: MapTiles.userAgentPackageName,
                        tileProvider: tiles,
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: latLng,
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: cabinetColor,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  location.nap.replaceAll(RegExp(r'\D'), ''),
                                  style: context.text.labelSmall!.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
  */
  // Gene - Nov, 12, 2026: Unified Mini-Map + GPS Geolocation into one Location & GPS Card with JetBrains Mono coordinates, outline status stamp, and 48dp/56dp gloved-thumb CTAs.
  Widget _buildLocationAndGpsCard(
    BuildContext context,
    LcpNapDto location,
    Color cabinetColor,
    bool isDark,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final hairline = AppTheme.hairlineOf(context);
    final isMapped = location.isMappable;
    final statusColor = isMapped
        ? AppTheme.successInkOf(context)
        : AppTheme.warningInkOf(context);

    final stamp = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
        border: Border.all(color: statusColor, width: 1.5),
      ),
      child: Text(
        isMapped ? 'MAPPED' : 'UNMAPPED',
        style: context.text.labelMedium!.copyWith(color: statusColor),
      ),
    );

    final tiles = _tiles;

    final navBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: FilledButton.icon(
        key: const ValueKey('btnNavigateSite'),
        onPressed: isMapped
            ? () {
                MapNavigationService.showNavigationChooser(
                  context: context,
                  latitude: location.latLng!.latitude,
                  longitude: location.latLng!.longitude,
                  title: location.lcpNap,
                  subtitle:
                      '${location.street ?? ""}, ${location.barangay ?? ""}, ${location.city ?? ""}',
                );
              }
            : null,
        icon: const Icon(Icons.navigation_rounded, size: 20),
        label: const Text('Navigate'),
      ),
    );

    final updateBtn = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: OutlinedButton.icon(
        key: const ValueKey('btnUpdateSiteCoordinates'),
        onPressed: () => _showLocationMappingSheet(context, location),
        icon: const Icon(Icons.edit_location_alt_outlined, size: 20),
        label: const Text('Update GPS'),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: scale > 1.5
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pin_drop_outlined,
                              size: 20, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Location & GPS',
                              style: context.text.titleMedium,
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
                      const Icon(Icons.pin_drop_outlined,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location & GPS',
                          style: context.text.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      stamp,
                    ],
                  ),
          ),
          if (isMapped) ...[
            Divider(height: 1, thickness: 1, color: hairline),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: tiles == null
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : FlutterMap(
                      key: ValueKey(
                          'minimap_${location.id}_${location.coordinates}'),
                      options: MapOptions(
                        initialCenter: location.latLng!,
                        initialZoom: 16,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapTiles.streetUrl,
                          maxNativeZoom: MapTiles.streetMaxNativeZoom,
                          maxZoom: MapTiles.streetMaxZoom,
                          userAgentPackageName: MapTiles.userAgentPackageName,
                          tileProvider: tiles,
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: location.latLng!,
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cabinetColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    location.nap.replaceAll(RegExp(r'\D'), ''),
                                    style: context.text.labelSmall!.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
          Divider(height: 1, thickness: 1, color: hairline),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.fillOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WGS84 Coordinates',
                              style: context.text.labelSmall!
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              location.coordinates ?? 'No GPS fix recorded',
                              style: location.coordinates != null
                                  ? context.text.bodyLarge
                                  : context.text.bodySmall!.copyWith(
                                      color: AppTheme.secondaryInkOf(context),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      if (location.coordinates != null)
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: AppTheme.minTarget,
                            minHeight: AppTheme.minTarget,
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          tooltip: 'Copy coordinates',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: location.coordinates!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Copied: ${location.coordinates}'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: isDark
                                    ? AppTheme.darkCard
                                    : AppTheme.darkSlate,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!isMapped)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: AppTheme.primaryButtonHeight),
                    child: ElevatedButton.icon(
                      key: const ValueKey('btnMapUnmappedSite'),
                      onPressed: () =>
                          _showLocationMappingSheet(context, location),
                      icon:
                          const Icon(Icons.add_location_alt_rounded, size: 20),
                      label: const Text('Map This Site (Set GPS)'),
                    ),
                  )
                else if (scale > 1.3)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      navBtn,
                      const SizedBox(height: 8),
                      updateBtn,
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: navBtn),
                      const SizedBox(width: 10),
                      Expanded(child: updateBtn),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Gene - Nov, 12, 2026: Responsive Port Matrix & Capacity card using JetBrains Mono port numbers and 2-col fallback at large text scales.
  Widget _buildPortMatrixCard(BuildContext context, LcpNapDto location) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final hairline = AppTheme.hairlineOf(context);
    final totalBadge = Text(
      '${location.portTotal} ports total',
      style: context.text.labelLarge!.copyWith(
        color: AppTheme.brandInkOf(context),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (scale > 1.5)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hub_outlined,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Port Matrix & Capacity',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  totalBadge,
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.hub_outlined,
                            size: 20, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Port Matrix & Capacity',
                            style: context.text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  totalBadge,
                ],
              ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: scale > 1.3 ? 2 : 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: scale > 1.3 ? 2.1 : 1.8,
              ),
              itemCount: location.portTotal,
              itemBuilder: (context, index) {
                final portNumber = index + 1;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.fillOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hairline),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle_outlined,
                          size: 18,
                          color: AppTheme.secondaryInkOf(context),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'P$portNumber',
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Standard NAP distribution box. Ready for drop cable splicing.',
              style: context.text.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  void _copySiteSummary(BuildContext context, LcpNapDto location, bool isDark) {
    final summary = 'Switch Fiber Plant Record:\n'
        'Site: ${location.lcpNap}\n'
        'Cabinet: ${location.lcp}\n'
        'NAP: ${location.nap}\n'
        'Ports: ${location.portTotal}\n'
        'Address: ${location.street ?? ""}, ${location.barangay ?? ""}, ${location.city ?? ""}\n'
        'GPS: ${location.coordinates ?? "N/A"}';

    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Site summary copied to clipboard!'),
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.darkSlate,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /*
  // Gene - Oct 24, 2026: Site enclosure and optical power reading photos card.
  Widget _buildSitePhotosCard(
    BuildContext context,
    LcpNapDto location,
    bool isDark,
  ) {
  */
  // Gene - Nov, 12, 2026: Replaced single nested _buildSitePhotosCard with _buildSitePhotosSection rendering 3 standalone top-level LcpNapPhotoSlotCards (always visible even when empty) and 1-tap inline upload.
  List<Widget> _buildSitePhotosSection(
    BuildContext context,
    LcpNapDto location,
    bool isDark,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final hairline = AppTheme.hairlineOf(context);

    // When _sitePhotos has been loaded/updated, treat it as authoritative so
    // deleted slots do not fall back to stale location columns.
    final enc1Bytes = _sitePhotos != null
        ? _sitePhotos!.image?.bytes
        : (location.image != null
            ? (PhotoStorageService.instance.resolveBytes(location.image!) ??
                DataUrl.decode(location.image!))
            : null);
    final enc1Url = _sitePhotos == null &&
            location.image != null &&
            (location.image!.startsWith('http://') ||
                location.image!.startsWith('https://'))
        ? location.image!
        : null;

    final enc2Bytes = _sitePhotos != null
        ? _sitePhotos!.image2?.bytes
        : (location.image2 != null
            ? (PhotoStorageService.instance.resolveBytes(location.image2!) ??
                DataUrl.decode(location.image2!))
            : null);
    final enc2Url = _sitePhotos == null &&
            location.image2 != null &&
            (location.image2!.startsWith('http://') ||
                location.image2!.startsWith('https://'))
        ? location.image2!
        : null;

    final readingBytes = _sitePhotos != null
        ? _sitePhotos!.readingImage?.bytes
        : (location.readingImage != null
            ? (PhotoStorageService.instance
                    .resolveBytes(location.readingImage!) ??
                DataUrl.decode(location.readingImage!))
            : null);
    final readingUrl = _sitePhotos == null &&
            location.readingImage != null &&
            (location.readingImage!.startsWith('http://') ||
                location.readingImage!.startsWith('https://'))
        ? location.readingImage!
        : null;

    bool hasSlot(Uint8List? b, String? url) =>
        (b != null && b.isNotEmpty) || (url != null && url.trim().isNotEmpty);

    final uploadedCount = (hasSlot(enc1Bytes, enc1Url) ? 1 : 0) +
        (hasSlot(enc2Bytes, enc2Url) ? 1 : 0) +
        (hasSlot(readingBytes, readingUrl) ? 1 : 0);

    final countColor = uploadedCount > 0
        ? AppTheme.successInkOf(context)
        : AppTheme.secondaryInkOf(context);

    final countStamp = Container(
      key: const ValueKey('sitePhotosCountBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
        border: Border.all(
          color: uploadedCount > 0 ? countColor : hairline,
          width: uploadedCount > 0 ? 1.5 : 1,
        ),
      ),
      child: Text(
        '$uploadedCount of 3 photos',
        style: context.text.labelMedium!.copyWith(color: countColor),
      ),
    );

    final slots = <({
      String key,
      String title,
      String subtitle,
      IconData icon,
      Uint8List? bytes,
      String? remoteUrl,
    })>[
      (
        key: 'enc1',
        title: 'Enclosure Exterior',
        subtitle: 'NAP Box Enclosure 1',
        icon: Icons.router_outlined,
        bytes: enc1Bytes,
        remoteUrl: enc1Url,
      ),
      (
        key: 'enc2',
        title: 'Enclosure Interior',
        subtitle: 'NAP Splicing Tray / Ports',
        icon: Icons.cable_rounded,
        bytes: enc2Bytes,
        remoteUrl: enc2Url,
      ),
      (
        key: 'reading',
        title: 'Optical Power Reading',
        subtitle: 'OPM Power Capture',
        icon: Icons.speed_rounded,
        bytes: readingBytes,
        remoteUrl: readingUrl,
      ),
    ];

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: scale > 1.5
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.photo_library_outlined,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Site Enclosure & Reading Photos',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  countStamp,
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Site Enclosure & Reading Photos',
                      style: context.text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  countStamp,
                ],
              ),
      ),
      if (_isLoadingPhotos && _sitePhotos == null && uploadedCount == 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hairline),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Loading site photos from server...',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 10),
      for (int i = 0; i < slots.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        LcpNapPhotoSlotCard(
          slotKey: slots[i].key,
          title: slots[i].title,
          subtitle: slots[i].subtitle,
          icon: slots[i].icon,
          bytes: slots[i].bytes,
          remoteUrl: slots[i].remoteUrl,
          isBusy: _busyPhotoSlots.contains(slots[i].key),
          busyLabel: _busyPhotoLabels[slots[i].key],
          onTakePhoto: () => _captureAndUploadSlot(
            context,
            location,
            photoKey: slots[i].key,
            photoTitle: slots[i].title,
            source: ImageSource.camera,
          ),
          onPickFromGallery: () => _captureAndUploadSlot(
            context,
            location,
            photoKey: slots[i].key,
            photoTitle: slots[i].title,
            source: ImageSource.gallery,
          ),
          onViewPhoto: () => _openSlotPhotoViewer(
            context,
            title: slots[i].title,
            bytes: slots[i].bytes,
            remoteUrl: slots[i].remoteUrl,
          ),
          onDeletePhoto: () => _confirmDeletePhoto(
            context,
            location,
            photoKey: slots[i].key,
            photoTitle: slots[i].title,
          ),
        ),
      ],
    ];
  }

  void _openSlotPhotoViewer(
    BuildContext context, {
    required String title,
    required Uint8List? bytes,
    required String? remoteUrl,
  }) {
    if (bytes != null && bytes.isNotEmpty) {
      showPhotoViewer(context, bytes, title: title);
    } else if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
      showPhotoViewer(
        context,
        Uint8List(0),
        title: title,
        imageUrl: remoteUrl,
      );
    }
  }

  LcpNapImageFileDto? _resolveSlotFileDto({
    required LcpNapImageFileDto? currentDto,
    required String? fallbackLocationField,
    required String downloadName,
  }) {
    if (_sitePhotos != null) return currentDto;
    final raw = fallbackLocationField?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return null;
    final decoded =
        PhotoStorageService.instance.resolveBytes(raw) ?? DataUrl.decode(raw);
    if (decoded == null || decoded.isEmpty) return null;
    return LcpNapImageFileDto(
      fileContents: base64Encode(decoded),
      contentType: 'image/jpeg',
      fileDownloadName: downloadName,
    );
  }

  // Gene - Nov, 12, 2026: 1-tap Camera or Gallery capture + immediate per-card upload without an intermediate staging sheet.
  Future<void> _captureAndUploadSlot(
    BuildContext context,
    LcpNapDto location, {
    required String photoKey,
    required String photoTitle,
    required ImageSource source,
  }) async {
    if (_busyPhotoSlots.contains(photoKey)) return;

    String? picked;
    try {
      if (widget.pickImageForTesting != null) {
        picked = await widget.pickImageForTesting!(source);
      } else {
        picked = await ImageCaptureService.instance.pickAsDataUrl(
          source,
          fallbackLat: location.latitude,
          fallbackLng: location.longitude,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('Could not capture photo: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (picked == null || picked.trim().isEmpty || !mounted) return;

    final rawBytes = PhotoStorageService.instance.resolveBytes(picked) ??
        DataUrl.decode(picked);
    if (rawBytes == null || rawBytes.isEmpty) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('Selected image could not be read.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _busyPhotoSlots.add(photoKey);
      _busyPhotoLabels[photoKey] = 'Uploading $photoTitle...';
    });

    try {
      if (_sitePhotos != null) {
        widget.signals.repository.seedImagesCache(location.id, _sitePhotos!);
      }

      final success = await widget.signals.uploadLocationPhotos(
        locationId: location.id,
        location: location,
        imageBytes: photoKey == 'enc1' ? rawBytes : null,
        image2Bytes: photoKey == 'enc2' ? rawBytes : null,
        readingImageBytes: photoKey == 'reading' ? rawBytes : null,
      );

      if (!mounted) return;
      if (success) {
        final newSlotDto = LcpNapImageFileDto(
          fileContents: base64Encode(rawBytes),
          contentType: 'image/jpeg',
          fileDownloadName: photoKey == 'enc1'
              ? 'image.jpg'
              : (photoKey == 'enc2' ? 'image2.jpg' : 'readingImage.jpg'),
        );
        final updatedDto = LcpNapImagesDto(
          image: photoKey == 'enc1'
              ? newSlotDto
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.image,
                  fallbackLocationField: location.image,
                  downloadName: 'image.jpg',
                ),
          image2: photoKey == 'enc2'
              ? newSlotDto
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.image2,
                  fallbackLocationField: location.image2,
                  downloadName: 'image2.jpg',
                ),
          readingImage: photoKey == 'reading'
              ? newSlotDto
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.readingImage,
                  fallbackLocationField: location.readingImage,
                  downloadName: 'readingImage.jpg',
                ),
        );
        setState(() => _sitePhotos = updatedDto);
        await _loadSitePhotos(forceRefresh: true, silent: true);
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$photoTitle uploaded successfully!'),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text(
              widget.signals.errorMessage.value ??
                  'Failed to upload $photoTitle. Please check your connection.',
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyPhotoSlots.remove(photoKey);
          _busyPhotoLabels.remove(photoKey);
        });
      }
    }
  }

  /*
  Widget _buildSitePhotosCard_previous(
    BuildContext context,
    LcpNapDto location,
    bool isDark,
  ) {
    /*
    // Resolve photos from live API DTO or base location DTO
    final enc1Bytes = _sitePhotos?.image?.bytes ??
        (location.image != null
            ? (PhotoStorageService.instance.resolveBytes(location.image!) ??
                DataUrl.decode(location.image!))
            : null);
    final enc1Url = location.image != null &&
            (location.image!.startsWith('http://') ||
                location.image!.startsWith('https://'))
        ? location.image!
        : null;

    final enc2Bytes = _sitePhotos?.image2?.bytes ??
        (location.image2 != null
            ? (PhotoStorageService.instance.resolveBytes(location.image2!) ??
                DataUrl.decode(location.image2!))
            : null);
    final enc2Url = location.image2 != null &&
            (location.image2!.startsWith('http://') ||
                location.image2!.startsWith('https://'))
        ? location.image2!
        : null;

    final readingBytes = _sitePhotos?.readingImage?.bytes ??
        (location.readingImage != null
            ? (PhotoStorageService.instance
                    .resolveBytes(location.readingImage!) ??
                DataUrl.decode(location.readingImage!))
            : null);
    final readingUrl = location.readingImage != null &&
            (location.readingImage!.startsWith('http://') ||
                location.readingImage!.startsWith('https://'))
        ? location.readingImage!
        : null;
    */
    // Gene - Nov, 8, 2026: When _sitePhotos has been loaded/updated, treat it as authoritative so deleted slots do not fall back to stale location columns.
    final enc1Bytes = _sitePhotos != null
        ? _sitePhotos!.image?.bytes
        : (location.image != null
            ? (PhotoStorageService.instance.resolveBytes(location.image!) ??
                DataUrl.decode(location.image!))
            : null);
    final enc1Url = _sitePhotos == null &&
            location.image != null &&
            (location.image!.startsWith('http://') ||
                location.image!.startsWith('https://'))
        ? location.image!
        : null;

    final enc2Bytes = _sitePhotos != null
        ? _sitePhotos!.image2?.bytes
        : (location.image2 != null
            ? (PhotoStorageService.instance.resolveBytes(location.image2!) ??
                DataUrl.decode(location.image2!))
            : null);
    final enc2Url = _sitePhotos == null &&
            location.image2 != null &&
            (location.image2!.startsWith('http://') ||
                location.image2!.startsWith('https://'))
        ? location.image2!
        : null;

    final readingBytes = _sitePhotos != null
        ? _sitePhotos!.readingImage?.bytes
        : (location.readingImage != null
            ? (PhotoStorageService.instance
                    .resolveBytes(location.readingImage!) ??
                DataUrl.decode(location.readingImage!))
            : null);
    final readingUrl = _sitePhotos == null &&
            location.readingImage != null &&
            (location.readingImage!.startsWith('http://') ||
                location.readingImage!.startsWith('https://'))
        ? location.readingImage!
        : null;

    final photos = <({
      String key,
      String title,
      String subtitle,
      IconData icon,
      Uint8List? bytes,
      String? remoteUrl
    })>[
      if (enc1Bytes != null || enc1Url != null)
        (
          key: 'enc1',
          title: 'Enclosure Exterior',
          subtitle: 'NAP Box Enclosure 1',
          icon: Icons.router_outlined,
          bytes: enc1Bytes,
          remoteUrl: enc1Url,
        ),
      if (enc2Bytes != null || enc2Url != null)
        (
          key: 'enc2',
          title: 'Enclosure Interior',
          subtitle: 'NAP Splicing Tray / Ports',
          icon: Icons.cable_rounded,
          bytes: enc2Bytes,
          remoteUrl: enc2Url,
        ),
      if (readingBytes != null || readingUrl != null)
        (
          key: 'reading',
          title: 'Optical Power Reading',
          subtitle: 'OPM Power Capture',
          icon: Icons.speed_rounded,
          bytes: readingBytes,
          remoteUrl: readingUrl,
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Gene - Oct 24, 2026: Kept icon size at 20 standard floor for decorative icons.
                /*
                const Icon(Icons.photo_library_outlined,
                    size: 18, color: AppTheme.primary),
                */
                const Icon(Icons.photo_library_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Site Enclosure & Reading Photos',
                    style: context.text.titleMedium,
                  ),
                ),
                /*
                if (photos.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppTheme.darkInput : AppTheme.primarySubtleBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.primarySubtleBorder,
                      ),
                    ),
                    child: Text(
                      '${photos.length} photos',
                      style: context.text.labelSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandInkOf(context),
                      ),
                    ),
                  ),
                */
                // Gene - Oct 29, 2026: Added photo count badge and Update action button in site photos header.
                if (photos.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkInput
                          : AppTheme.primarySubtleBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.primarySubtleBorder,
                      ),
                    ),
                    child: Text(
                      '${photos.length} photos',
                      style: context.text.labelSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandInkOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showUploadPhotosSheet(context, location),
                    /*
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16), // map furniture
                    */
                    // Gene - Oct 29, 2026: Set icon size to 18 to comply with UI icon floor standard.
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Update'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            if (_isLoadingPhotos)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading site photos from server...',
                      style: context.text.bodySmall!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (photos.isEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_camera_back_outlined,
                      size: 32,
                      color: AppTheme.secondaryInkOf(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No enclosure or optical reading photos uploaded yet.',
                      style: context.text.bodySmall!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _showUploadPhotosSheet(context, location),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Upload Site Photos'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < photos.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _buildPhotoItem(
                      context,
                      location: location,
                      photoKey: photos[i].key,
                      title: photos[i].title,
                      subtitle: photos[i].subtitle,
                      icon: photos[i].icon,
                      bytes: photos[i].bytes,
                      remoteUrl: photos[i].remoteUrl,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoItem(
    BuildContext context, {
    required LcpNapDto location,
    required String photoKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Uint8List? bytes,
    required String? remoteUrl,
    required bool isDark,
  }) {
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
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: [
                // Gene - Oct 24, 2026: Set icon size to 20 to match standard decorative icon floor.
                /*
                Icon(icon, size: 18, color: AppTheme.primary),
                */
                Icon(icon, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.text.labelMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: context.text.labelSmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Gene - Oct 31, 2026: Added direct delete photo button to clear/delete image on the server.
                IconButton(
                  icon: const Icon(CupertinoIcons.trash, size: 20),
                  color: AppTheme.dangerInkOf(context),
                  tooltip: 'Delete $title',
                  onPressed: () => _confirmDeletePhoto(
                    context,
                    location,
                    photoKey: photoKey,
                    photoTitle: title,
                  ),
                ),
              ],
            ),
          ),
          /*
          InkWell(
            onTap: () {
              if (bytes != null) {
                showPhotoViewer(context, bytes, title: title);
              } else if (remoteUrl != null) {
                launchUrl(Uri.parse(remoteUrl),
                    mode: LaunchMode.externalApplication);
              }
            },
          */
          // Gene - Nov, 8, 2026: Open both inline bytes and remote URLs inside the in-app full-screen photo viewer.
          InkWell(
            onTap: () {
              if (bytes != null) {
                showPhotoViewer(context, bytes, title: title);
              } else if (remoteUrl != null) {
                showPhotoViewer(
                  context,
                  Uint8List(0),
                  title: title,
                  imageUrl: remoteUrl,
                );
              }
            },
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                    )
                  else if (remoteUrl != null)
                    Image.network(
                      remoteUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 32),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
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
                          // Gene - Oct 24, 2026: Updated zoom icon size from 16 to 20 to conform with standard 20px floor.
                          /*
                          const Icon(CupertinoIcons.zoom_in,
                              size: 16, // map furniture
                              color: Colors.white),
                          */
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
  */

  // Gene - Oct 31, 2026: Confirms and deletes/clears a single photo directly from the photo card.
  Future<void> _confirmDeletePhoto(
    BuildContext context,
    LcpNapDto location, {
    required String photoKey,
    required String photoTitle,
  }) async {
    if (_busyPhotoSlots.contains(photoKey)) return;
    /*
    final isDark = Theme.of(context).brightness == Brightness.dark;
    */
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $photoTitle?'),
        content: Text(
          'Are you sure you want to delete this photo for ${location.lcpNap}? This will clear the image on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    /*
    final success = await widget.signals.uploadLocationPhotos(
      locationId: location.id,
      location: location,
      clearImage: photoKey == 'enc1',
      clearImage2: photoKey == 'enc2',
      clearReadingImage: photoKey == 'reading',
    );

    if (!mounted) return;
    if (success) {
      await _loadSitePhotos();
      if (!mounted) return;
    */
    /*
    // Gene - Nov, 8, 2026: Seed current _sitePhotos into repository cache before deleting so sibling photos are preserved, then optimistically remove the deleted slot and force-refresh from live API.
    if (_sitePhotos != null) {
      widget.signals.repository.seedImagesCache(location.id, _sitePhotos!);
    }

    final success = await widget.signals.uploadLocationPhotos(
      locationId: location.id,
      location: location,
      clearImage: photoKey == 'enc1',
      clearImage2: photoKey == 'enc2',
      clearReadingImage: photoKey == 'reading',
    );

    if (!mounted) return;
    if (success) {
      final updatedPhotos = LcpNapImagesDto(
        image: photoKey == 'enc1' ? null : _sitePhotos?.image,
        image2: photoKey == 'enc2' ? null : _sitePhotos?.image2,
        readingImage: photoKey == 'reading' ? null : _sitePhotos?.readingImage,
      );
      setState(() => _sitePhotos = updatedPhotos);
      await _loadSitePhotos(forceRefresh: true, silent: true);
      if (!mounted) return;
    */
    // Gene - Nov, 12, 2026: Show per-card busy spinner while deleting and preserve sibling slot DTOs even when _sitePhotos had not been loaded yet.
    setState(() {
      _busyPhotoSlots.add(photoKey);
      _busyPhotoLabels[photoKey] = 'Deleting $photoTitle...';
    });

    try {
      if (_sitePhotos != null) {
        widget.signals.repository.seedImagesCache(location.id, _sitePhotos!);
      }

      final success = await widget.signals.uploadLocationPhotos(
        locationId: location.id,
        location: location,
        clearImage: photoKey == 'enc1',
        clearImage2: photoKey == 'enc2',
        clearReadingImage: photoKey == 'reading',
      );

      if (!mounted) return;
      if (success) {
        final updatedPhotos = LcpNapImagesDto(
          image: photoKey == 'enc1'
              ? null
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.image,
                  fallbackLocationField: location.image,
                  downloadName: 'image.jpg',
                ),
          image2: photoKey == 'enc2'
              ? null
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.image2,
                  fallbackLocationField: location.image2,
                  downloadName: 'image2.jpg',
                ),
          readingImage: photoKey == 'reading'
              ? null
              : _resolveSlotFileDto(
                  currentDto: _sitePhotos?.readingImage,
                  fallbackLocationField: location.readingImage,
                  downloadName: 'readingImage.jpg',
                ),
        );
        setState(() => _sitePhotos = updatedPhotos);
        await _loadSitePhotos(forceRefresh: true, silent: true);
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$photoTitle deleted successfully!'),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text(
              widget.signals.errorMessage.value ??
                  'Failed to delete photo. Please check your connection.',
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyPhotoSlots.remove(photoKey);
          _busyPhotoLabels.remove(photoKey);
        });
      }
    }
  }

  /*
  // Gene - Oct 29, 2026: Opens modal bottom sheet to capture and upload LCP NAP site enclosure and reading photos.
  // Gene - Nov, 12, 2026: Commented out staging sheet helper in favor of 1-tap inline per-card upload (_captureAndUploadSlot).
  Future<void> _showUploadPhotosSheet(
    BuildContext context,
    LcpNapDto location,
  ) async {
    // Gene - Nov, 8, 2026: Receive updated LcpNapImagesDto from upload sheet, apply immediately, and force-refresh from live server.
    final updated = await showModalBottomSheet<LcpNapImagesDto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LcpNapUploadPhotosSheet(
        location: location,
        signals: widget.signals,
        initialImages: _sitePhotos,
        pickImageForTesting: widget.pickImageForTesting,
      ),
    );

    if (updated != null) {
      if (mounted) {
        setState(() => _sitePhotos = updated);
      }
      await _loadSitePhotos(forceRefresh: true, silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Site photos uploaded successfully!'),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  */

  // Gene - Oct 31, 2026: Opens modal bottom sheet to map or update LCP NAP location coordinates.
  Future<void> _showLocationMappingSheet(
    BuildContext context,
    LcpNapDto location,
  ) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LcpNapLocationPickerSheet(
        location: location,
        signals: widget.signals,
        tileProvider: _tiles,
        locationService: widget.locationServiceForTesting,
        placeLookup: widget.placeLookupForTesting,
        reverseGeocodeForTesting: widget.reverseGeocodeForTesting,
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child:
                    Text('LCP NAP location coordinates updated successfully!'),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Gene - Nov, 11, 2026: Opens modal bottom sheet to edit LCP NAP site details (LCP, NAP, PortTotal, address, and optional GPS coordinates).
  Future<void> _showEditSiteDetailsSheet(
    BuildContext context,
    LcpNapDto location,
  ) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LcpNapLocationPickerSheet(
        location: location,
        signals: widget.signals,
        tileProvider: _tiles,
        locationService: widget.locationServiceForTesting,
        placeLookup: widget.placeLookupForTesting,
        reverseGeocodeForTesting: widget.reverseGeocodeForTesting,
        allowEmptyCoordinates: true,
        sheetTitle: 'Edit LCP NAP Details',
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('LCP NAP site details updated successfully!'),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/*
// Gene - Nov, 12, 2026: Commented out _LcpNapUploadPhotosSheet after replacing multi-step modal upload with 1-tap inline LcpNapPhotoSlotCard upload.
// Gene - Oct 29, 2026: Modal bottom sheet for capturing and uploading LCP NAP site enclosure and reading photos.
class _LcpNapUploadPhotosSheet extends StatefulWidget {
  final LcpNapDto location;
  final LcpNapSignals signals;
  final LcpNapImagesDto? initialImages;
  final Future<String?> Function(ImageSource source)? pickImageForTesting;

  const _LcpNapUploadPhotosSheet({
    required this.location,
    required this.signals,
    this.initialImages,
    this.pickImageForTesting,
  });

  @override
  State<_LcpNapUploadPhotosSheet> createState() =>
      _LcpNapUploadPhotosSheetState();
}

class _LcpNapUploadPhotosSheetState extends State<_LcpNapUploadPhotosSheet> {
  String? _enc1;
  String? _enc2;
  String? _reading;
  bool _isUploading = false;
  String? _uploadError;

  /*
  @override
  void initState() {
    super.initState();
    _enc1 = widget.initialImages?.image?.dataUrl;
    _enc2 = widget.initialImages?.image2?.dataUrl;
    _reading = widget.initialImages?.readingImage?.dataUrl;
  }

  Future<void> _submit() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    final enc1Bytes = _enc1 != null && _enc1!.trim().isNotEmpty
        ? DataUrl.decode(_enc1!)
        : null;
    final enc2Bytes = _enc2 != null && _enc2!.trim().isNotEmpty
        ? DataUrl.decode(_enc2!)
        : null;
    final readingBytes = _reading != null && _reading!.trim().isNotEmpty
        ? DataUrl.decode(_reading!)
        : null;

    // Gene - Oct 31, 2026: Determine whether an image was explicitly deleted/cleared (was previously present, now empty/null).
    final hadEnc1 = widget.initialImages?.image?.hasImage == true;
    final hadEnc2 = widget.initialImages?.image2?.hasImage == true;
    final hadReading = widget.initialImages?.readingImage?.hasImage == true;

    final clearEnc1 = hadEnc1 && (enc1Bytes == null || enc1Bytes.isEmpty);
    final clearEnc2 = hadEnc2 && (enc2Bytes == null || enc2Bytes.isEmpty);
    final clearReading =
        hadReading && (readingBytes == null || readingBytes.isEmpty);

    final success = await widget.signals.uploadLocationPhotos(
      locationId: widget.location.id,
      location: widget.location,
      imageBytes: enc1Bytes,
      image2Bytes: enc2Bytes,
      readingImageBytes: readingBytes,
      clearImage: clearEnc1,
      clearImage2: clearEnc2,
      clearReadingImage: clearReading,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isUploading = false;
        _uploadError = widget.signals.errorMessage.value ??
            'Failed to upload photos. Please check your connection.';
      });
    }
  }
  */
  /*
  // Gene - Nov, 8, 2026: Fall back to location photo fields on initState, seed repository cache, and return updated LcpNapImagesDto on success.
  @override
  void initState() {
    super.initState();
    _enc1 = widget.initialImages?.image?.dataUrl ?? widget.location.image;
    _enc2 = widget.initialImages?.image2?.dataUrl ?? widget.location.image2;
    _reading = widget.initialImages?.readingImage?.dataUrl ??
        widget.location.readingImage;
  }
  */
  // Gene - Nov, 11, 2026: Normalize empty-string offline deletion sentinels ('') to null so PhotoCaptureTile treats cleared slots as empty.
  static String? _nonEmptyOrNull(String? raw) =>
      (raw != null && raw.trim().isNotEmpty) ? raw : null;

  @override
  void initState() {
    super.initState();
    _enc1 = widget.initialImages?.image?.dataUrl ??
        _nonEmptyOrNull(widget.location.image);
    _enc2 = widget.initialImages?.image2?.dataUrl ??
        _nonEmptyOrNull(widget.location.image2);
    _reading = widget.initialImages?.readingImage?.dataUrl ??
        _nonEmptyOrNull(widget.location.readingImage);
  }

  Future<void> _submit() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    if (widget.initialImages != null) {
      widget.signals.repository.seedImagesCache(
        widget.location.id,
        widget.initialImages!,
      );
    }

    final enc1Bytes = _enc1 != null && _enc1!.trim().isNotEmpty
        ? (PhotoStorageService.instance.resolveBytes(_enc1!) ??
            DataUrl.decode(_enc1!))
        : null;
    final enc2Bytes = _enc2 != null && _enc2!.trim().isNotEmpty
        ? (PhotoStorageService.instance.resolveBytes(_enc2!) ??
            DataUrl.decode(_enc2!))
        : null;
    final readingBytes = _reading != null && _reading!.trim().isNotEmpty
        ? (PhotoStorageService.instance.resolveBytes(_reading!) ??
            DataUrl.decode(_reading!))
        : null;

    final hadEnc1 = (widget.initialImages?.image?.hasImage == true) ||
        (widget.location.image?.trim().isNotEmpty == true);
    final hadEnc2 = (widget.initialImages?.image2?.hasImage == true) ||
        (widget.location.image2?.trim().isNotEmpty == true);
    final hadReading = (widget.initialImages?.readingImage?.hasImage == true) ||
        (widget.location.readingImage?.trim().isNotEmpty == true);

    final clearEnc1 = hadEnc1 && (enc1Bytes == null || enc1Bytes.isEmpty);
    final clearEnc2 = hadEnc2 && (enc2Bytes == null || enc2Bytes.isEmpty);
    final clearReading =
        hadReading && (readingBytes == null || readingBytes.isEmpty);

    final success = await widget.signals.uploadLocationPhotos(
      locationId: widget.location.id,
      location: widget.location,
      imageBytes: enc1Bytes,
      image2Bytes: enc2Bytes,
      readingImageBytes: readingBytes,
      clearImage: clearEnc1,
      clearImage2: clearEnc2,
      clearReadingImage: clearReading,
    );

    if (!mounted) return;
    if (success) {
      final updatedDto = LcpNapImagesDto(
        image: clearEnc1
            ? null
            : (enc1Bytes != null && enc1Bytes.isNotEmpty
                ? LcpNapImageFileDto(
                    fileContents: base64Encode(enc1Bytes),
                    contentType: 'image/jpeg',
                    fileDownloadName: 'image.jpg',
                  )
                : widget.initialImages?.image),
        image2: clearEnc2
            ? null
            : (enc2Bytes != null && enc2Bytes.isNotEmpty
                ? LcpNapImageFileDto(
                    fileContents: base64Encode(enc2Bytes),
                    contentType: 'image/jpeg',
                    fileDownloadName: 'image2.jpg',
                  )
                : widget.initialImages?.image2),
        readingImage: clearReading
            ? null
            : (readingBytes != null && readingBytes.isNotEmpty
                ? LcpNapImageFileDto(
                    fileContents: base64Encode(readingBytes),
                    contentType: 'image/jpeg',
                    fileDownloadName: 'readingImage.jpg',
                  )
                : widget.initialImages?.readingImage),
      );
      Navigator.of(context).pop(updatedDto);
    } else {
      setState(() {
        _isUploading = false;
        _uploadError = widget.signals.errorMessage.value ??
            'Failed to upload photos. Please check your connection.';
      });
    }
  }

  Future<String?> _pick(ImageSource source) {
    if (widget.pickImageForTesting != null) {
      return widget.pickImageForTesting!(source);
    }
    return ImageCaptureService.instance.pickAsDataUrl(
      source,
      fallbackLat: widget.location.latitude,
      fallbackLng: widget.location.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          // iOS Grabber Pill
          Container(
            width: 36,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Site Photos',
                        style: context.text.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.location.lcpNap,
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed:
                      _isUploading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                if (_uploadError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _uploadError!,
                      style: context.text.bodySmall!
                          .copyWith(color: AppTheme.danger),
                    ),
                  ),
                ],
                PhotoCaptureTile(
                  key: const ValueKey('enc1'),
                  label: 'Enclosure Exterior',
                  hint: 'NAP Box Enclosure 1',
                  icon: Icons.router_outlined,
                  value: _enc1,
                  pick: _pick,
                  onChanged: (v) => setState(() => _enc1 = v),
                ),
                const SizedBox(height: 12),
                PhotoCaptureTile(
                  key: const ValueKey('enc2'),
                  label: 'Enclosure Interior',
                  hint: 'NAP Splicing Tray / Ports',
                  icon: Icons.cable_rounded,
                  value: _enc2,
                  pick: _pick,
                  onChanged: (v) => setState(() => _enc2 = v),
                ),
                const SizedBox(height: 12),
                PhotoCaptureTile(
                  key: const ValueKey('reading'),
                  label: 'Optical Power Reading',
                  hint: 'OPM Power Capture',
                  icon: Icons.speed_rounded,
                  value: _reading,
                  pick: _pick,
                  onChanged: (v) => setState(() => _reading = v),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, bottomPadding > 0 ? bottomPadding : 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  width: 0.5,
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _submit,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 20),
                label: Text(_isUploading
                    ? 'Uploading Photos...'
                    : 'Save & Upload Photos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
*/
