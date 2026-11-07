// Gene - Oct 31, 2026: Interactive Location Mapping sheet and Map Pin Picker for LCP NAP locations.
// Allows technicians to acquire device GPS coordinates ("Use Current Location") or visually drop/drag
// a pin on the map ("Pin on Map") to capture coordinates and reverse-geocode address metadata.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../models/lcp_nap_model.dart';
import '../services/map_clustering.dart';
import '../services/map_tiles.dart';
import '../signals/lcp_nap_signals.dart';
import 'map_search_bar.dart';

/// Modal bottom sheet allowing technicians to map an LCP NAP location by
/// clicking current GPS location or pinning onto the interactive map.
class LcpNapLocationPickerSheet extends StatefulWidget {
  final LcpNapDto location;
  final LcpNapSignals signals;
  final TileProvider? tileProvider;
  final LocationService? locationService;
  final PlaceLookup? placeLookup;
  final Future<List<geo.Placemark>> Function(double lat, double lng)?
      reverseGeocodeForTesting;

  const LcpNapLocationPickerSheet({
    super.key,
    required this.location,
    required this.signals,
    this.tileProvider,
    this.locationService,
    this.placeLookup,
    this.reverseGeocodeForTesting,
  });

  @override
  State<LcpNapLocationPickerSheet> createState() =>
      _LcpNapLocationPickerSheetState();
}

class _LcpNapLocationPickerSheetState extends State<LcpNapLocationPickerSheet> {
  late final TextEditingController _coordinatesController;
  late final TextEditingController _streetController;
  late final TextEditingController _barangayController;
  late final TextEditingController _cityController;
  late final TextEditingController _regionController;

  bool _isLocating = false;
  bool _isSaving = false;
  String? _errorMessage;
  TileProvider? _tiles;

  @override
  void initState() {
    super.initState();
    _coordinatesController =
        TextEditingController(text: widget.location.coordinates ?? '');
    _streetController =
        TextEditingController(text: widget.location.street ?? '');
    _barangayController =
        TextEditingController(text: widget.location.barangay ?? '');
    _cityController = TextEditingController(text: widget.location.city ?? '');
    _regionController =
        TextEditingController(text: widget.location.region ?? '');

    _tiles = widget.tileProvider;
    if (_tiles == null) _loadTiles();
  }

  Future<void> _loadTiles() async {
    try {
      final p = await MapTiles.provider();
      if (mounted) setState(() => _tiles = p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _coordinatesController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  LocationService get _locationService =>
      widget.locationService ?? LocationService.instance;

  /// Helper to parse coordinates from the text controller
  LatLng? get _parsedLatLng {
    final raw = _coordinatesController.text.trim();
    if (raw.isEmpty) return null;
    final parts = raw
        .replaceAll(
            RegExp(r'lat:|latitude:|lng:|longitude:|lon:',
                caseSensitive: false),
            '')
        .split(RegExp(r'[,;\s]+'))
        .map((p) => double.tryParse(p.trim()))
        .toList();
    if (parts.length != 2) return null;
    final lat = parts[0];
    final lng = parts[1];
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLng(lat, lng);
  }

  /// Query reverse-geocoding for the selected coordinates and prefill address fields
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final List<geo.Placemark> placemarks;
      if (widget.reverseGeocodeForTesting != null) {
        placemarks = await widget.reverseGeocodeForTesting!(lat, lng);
      } else {
        placemarks = await geo.Geocoding().placemarkFromCoordinates(lat, lng);
      }

      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        setState(() {
          if (_streetController.text.trim().isEmpty) {
            final st = p.street ?? p.thoroughfare;
            if (st != null && st.isNotEmpty) _streetController.text = st;
          }
          if (_barangayController.text.trim().isEmpty) {
            final bg = p.subLocality;
            if (bg != null && bg.isNotEmpty) _barangayController.text = bg;
          }
          if (_cityController.text.trim().isEmpty) {
            final ct = p.locality ?? p.subAdministrativeArea;
            if (ct != null && ct.isNotEmpty) _cityController.text = ct;
          }
          if (_regionController.text.trim().isEmpty) {
            final rg = p.administrativeArea;
            if (rg != null && rg.isNotEmpty) _regionController.text = rg;
          }
        });
      }
    } catch (_) {
      // Graceful offline fallback
    }
  }

  /// Click 1: Acquire device GPS coordinates
  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;

