import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../models/lcp_nap_model.dart';
import '../services/map_clustering.dart';
import '../services/map_tiles.dart';
import '../signals/lcp_nap_signals.dart';
import 'lcp_nap_pin_popup.dart';
import 'map_search_bar.dart';
// Gene - Oct 31, 2026: Imported LcpNapLocationPickerSheet to support mapping unmapped sites from the map.
import 'lcp_nap_location_picker_sheet.dart';
// Gene - Nov, 12, 2026: Imported LcpNapFloatingAddButton for bottom-left Map view Add LCP NAP action.
import 'lcp_nap_floating_add_button.dart';

/// Map of LCP NAP sites, driven by the same filtered signal as the list view.
///
/// [tileProvider] is injectable so widget tests can supply one that never hits
/// the network.
class LcpNapMapView extends StatefulWidget {
  final LcpNapSignals signals;
  final TileProvider? tileProvider;
  final void Function(LcpNapDto location)? onOpenDetails;

  /// Place search backend. Defaults to the phone's own geocoder; tests
  /// inject a fake so they never touch the platform plugin.
  final PlaceLookup? placeLookup;
  // Gene - Nov, 12, 2026: Optional callback to open Create LCP NAP sheet from the bottom-left floating button on Map view.
  final VoidCallback? onCreateSite;
  // Gene - Nov, 21, 2026: Injectable LocationService so Plant map auto-locate works cleanly and is widget-testable.
  final LocationService? locationService;

  /*
  const LcpNapMapView({
    super.key,
    required this.signals,
    this.tileProvider,
    this.onOpenDetails,
    this.placeLookup,
  });
  */
  /*
  const LcpNapMapView({
    super.key,
    required this.signals,
    this.tileProvider,
    this.onOpenDetails,
    this.placeLookup,
    this.onCreateSite,
  });
  */
  const LcpNapMapView({
    super.key,
    required this.signals,
    this.tileProvider,
    this.onOpenDetails,
    this.placeLookup,
    this.onCreateSite,
    this.locationService,
  });

  @override
  State<LcpNapMapView> createState() => _LcpNapMapViewState();
}

class _LcpNapMapViewState extends State<LcpNapMapView> {
  final MapController _mapController = MapController();

  /// Centre used before any site has loaded: Binangonan, Rizal, where the
  /// current plant records sit.
  static const LatLng _fallbackCentre = LatLng(14.4695, 121.1956);

  TileProvider? _tiles;
  LcpNapDto? _selected;
  bool _didInitialFit = false;
  bool _mapReady = false;
  List<LcpNapDto>? _pendingFit;
  bool _satellite = false;
  bool _showLegend = false;
  double _zoom = 14;

  /// The floating column across the top of the map (place search, the
  /// unmapped-sites notice, legend and base-layer row). Measured so a camera
  /// fit can keep pins and cluster badges out from under it.
  final GlobalKey _overlayKey = GlobalKey();

  /// Where the last place search landed, and what was typed to get there.
  LatLng? _searchTarget;
  String? _searchLabel;
  // Gene - Nov, 21, 2026: Track technician GPS marker and pending camera move for the Plant map auto-locate control.
  LatLng? _userLocation;
  bool _isLocating = false;
  LatLng? _pendingUserMove;
  // Gene - Nov, 23, 2026: Track offline tile prefetch state for the Plant map Cache area control.
  bool _isPrefetchingTiles = false;

  Future<void> _prefetchVisibleArea() async {
    if (_isPrefetchingTiles) return;
    LatLng center = _fallbackCentre;
    try {
      center = _mapController.camera.center;
    } catch (_) {
      center = _fallbackCentre;
    }
    setState(() => _isPrefetchingTiles = true);
    try {
      final result = await MapTiles.prefetchArea(
        centerLat: center.latitude,
        centerLng: center.longitude,
        satellite: _satellite,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cached ${result.downloaded} of ${result.total} map tiles for offline viewing',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrefetchingTiles = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tiles = widget.tileProvider;
    if (_tiles == null) _loadTileProvider();
  }

  // Gene - Nov, 21, 2026: Dispose MapController when LcpNapMapView unmounts.
  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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

  /// Drop a pin at a searched place and fly the map to it.
  void _onPlaceLocated(LatLng target, String query) {
    setState(() {
      _searchTarget = target;
      _searchLabel = query;
      _selected = null;
      _showLegend = false;
    });
    _mapController.move(target, 17);
  }

  // Gene - Oct 31, 2026: Shows modal bottom sheet listing unmapped sites to allow technicians to map their GPS locations.
  Future<void> _showUnmappedSitesSheet(
      BuildContext context, List<LcpNapDto> unmappedSites) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.location_off_outlined,
                      size: 22, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unmapped Sites (${unmappedSites.length})',
                          style: context.text.titleMedium,
                        ),
                        Text(
                          'Select a site to map its GPS coordinates',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: unmappedSites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final site = unmappedSites[index];
                  final hue = lcpColorSeed(site.lcp);
                  final color = HSLColor.fromAHSL(1, hue, 0.62, 0.44).toColor();

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            isDark ? AppTheme.borderDark : AppTheme.borderLight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                site.lcpNap,
                                style: context.text.labelLarge!.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (site.barangay != null || site.city != null)
                                Text(
                                  [site.barangay, site.city]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(', '),
                                  style: context.text.labelSmall!.copyWith(
                                    color: AppTheme.secondaryInkOf(context),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await showModalBottomSheet<bool>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (sheetCtx) => LcpNapLocationPickerSheet(
                                location: site,
                                signals: widget.signals,
                                tileProvider: _tiles,
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_location_alt_rounded,
                              size: 18),
                          label: const Text('Map'),
                          /*
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: const Size(0, 32),
                          ),
                          */
                          // Gene - Nov, 12, 2026: Enforced 48dp minimum touch target height per DESIGN.md.
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            minimumSize: const Size(
                                AppTheme.minTarget, AppTheme.minTarget),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pixels the top overlay covers, including its 8px margins, capped so a
  /// tall overlay (large text, expanded legend) never eats the whole map.
  double _overlayInset() {
    final box = _overlayKey.currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    final cap = _mapController.camera.nonRotatedSize.height * 0.4;
    return (8 + height + 8).clamp(0.0, cap);
  }

  void _fitToSites(List<LcpNapDto> sites) {
    final points = sites.map((s) => s.latLng!).toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.fromLTRB(48, 48 + _overlayInset(), 48, 48),
      ),
    );
  }

  void _zoomIn() {
    /*
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom + 1).clamp(3.0, 19.0),
    );
    */
    // Gene - Nov, 11, 2026: Allow zooming in up to MapTiles.streetMaxZoom (22) for pole-level detail.
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom + 1).clamp(3.0, MapTiles.streetMaxZoom),
    );
  }