      if (pos != null) {
        final formatted =
            '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
        _coordinatesController.text = formatted;
        await _reverseGeocode(pos.latitude, pos.longitude);
      } else {
        setState(() {
          _errorMessage =
              'Could not acquire current GPS location. Please check location permissions.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'GPS acquisition error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  /// Click 2: Pin on map picker
  Future<void> _openMapPinPicker() async {
    final current = _parsedLatLng ?? widget.location.latLng;

    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LcpNapMapPickerScreen(
          location: widget.location,
          initialLatLng: current,
          tileProvider: _tiles,
          placeLookup: widget.placeLookup,
          locationService: widget.locationService,
        ),
      ),
    );

    if (picked != null && mounted) {
      final formatted =
          '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}';
      setState(() {
        _coordinatesController.text = formatted;
      });
      await _reverseGeocode(picked.latitude, picked.longitude);
    }
  }

  /// Save and update location
  Future<void> _saveLocation() async {
    final parsed = _parsedLatLng;
    if (parsed == null) {
      setState(() {
        _errorMessage =
            'Please enter or pick valid GPS coordinates (e.g. 14.586200, 121.061800).';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final coordinates =
        '${parsed.latitude.toStringAsFixed(6)}, ${parsed.longitude.toStringAsFixed(6)}';

    final success = await widget.signals.updateLocationCoordinates(
      locationId: widget.location.id,
      location: widget.location,
      coordinates: coordinates,
      street: _streetController.text.trim().isNotEmpty
          ? _streetController.text.trim()
          : null,
      barangay: _barangayController.text.trim().isNotEmpty
          ? _barangayController.text.trim()
          : null,
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      region: _regionController.text.trim().isNotEmpty
          ? _regionController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = widget.signals.errorMessage.value ??
            'Failed to update location coordinates. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom > 0
        ? MediaQuery.of(context).viewInsets.bottom
        : MediaQuery.of(context).padding.bottom;
    final currentLatLng = _parsedLatLng;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                        'Map LCP NAP Location',
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
                      _isSaving ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                if (_errorMessage != null) ...[
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
                      _errorMessage!,
                      style: context.text.bodySmall!
                          .copyWith(color: AppTheme.danger),
                    ),
                  ),
                ],

                // Action Row: Current Location GPS and Pin on Map
                Text(
                  'ACQUIRE LOCATION COORDINATES',
                  style: context.text.labelSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Button 1: Use Current Location (GPS)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('btnCurrentLocation'),
                        onPressed: _isLocating || _isSaving
                            ? null
                            : _useCurrentLocation,
                        icon: _isLocating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primary,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(
                          _isLocating ? 'Locating...' : 'Current GPS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Button 2: Pin to Map
                    Expanded(
                      child: ElevatedButton.icon(
                        key: const ValueKey('btnPinOnMap'),
                        onPressed: _isSaving ? null : _openMapPinPicker,
                        icon: const Icon(Icons.pin_drop_rounded, size: 18),
                        label: const Text(
                          'Pin on Map',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Mini preview map if coordinates are valid
                if (currentLatLng != null && _tiles != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 120,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: currentLatLng,
                          initialZoom: 16,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: MapTiles.streetUrl,
                            maxZoom: MapTiles.streetMaxZoom,
                            userAgentPackageName: MapTiles.userAgentPackageName,
                            tileProvider: _tiles,
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: currentLatLng,
                                width: 32,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: HSLColor.fromAHSL(
                                      1,
                                      lcpColorSeed(widget.location.lcp),
                                      0.62,
                                      0.44,
                                    ).toColor(),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.location.nap
                                          .replaceAll(RegExp(r'\D'), ''),
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
                  ),
                  const SizedBox(height: 14),
                ],

                // Coordinates Input Field
                TextField(
                  key: const ValueKey('inputCoordinates'),
                  controller: _coordinatesController,
                  decoration: InputDecoration(
                    labelText: 'WGS84 Coordinates (Lat, Long)',
                    hintText: 'e.g. 14.586200, 121.061800',
                    prefixIcon: const Icon(Icons.gps_fixed_rounded, size: 20),
                    suffixIcon: _coordinatesController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () =>
                                setState(() => _coordinatesController.clear()),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // Address Metadata Header
                Text(
                  'ADDRESS & LOCATION DATA',
                  style: context.text.labelSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ),
                const SizedBox(height: 8),

                // Street
                TextField(
                  key: const ValueKey('inputStreet'),
                  controller: _streetController,
                  decoration: InputDecoration(
                    labelText: 'Street / Landmark',
                    prefixIcon: const Icon(Icons.home_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Barangay & City in row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('inputBarangay'),
                        controller: _barangayController,
                        decoration: InputDecoration(
                          labelText: 'Barangay',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('inputCity'),
                        controller: _cityController,
                        decoration: InputDecoration(
                          labelText: 'City / Municipality',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Region
                TextField(
                  key: const ValueKey('inputRegion'),
                  controller: _regionController,
                  decoration: InputDecoration(
                    labelText: 'Region / Province',
                    prefixIcon: const Icon(Icons.map_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
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
                key: const ValueKey('btnSaveLocation'),
                onPressed: _isSaving ? null : _saveLocation,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(_isSaving
                    ? 'Saving Location...'
                    : 'Save & Update Location'),
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

/// Fullscreen interactive Map Pin Picker allowing technician to pinpoint the
/// exact location of an LCP NAP by tapping, panning, or searching places.
class LcpNapMapPickerScreen extends StatefulWidget {
  final LcpNapDto location;
  final LatLng? initialLatLng;
  final TileProvider? tileProvider;
  final PlaceLookup? placeLookup;
  final LocationService? locationService;

  const LcpNapMapPickerScreen({
    super.key,
    required this.location,
    this.initialLatLng,
    this.tileProvider,
    this.placeLookup,
    this.locationService,
  });

  @override
  State<LcpNapMapPickerScreen> createState() => _LcpNapMapPickerScreenState();
}

class _LcpNapMapPickerScreenState extends State<LcpNapMapPickerScreen> {
  final MapController _mapController = MapController();
  TileProvider? _tiles;
  late LatLng _pinLocation;
  bool _satellite = false;
  bool _isLocating = false;

  static const LatLng _fallbackCenter =
      LatLng(LocationService.fallbackLat, LocationService.fallbackLng);

  @override
  void initState() {
    super.initState();
    _pinLocation =
        widget.initialLatLng ?? widget.location.latLng ?? _fallbackCenter;
    _tiles = widget.tileProvider;
    if (_tiles == null) _loadTiles();
  }

  Future<void> _loadTiles() async {
    try {
      final p = await MapTiles.provider();
      if (mounted) setState(() => _tiles = p);
    } catch (_) {}
  }

  LocationService get _locationService =>
      widget.locationService ?? LocationService.instance;

  Future<void> _centerOnGps() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() => _pinLocation = target);
        _mapController.move(target, 17);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onPlaceLocated(LatLng target, String query) {
    setState(() {
      _pinLocation = target;
    });
    _mapController.move(target, 17);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hue = lcpColorSeed(widget.location.lcp);
    final cabinetColor = HSLColor.fromAHSL(1, hue, 0.62, 0.44).toColor();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pin Location on Map'),
            Text(
              widget.location.lcpNap,
              style: context.text.labelSmall!.copyWith(
                color: isDark ? AppTheme.textMuted : AppTheme.darkSlate,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _satellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
              color: AppTheme.primary,
            ),
            tooltip:
                _satellite ? 'Switch to Street Map' : 'Switch to Satellite',
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pinLocation,
              initialZoom: 16.5,
              onTap: (_, point) {
                setState(() => _pinLocation = point);
              },
            ),
            children: [
              if (_tiles != null)
                TileLayer(
                  urlTemplate:
                      _satellite ? MapTiles.satelliteUrl : MapTiles.streetUrl,
                  maxZoom: _satellite
                      ? MapTiles.satelliteMaxZoom
                      : MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: _tiles,
                ),
              // Marker for the pinned location
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pinLocation,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cabinetColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          width: 4,
                          height: 6,
                          color: cabinetColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Search Bar Overlay at Top
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: MapSearchBar(
              lookup: widget.placeLookup ?? nativePlaceLookup,
              onLocated: _onPlaceLocated,
            ),
          ),

          // GPS Centering Floating Button
          Positioned(
            right: 16,
            bottom: 125,
            child: FloatingActionButton.small(
              key: const ValueKey('fabCenterGps'),
              heroTag: 'fabMapPickerGps',
              backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
              foregroundColor: AppTheme.primary,
              tooltip: 'Center on My GPS Location',
              onPressed: _isLocating ? null : _centerOnGps,
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
          ),

          // Bottom Confirmation Card
          Positioned(
            left: 14,
            right: 14,
            bottom: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pin_drop_rounded,
                            color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Coordinates',
                                style: context.text.labelSmall!.copyWith(
                                  color: AppTheme.secondaryInkOf(context),
                                ),
                              ),
                              Text(
                                '${_pinLocation.latitude.toStringAsFixed(6)}, ${_pinLocation.longitude.toStringAsFixed(6)}',
                                style: context.text.titleSmall!.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        key: const ValueKey('btnConfirmPinLocation'),
                        onPressed: () =>
                            Navigator.of(context).pop(_pinLocation),
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Confirm Pin Location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