  void _zoomOut() {
    /*
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom - 1).clamp(3.0, 19.0),
    );
    */
    // Gene - Nov, 11, 2026: Clamp zoom out against MapTiles.streetMaxZoom (22).
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom - 1).clamp(3.0, MapTiles.streetMaxZoom),
    );
  }

  /// Frame every site the first time records arrive, so the technician opens
  /// the map on their whole plant rather than zoomed onto one arbitrary box.
  /// Sites load asynchronously from the local database, so this cannot be done via
  /// MapOptions' initial camera alone.
  ///
  /// Waits for [MapOptions.onMapReady]: a camera fit issued in the very
  /// first frame, before flutter_map has finished initialising, moved the
  /// camera but never triggered a tile load, so the overview opened as pins
  /// on a blank grey background until the technician panned.
  void _fitOnFirstLoad(List<LcpNapDto> sites) {
    if (_didInitialFit || sites.isEmpty) return;
    if (!_mapReady) {
      _pendingFit = sites;
      return;
    }
    _didInitialFit = true;
    _pendingFit = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToSites(sites);
    });
  }

  /*
  void _onMapReady() {
    _mapReady = true;
    final pending = _pendingFit;
    if (pending != null) _fitOnFirstLoad(pending);
  }
  */
  // Gene - Nov, 21, 2026: Flush queued auto-locate camera move on map ready and expose _locateUser() for Plant map GPS centering.
  void _onMapReady() {
    _mapReady = true;
    final pendingUser = _pendingUserMove;
    if (pendingUser != null) {
      _pendingUserMove = null;
      _pendingFit = null;
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(pendingUser, 18);
        } catch (_) {}
      });
      return;
    }
    final pending = _pendingFit;
    if (pending != null) _fitOnFirstLoad(pending);
  }

  Future<void> _locateUser() async {
    setState(() => _isLocating = true);
    try {
      final service = widget.locationService ?? LocationService.instance;
      final pos = await service.getCurrentPosition();
      if (!mounted) return;
      if (pos != null) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _userLocation = target;
          _selected = null;
          _showLegend = false;
          _didInitialFit = true;
        });
        if (_mapReady) {
          try {
            _mapController.move(target, 18);
          } catch (_) {
            _pendingUserMove = target;
          }
        } else {
          _pendingUserMove = target;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not acquire current GPS location. Please check location permissions.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not acquire current GPS location. Please check location permissions.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Zoom to a cluster's members so they separate into individual pins.
  void _zoomInto(MapCluster cluster) {
    final points = cluster.sites.map((s) => s.latLng!).toList();
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.fromLTRB(64, 64 + _overlayInset(), 64, 64),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;
    if (tiles == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return SignalBuilder(
      builder: (context) {
        final sites = widget.signals.mappableLocations.value;
        final unmappedSites = widget.signals.unmappedLocations.value;
        final unmapped = unmappedSites.length;
        _fitOnFirstLoad(sites);

        // A site can disappear from the filtered set while its popup is open.
        final selected =
            _selected != null && sites.any((s) => s.id == _selected!.id)
                ? sites.firstWhere((s) => s.id == _selected!.id)
                : null;

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    sites.isNotEmpty ? sites.first.latLng! : _fallbackCentre,
                initialZoom: sites.isEmpty ? 11 : 14,
                // Gene - Nov, 11, 2026: Explicitly allow zooming up to MapTiles.streetMaxZoom (22).
                minZoom: 3,
                maxZoom: MapTiles.streetMaxZoom,
                onMapReady: _onMapReady,
                onTap: (_, __) => setState(() {
                  _selected = null;
                  _showLegend = false;
                  _searchTarget = null;
                }),
                onPositionChanged: (camera, _) {
                  // Re-cluster as the technician zooms.
                  if ((camera.zoom - _zoom).abs() >= 0.5) {
                    setState(() => _zoom = camera.zoom);
                  }
                },
              ),
              children: [
                /*
                TileLayer(
                  urlTemplate:
                      _satellite ? MapTiles.satelliteUrl : MapTiles.streetUrl,
                  maxZoom: _satellite
                      ? MapTiles.satelliteMaxZoom
                      : MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: tiles,
                  errorTileCallback: (tile, error, stackTrace) =>
                      debugPrint('Map tile failed: '
                          '${tile.coordinates} $error'),
                ),
                */
                // Gene - Nov, 11, 2026: Configure maxNativeZoom alongside maxZoom (22) so high-res Google tiles never drop out at close zoom.
                TileLayer(
                  urlTemplate:
                      _satellite ? MapTiles.satelliteUrl : MapTiles.streetUrl,
                  maxNativeZoom: _satellite
                      ? MapTiles.satelliteMaxNativeZoom
                      : MapTiles.streetMaxNativeZoom,
                  maxZoom: _satellite
                      ? MapTiles.satelliteMaxZoom
                      : MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: tiles,
                  errorTileCallback: (tile, error, stackTrace) =>
                      debugPrint('Map tile failed: '
                          '${tile.coordinates} $error'),
                ),
                MarkerLayer(
                  markers: [
                    for (final cluster in clusterSites(sites, zoom: _zoom))
                      Marker(
                        point: cluster.center,
                        width: 48,
                        height: 48,
                        child: cluster.isCluster
                            ? GestureDetector(
                                key: const Key('lcpNapCluster'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _zoomInto(cluster),
                                child: _ClusterPin(count: cluster.count),
                              )
                            : GestureDetector(
                                key: Key('lcpNapPin_${cluster.site.id}'),
                                onTap: () =>
                                    setState(() => _selected = cluster.site),
                                child: _Pin(
                                  selected: selected?.id == cluster.site.id,
                                  label: cluster.site.lcpNap,
                                  nap: cluster.site.nap,
                                  hue: lcpColorSeed(cluster.site.lcp),
                                ),
                              ),
                      ),
                  ],
                ),
                // The searched place, if any.
                if (_searchTarget != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        key: const Key('lcpNapSearchPin'),
                        point: _searchTarget!,
                        width: MapSearchPin.markerWidth,
                        height: MapSearchPin.markerHeight,
                        alignment: Alignment.topCenter,
                        child: MapSearchPin(label: _searchLabel ?? ''),
                      ),
                    ],
                  ),
                // Gene - Nov, 21, 2026: Render technician GPS position marker when auto-located on the Plant map.
                if (_userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        key: const Key('lcpNapUserLocationPin'),
                        point: _userLocation!,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x662563EB),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Top strip: place search, the unmapped-sites notice, then the
            // legend and base-layer controls. One column instead of fixed
            // offsets, so a large text setting pushes the controls down
            // rather than drawing them over the search bar and each other.
            Positioned(
              key: const Key('lcpNapMapOverlay'),
              top: 8,
              left: 8,
              right: 8,
              child: Column(
                key: _overlayKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MapSearchBar(
                    lookup: widget.placeLookup ?? nativePlaceLookup,
                    onLocated: _onPlaceLocated,
                  ),
                  // Sites the map cannot place, so they are visibly missing.
                  if (unmapped > 0) ...[
                    const SizedBox(height: 8),
                    /*
                    _UnmappedNotice(sites: unmappedSites),
                    */
                    // Gene - Oct 31, 2026: Made unmapped notice tappable to open unmapped sites sheet and map coordinates.
                    _UnmappedNotice(
                      sites: unmappedSites,
                      onTap: () =>
                          _showUnmappedSitesSheet(context, unmappedSites),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Legend on the left, base layer on the right; when the
                  // two no longer fit side by side the toggle wraps under.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PlantLegendButton(
                        expanded: _showLegend,
                        onToggle: () =>
                            setState(() => _showLegend = !_showLegend),
                      ),
                      _BaseLayerToggle(
                        satellite: _satellite,
                        onChanged: (v) => setState(() => _satellite = v),
                      ),
                    ],
                  ),
                  // Plant Legend Expanded Card
                  if (_showLegend) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _PlantLegendOverlay(
                        signals: widget.signals,
                        onClose: () => setState(() => _showLegend = false),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Right Float: Zoom Controls + Fit Bounds + My Location
            Positioned(
              right: 8,
              bottom: selected == null ? 8 : 220,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapZoomControl(
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                  ),
                  const SizedBox(height: 8),
                  if (sites.isNotEmpty) ...[
                    FloatingActionButton.small(
                      heroTag: 'lcpNapFitBounds',
                      backgroundColor:
                          Theme.of(context).cardTheme.color ?? Colors.white,
                      foregroundColor: AppTheme.primary,
                      tooltip: 'Fit all sites',
                      onPressed: () => _fitToSites(sites),
                      child: const Icon(Icons.fit_screen_rounded),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Gene - Nov, 23, 2026: Prefetch visible 1.5 km tile radius for offline field work.
                  FloatingActionButton.small(
                    key: const ValueKey('plant_cache_area_button'),
                    heroTag: 'lcpNapCacheArea',
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor:
                        Theme.of(context).cardTheme.color ?? Colors.white,
                    foregroundColor: AppTheme.primary,
                    tooltip: 'Cache area',
                    onPressed:
                        _isPrefetchingTiles ? null : _prefetchVisibleArea,
                    child: _isPrefetchingTiles
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : const Icon(
                            Icons.download_for_offline_outlined,
                            size: 20,
                          ),
                  ),
                  const SizedBox(height: 8),
                  // Gene - Nov, 21, 2026: Add My Location auto-locate button to center the Plant map on technician GPS coordinates.
                  FloatingActionButton.small(
                    key: const ValueKey('btnLcpNapMapMyLocation'),
                    heroTag: 'lcpNapMyLocation',
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor:
                        Theme.of(context).cardTheme.color ?? Colors.white,
                    foregroundColor: AppTheme.primary,
                    tooltip: 'My location',
                    onPressed: _isLocating ? null : _locateUser,
                    child: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ],
              ),
            ),

            // Gene - Nov, 12, 2026: Bottom-left floating Add LCP NAP pill on Map view; auto-hidden when a pin popup is active so it never collides with bottom-right zoom controls or the popup card.
            if (selected == null && widget.onCreateSite != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: LcpNapFloatingAddButton(
                  buttonKey: const ValueKey('btnCreateLcpNapMap'),
                  label: 'Add LCP NAP',
                  maxWidth: MediaQuery.sizeOf(context).width - 80,
                  onPressed: widget.onCreateSite!,
                ),
              ),

            // Bottom Selected Pin Popup Card
            if (selected != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: LcpNapPinPopup(
                  location: selected,
                  onClose: () => setState(() => _selected = null),
                  onOpenDetails: () => widget.onOpenDetails?.call(selected),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Pin extends StatelessWidget {
  final bool selected;
  final String label;
  final String nap;
  final double hue;

  const _Pin({
    required this.selected,
    required this.label,
    required this.nap,
    required this.hue,
  });

  /// The NAP number alone; the cabinet is conveyed by the pin's colour.
  String get _shortLabel {
    final digits = nap.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? '?' : int.parse(digits).toString();
  }

  @override
  Widget build(BuildContext context) {
    final colour = HSLColor.fromAHSL(1, hue, 0.62, 0.44).toColor();
    return Semantics(
      label: 'Site $label',
      button: true,
      child: Center(
        child: Container(
          width: selected ? 34 : 28,
          height: selected ? 34 : 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.white70,
              width: selected ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            _shortLabel,
            // Map furniture: fixed-size marker circle, cannot grow with the
            // type scale.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: Colors.white,
              fontSize: selected ? 13 : 11, // map furniture
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Several sites merged because they would overlap at this zoom.
class _ClusterPin extends StatelessWidget {
  final int count;

  const _ClusterPin({required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count sites, zoom in to separate',
      button: true,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            '$count',
            // Map furniture: fixed-size marker circle, cannot grow with the
            // type scale.
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14, // map furniture
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Street / Satellite switch. Satellite is what technicians use to find the
/// actual pole or wall a NAP box is mounted on.
class _BaseLayerToggle extends StatelessWidget {
  final bool satellite;
  final ValueChanged<bool> onChanged;

  const _BaseLayerToggle({required this.satellite, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).cardTheme.color ?? Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg(context, 'Street', Icons.map_rounded, !satellite,
                () => onChanged(false)),
            _seg(context, 'Satellite', Icons.satellite_alt_rounded, satellite,
                () => onChanged(true)),
          ],
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, String label, IconData icon, bool active,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 24, color: active ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.text.labelLarge!.copyWith(
                color: active ? Colors.white : AppTheme.secondaryInkOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
class _UnmappedNotice extends StatelessWidget {
  final List<LcpNapDto> sites;

  const _UnmappedNotice({required this.sites});

  /// Names the records so a technician can go fix their coordinates, rather
  /// than only being told a number is missing.
  String get _summary {
    final names = sites
        .take(3)
        .map((s) => s.lcpNap.trim().isEmpty ? 'record #${s.id}' : s.lcpNap)
        .join(', ');
    final rest = sites.length - 3;
    return rest > 0 ? '$names and $rest more' : names;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off_outlined,
              size: 20, color: Color(0xFF92400E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${sites.length} site${sites.length == 1 ? '' : 's'} '
              'without a GPS fix: $_summary',
              style: context.text.labelMedium!.copyWith(
                color: AppTheme.warningInkOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
*/
// Gene - Oct 31, 2026: Added optional onTap handler to _UnmappedNotice with tap feedback and chevron indicator.
class _UnmappedNotice extends StatelessWidget {
  final List<LcpNapDto> sites;
  final VoidCallback? onTap;

  const _UnmappedNotice({
    required this.sites,
    this.onTap,
  });

  /// Names the records so a technician can go fix their coordinates, rather
  /// than only being told a number is missing.
  String get _summary {
    final names = sites
        .take(3)
        .map((s) => s.lcpNap.trim().isEmpty ? 'record #${s.id}' : s.lcpNap)
        .join(', ');
    final rest = sites.length - 3;
    return rest > 0 ? '$names and $rest more' : names;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.warningSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.location_off_outlined,
                  size: 20, color: Color(0xFF92400E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sites.length} site${sites.length == 1 ? '' : 's'} '
                  'without a GPS fix: $_summary. Tap to map.',
                  style: context.text.labelMedium!.copyWith(
                    color: AppTheme.warningInkOf(context),
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF92400E),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zoom in / out buttons on the map.
class _MapZoomControl extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _MapZoomControl({
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).cardTheme.color ?? Colors.white;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : AppTheme.darkSlate;

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onZoomIn,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.add_rounded, size: 20, color: iconColor),
            ),
          ),
          Container(
            height: 1,
            width: 28,
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
          InkWell(
            onTap: onZoomOut,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.remove_rounded, size: 20, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Button to toggle the Plant Color Legend
class _PlantLegendButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;

  const _PlantLegendButton({
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).cardTheme.color ?? Colors.white,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.palette_outlined,
                  size: 24, color: AppTheme.primary),
              const SizedBox(width: 5),
              Text(
                'Legend',
                style: context.text.labelLarge!.copyWith(
                  color: expanded ? AppTheme.brandInkOf(context) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown card showing LCP Cabinet color keys and pin explanation
class _PlantLegendOverlay extends StatelessWidget {
  final LcpNapSignals signals;
  final VoidCallback onClose;

  const _PlantLegendOverlay({
    required this.signals,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final cabinets =
            signals.lcpCabinetList.value.where((c) => c != 'All').toList();

        return Card(
          elevation: 6,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'LCP Cabinet Colors',
                        style: context.text.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(12),
                      child: const Icon(Icons.close_rounded,
                          size: 24, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Pin numbers show NAP box ID. Outer ring hue identifies Cabinet:',
                  style: context.text.labelSmall,
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cabinets.length,
                    itemBuilder: (context, index) {
                      final cab = cabinets[index];
                      final hue = lcpColorSeed(cab);
                      final color =
                          HSLColor.fromAHSL(1, hue, 0.62, 0.44).toColor();

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cab,
                                style: context.text.labelMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
