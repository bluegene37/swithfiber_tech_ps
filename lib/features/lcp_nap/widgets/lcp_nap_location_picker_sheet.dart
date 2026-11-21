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
// Gene - Nov, 11, 2026: Imported AuthSignals to attach signed-in technician identity (ModifiedBy / UserEmail) when creating or editing LCP NAP locations.
import '../../auth/signals/auth_signals.dart';
import '../models/lcp_nap_model.dart';
import '../services/map_clustering.dart';
import '../services/map_tiles.dart';
import '../signals/lcp_nap_signals.dart';
// Gene - Nov, 12, 2026: Imported searchable LCP Cabinet bottom-sheet picker to replace the 241-item PopupMenuButton.
import 'lcp_cabinet_picker_sheet.dart';
import 'map_search_bar.dart';

/// Modal bottom sheet allowing technicians to map an LCP NAP location,
/// edit site details (LCP, NAP, PortTotal, address, GPS), or create a new LCP NAP site.
class LcpNapLocationPickerSheet extends StatefulWidget {
  final LcpNapDto location;
  final LcpNapSignals signals;
  final TileProvider? tileProvider;
  final LocationService? locationService;
  final PlaceLookup? placeLookup;
  final Future<List<geo.Placemark>> Function(double lat, double lng)?
      reverseGeocodeForTesting;
  // Gene - Nov, 11, 2026: Added isCreateMode, allowEmptyCoordinates, custom sheetTitle, and onCreated callback to support creating new LCP NAP locations and editing site details.
  final bool isCreateMode;
  final bool allowEmptyCoordinates;
  final String? sheetTitle;
  final void Function(LcpNapDto created)? onCreated;

  /*
  const LcpNapLocationPickerSheet({
    super.key,
    required this.location,
    required this.signals,
    this.tileProvider,
    this.locationService,
    this.placeLookup,
    this.reverseGeocodeForTesting,
  });
  */
  const LcpNapLocationPickerSheet({
    super.key,
    required this.location,
    required this.signals,
    this.tileProvider,
    this.locationService,
    this.placeLookup,
    this.reverseGeocodeForTesting,
    this.isCreateMode = false,
    this.allowEmptyCoordinates = false,
    this.sheetTitle,
    this.onCreated,
  });

  /// Convenience constructor for creating a new LCP NAP location.
  factory LcpNapLocationPickerSheet.create({
    Key? key,
    required LcpNapSignals signals,
    String initialLcp = '',
    String initialNap = 'NAP 001',
    int initialPortTotal = 16,
    String? initialCity,
    String? initialRegion = 'Rizal',
    TileProvider? tileProvider,
    LocationService? locationService,
    PlaceLookup? placeLookup,
    Future<List<geo.Placemark>> Function(double lat, double lng)?
        reverseGeocodeForTesting,
    void Function(LcpNapDto created)? onCreated,
  }) {
    final cleanLcp = initialLcp.trim();
    final cleanNap = initialNap.trim();
    final combined =
        cleanLcp.isNotEmpty ? '$cleanLcp $cleanNap'.trim() : cleanNap;
    return LcpNapLocationPickerSheet(
      key: key,
      location: LcpNapDto(
        id: 0,
        lcp: cleanLcp,
        nap: cleanNap,
        lcpNap: combined,
        portTotal: initialPortTotal,
        city: initialCity,
        region: initialRegion,
      ),
      signals: signals,
      tileProvider: tileProvider,
      locationService: locationService,
      placeLookup: placeLookup,
      reverseGeocodeForTesting: reverseGeocodeForTesting,
      isCreateMode: true,
      allowEmptyCoordinates: true,
      sheetTitle: 'Create LCP NAP Location',
      onCreated: onCreated,
    );
  }

  @override
  State<LcpNapLocationPickerSheet> createState() =>
      _LcpNapLocationPickerSheetState();
}

class _LcpNapLocationPickerSheetState extends State<LcpNapLocationPickerSheet> {
  // Gene - Nov, 11, 2026: Added controllers for LCP, NAP, LCPNAP label, and PortTotal capacity.
  late final TextEditingController _lcpController;
  late final TextEditingController _napController;
  late final TextEditingController _lcpNapController;
  late final TextEditingController _portTotalController;
  late final TextEditingController _coordinatesController;
  late final TextEditingController _streetController;
  late final TextEditingController _barangayController;
  late final TextEditingController _cityController;
  late final TextEditingController _regionController;

  bool _lcpNapManuallyEdited = false;
  bool _isLocating = false;
  bool _isSaving = false;
  String? _errorMessage;
  TileProvider? _tiles;
  // Gene - Nov, 21, 2026: Track preview MapController & readiness so auto-locate, pin picker, and typed coordinates immediately move the mini preview map camera.
  final MapController _previewMapController = MapController();
  bool _previewMapReady = false;
  LatLng? _pendingPreviewCenter;
  LatLng? _lastPreviewCenter;

  static const List<int> _standardPortCounts = [8, 16, 24, 32];
  static const List<String> _standardNaps = [
    'NAP 001',
    'NAP 002',
    'NAP 003',
    'NAP 004',
    'NAP 005',
    'NAP 006',
    'NAP 007',
    'NAP 008',
    'NAP 009',
    'NAP 010',
    'NAP 011',
    'NAP 012',
    'NAP 013',
    'NAP 014',
    'NAP 015',
    'NAP 016',
  ];

  @override
  void initState() {
    super.initState();
    _lcpController = TextEditingController(text: widget.location.lcp);
    _napController = TextEditingController(text: widget.location.nap);
    _lcpNapController = TextEditingController(text: widget.location.lcpNap);
    _portTotalController =
        TextEditingController(text: widget.location.portTotal.toString());
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

  /*
  @override
  void dispose() {
    _lcpController.dispose();
    _napController.dispose();
    _lcpNapController.dispose();
    _portTotalController.dispose();
    _coordinatesController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    super.dispose();
  }
  */
  // Gene - Nov, 21, 2026: Dispose the preview MapController alongside form text controllers.
  @override
  void dispose() {
    _previewMapController.dispose();
    _lcpController.dispose();
    _napController.dispose();
    _lcpNapController.dispose();
    _portTotalController.dispose();
    _coordinatesController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _syncLcpNapLabel() {
    if (_lcpNapManuallyEdited) return;
    final lcp = _lcpController.text.trim();
    final nap = _napController.text.trim();
    if (lcp.isNotEmpty && nap.isNotEmpty) {
      _lcpNapController.text = '$lcp $nap';
    } else if (lcp.isNotEmpty) {
      _lcpNapController.text = lcp;
    } else {
      _lcpNapController.text = nap;
    }
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

  // Gene - Nov, 21, 2026: Move mini preview map camera reliably once FlutterMap is ready (or queue until onMapReady fires).
  void _movePreviewMap(LatLng target) {
    _lastPreviewCenter = target;
    if (_previewMapReady) {
      try {
        _previewMapController.move(target, 16);
      } catch (_) {
        _previewMapReady = false;
        _pendingPreviewCenter = target;
      }
    } else {
      _pendingPreviewCenter = target;
    }
  }

  void _onPreviewMapReady() {
    _previewMapReady = true;
    final pending = _pendingPreviewCenter;
    if (pending != null) {
      _pendingPreviewCenter = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _previewMapController.move(pending, 16);
        } catch (_) {}
      });
    }
  }

  void _resetPreviewMapState() {
    _previewMapReady = false;
    _pendingPreviewCenter = null;
    _lastPreviewCenter = null;
  }

  /// Click 1: Acquire device GPS coordinates
  /*
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
  */
  // Gene - Nov, 21, 2026: Update coordinates field, pin marker, and mini preview map camera immediately when Current GPS succeeds.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;

      if (pos != null) {
        final target = LatLng(pos.latitude, pos.longitude);
        final formatted =
            '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
        setState(() {
          _coordinatesController.text = formatted;
        });
        _movePreviewMap(target);
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
    // Gene - Nov, 11, 2026: Pass current edited LCP/NAP values into the Map Pin Picker preview.
    final previewLocation = widget.location.copyWith(
      lcp: _lcpController.text.trim().isNotEmpty
          ? _lcpController.text.trim()
          : widget.location.lcp,
      nap: _napController.text.trim().isNotEmpty
          ? _napController.text.trim()
          : widget.location.nap,
      lcpNap: _lcpNapController.text.trim().isNotEmpty
          ? _lcpNapController.text.trim()
          : widget.location.lcpNap,
    );

    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LcpNapMapPickerScreen(
          /*
          location: widget.location,
          */
          location: previewLocation,
          initialLatLng: current,
          tileProvider: _tiles,
          placeLookup: widget.placeLookup,
          locationService: widget.locationService,
        ),
      ),
    );

    /*
    if (picked != null && mounted) {
      final formatted =
          '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}';
      setState(() {
        _coordinatesController.text = formatted;
      });
      await _reverseGeocode(picked.latitude, picked.longitude);
    }
    */
    // Gene - Nov, 21, 2026: Also move the mini preview map camera when returning with a picked pin coordinate.
    if (picked != null && mounted) {
      final formatted =
          '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}';
      setState(() {
        _coordinatesController.text = formatted;
      });
      _movePreviewMap(picked);
      await _reverseGeocode(picked.latitude, picked.longitude);
    }
  }

  // Gene - Nov, 11, 2026: Suggest next sequential NAP number for a given LCP cabinet.
  String _suggestNextNapForLcp(String lcpName) {
    final normalized = lcpName.trim().toLowerCase();
    if (normalized.isEmpty) return 'NAP 001';
    final existing = widget.signals.allLocations.value
        .where((loc) => loc.lcp.trim().toLowerCase() == normalized)
        .toList();
    int maxNum = 0;
    for (final loc in existing) {
      final match = RegExp(r'(\d+)').firstMatch(loc.nap);
      if (match != null) {
        final val = int.tryParse(match.group(1)!) ?? 0;
        if (val > maxNum) maxNum = val;
      }
    }
    final nextNum = maxNum + 1;
    return 'NAP ${nextNum.toString().padLeft(3, '0')}';
  }

  /// Save and update or create location
  /*
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
  */
  // Gene - Nov, 11, 2026: Enhanced _saveLocation to support both creating new LCP NAP locations and editing site details (LCP, NAP, LCPNAP, PortTotal, address, and coordinates).
  Future<void> _saveLocation() async {
    final parsed = _parsedLatLng;
    final rawCoords = _coordinatesController.text.trim();

    if ((!widget.isCreateMode &&
            !widget.allowEmptyCoordinates &&
            parsed == null) ||
        (rawCoords.isNotEmpty && parsed == null)) {
      setState(() {
        _errorMessage =
            'Please enter or pick valid GPS coordinates (e.g. 14.586200, 121.061800).';
      });
      return;
    }

    final lcp = _lcpController.text.trim();
    final nap = _napController.text.trim();
    if (lcp.isEmpty || nap.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both LCP Cabinet and NAP Box names.';
      });
      return;
    }

    final portTotal = int.tryParse(_portTotalController.text.trim());
    if (portTotal == null || portTotal <= 0 || portTotal > 128) {
      setState(() {
        _errorMessage =
            'Please enter a valid port capacity (e.g. 8, 16, 24, or 32).';
      });
      return;
    }

    final lcpNap = _lcpNapController.text.trim().isNotEmpty
        ? _lcpNapController.text.trim()
        : '$lcp $nap';

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final coordinates = parsed != null
        ? '${parsed.latitude.toStringAsFixed(6)}, ${parsed.longitude.toStringAsFixed(6)}'
        : '';

    final user = AuthSignals.instance.currentUser.value;
    final modifiedBy = user != null
        ? (user.fullName.isNotEmpty ? user.fullName : user.username)
        : widget.location.modifiedBy;
    final userEmail = user != null && user.email.isNotEmpty
        ? user.email
        : widget.location.userEmail;

    final street = _streetController.text.trim().isNotEmpty
        ? _streetController.text.trim()
        : null;
    final barangay = _barangayController.text.trim().isNotEmpty
        ? _barangayController.text.trim()
        : null;
    final city = _cityController.text.trim().isNotEmpty
        ? _cityController.text.trim()
        : null;
    final region = _regionController.text.trim().isNotEmpty
        ? _regionController.text.trim()
        : null;

    if (widget.isCreateMode) {
      final created = await widget.signals.createLocation(
        lcp: lcp,
        nap: nap,
        lcpNap: lcpNap,
        portTotal: portTotal,
        coordinates: coordinates.isNotEmpty ? coordinates : null,
        street: street,
        barangay: barangay,
        city: city,
        region: region,
        modifiedBy: modifiedBy,
        userEmail: userEmail,
      );

      if (!mounted) return;

      if (created != null) {
        widget.onCreated?.call(created);
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = widget.signals.errorMessage.value ??
              'Failed to create LCP NAP location. Please try again.';
        });
      }
      return;
    }

    final success = await widget.signals.updateLocationCoordinates(
      locationId: widget.location.id,
      location: widget.location,
      coordinates: coordinates,
      lcp: lcp,
      nap: nap,
      lcpNap: lcpNap,
      portTotal: portTotal,
      street: street,
      barangay: barangay,
      city: city,
      region: region,
      modifiedBy: modifiedBy,
      userEmail: userEmail,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = widget.signals.errorMessage.value ??
            'Failed to update location details. Please try again.';
      });
    }
  }

  // Gene - Nov, 11, 2026: Built Site Identification & Capacity form section (LCP, NAP, LCPNAP, PortTotal + quick pickers).
  Widget _buildSiteIdentitySection(BuildContext context, bool isDark) {
    final existingLcps = widget.signals.lcpCabinetList.value
        .where((e) => e != 'All' && e.trim().isNotEmpty)
        .toList();
    // Gene - Nov, 12, 2026: Build NAP count lookup per cabinet for the searchable cabinet picker sheet.
    final groupedLcps = widget.signals.groupedByLcp.value;
    final napCounts = <String, int>{
      for (final entry in groupedLcps.entries) entry.key: entry.value.length,
    };
    final selectedPorts = int.tryParse(_portTotalController.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SITE IDENTIFICATION & CAPACITY',
          style: context.text.labelSmall!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppTheme.secondaryInkOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: TextField(
                key: const ValueKey('inputLcp'),
                controller: _lcpController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'LCP Cabinet *',
                  hintText: 'e.g. LCP 001 - ANG',
                  prefixIcon: const Icon(Icons.dns_outlined, size: 19),
                  /*
                  suffixIcon: existingLcps.isNotEmpty
                      ? PopupMenuButton<String>(
                          key: const ValueKey('btnPickExistingLcp'),
                          tooltip: 'Pick existing LCP Cabinet',
                          icon: const Icon(Icons.arrow_drop_down_rounded),
                          onSelected: (selectedLcp) {
                            setState(() {
                              _lcpController.text = selectedLcp;
                              if (widget.isCreateMode) {
                                _napController.text =
                                    _suggestNextNapForLcp(selectedLcp);
                              }
                              _syncLcpNapLabel();
                              // Pre-fill city/region from existing cabinet member if blank
                              final sample = widget.signals.allLocations.value
                                  .where((loc) => loc.lcp == selectedLcp)
                                  .firstOrNull;
                              if (sample != null) {
                                if (_cityController.text.trim().isEmpty &&
                                    (sample.city ?? '').isNotEmpty) {
                                  _cityController.text = sample.city!;
                                }
                                if (_regionController.text.trim().isEmpty &&
                                    (sample.region ?? '').isNotEmpty) {
                                  _regionController.text = sample.region!;
                                }
                              }
                            });
                          },
                          itemBuilder: (ctx) => existingLcps
                              .map(
                                (lcp) => PopupMenuItem<String>(
                                  value: lcp,
                                  child: Text(lcp),
                                ),
                              )
                              .toList(),
                        )
                      : null,
                  */
                  // Gene - Nov, 12, 2026: Replaced unwieldy 241-item PopupMenuButton with searchable 52dp-row bottom-sheet picker.
                  suffixIcon: existingLcps.isNotEmpty
                      ? IconButton(
                          key: const ValueKey('btnPickExistingLcp'),
                          tooltip: 'Search & pick LCP Cabinet',
                          constraints: const BoxConstraints(
                            minWidth: AppTheme.minTarget,
                            minHeight: AppTheme.minTarget,
                          ),
                          icon: const Icon(Icons.arrow_drop_down_rounded),
                          onPressed: () async {
                            FocusScope.of(context).unfocus();
                            final selectedLcp = await showLcpCabinetPickerSheet(
                              context: context,
                              cabinets: existingLcps,
                              napCounts: napCounts,
                              currentSelected: _lcpController.text.trim(),
                              allowCustomCabinet: true,
                              title: 'Select LCP Cabinet',
                              subtitle:
                                  'Search existing cabinets or enter a new cabinet code:',
                            );
                            if (selectedLcp == null || !mounted) return;
                            setState(() {
                              _lcpController.text = selectedLcp;
                              if (widget.isCreateMode) {
                                _napController.text =
                                    _suggestNextNapForLcp(selectedLcp);
                              }
                              _syncLcpNapLabel();
                              final sample = widget.signals.allLocations.value
                                  .where((loc) => loc.lcp == selectedLcp)
                                  .firstOrNull;
                              if (sample != null) {
                                if (_cityController.text.trim().isEmpty &&
                                    (sample.city ?? '').isNotEmpty) {
                                  _cityController.text = sample.city!;
                                }
                                if (_regionController.text.trim().isEmpty &&
                                    (sample.region ?? '').isNotEmpty) {
                                  _regionController.text = sample.region!;
                                }
                              }
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) {
                  setState(() {
                    _syncLcpNapLabel();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: TextField(
                key: const ValueKey('inputNap'),
                controller: _napController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'NAP Box *',
                  hintText: 'e.g. NAP 001',
                  prefixIcon:
                      const Icon(Icons.settings_input_hdmi_outlined, size: 19),
                  suffixIcon: PopupMenuButton<String>(
                    key: const ValueKey('btnPickStandardNap'),
                    tooltip: 'Pick NAP number',
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    onSelected: (selectedNap) {
                      setState(() {
                        _napController.text = selectedNap;
                        _syncLcpNapLabel();
                      });
                    },
                    itemBuilder: (ctx) => _standardNaps
                        .map(
                          (nap) => PopupMenuItem<String>(
                            value: nap,
                            child: Text(nap),
                          ),
                        )
                        .toList(),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) {
                  setState(() {
                    _syncLcpNapLabel();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: TextField(
                key: const ValueKey('inputLcpNap'),
                controller: _lcpNapController,
                decoration: InputDecoration(
                  labelText: 'Site Code (LCPNAP)',
                  hintText: 'Auto-generated from LCP + NAP',
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 19),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (val) {
                  _lcpNapManuallyEdited = val.trim().isNotEmpty;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: TextField(
                key: const ValueKey('inputPortTotal'),
                controller: _portTotalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Total Ports *',
                  hintText: '16',
                  prefixIcon: const Icon(Icons.hub_outlined, size: 19),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Quick Port Capacity:',
              style: context.text.labelSmall!.copyWith(
                color: AppTheme.secondaryInkOf(context),
              ),
            ),
            /*
            for (final count in _standardPortCounts)
              ChoiceChip(
                key: ValueKey('chipPort_$count'),
                label: Text('$count Ports'),
                selected: selectedPorts == count,
                onSelected: (_) {
                  setState(() {
                    _portTotalController.text = count.toString();
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
            */
            // Gene - Nov, 12, 2026: Removed prohibited VisualDensity.compact and ensured 48dp minimum gloved-thumb target per DESIGN.md.
            for (final count in _standardPortCounts)
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: AppTheme.minTarget),
                child: ChoiceChip(
                  key: ValueKey('chipPort_$count'),
                  label: Text('$count Ports'),
                  selected: selectedPorts == count,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    setState(() {
                      _portTotalController.text = count.toString();
                    });
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Gene - Nov, 11, 2026: Extracted GPS & Map Coordinate acquisition section so it can be ordered contextually for Create/Edit vs Map modes.
  Widget _buildCoordinatesSection(
    BuildContext context,
    LatLng? currentLatLng,
  ) {
    final activeLcp = _lcpController.text.trim().isNotEmpty
        ? _lcpController.text.trim()
        : widget.location.lcp;
    final activeNap = _napController.text.trim().isNotEmpty
        ? _napController.text.trim()
        : widget.location.nap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                onPressed:
                    _isLocating || _isSaving ? null : _useCurrentLocation,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mini preview map if coordinates are valid
        /*
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
                  /*
                  TileLayer(
                    urlTemplate: MapTiles.streetUrl,
                    maxZoom: MapTiles.streetMaxZoom,
                    userAgentPackageName: MapTiles.userAgentPackageName,
                    tileProvider: _tiles,
                  ),
                  */
                  // Gene - Nov, 11, 2026: Configure maxNativeZoom alongside maxZoom on mini-map TileLayer for high-detail street tiles.
                  TileLayer(
                    urlTemplate: MapTiles.streetUrl,
                    maxNativeZoom: MapTiles.streetMaxNativeZoom,
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
                              lcpColorSeed(activeLcp),
                              0.62,
                              0.44,
                            ).toColor(),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
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
                              activeNap.replaceAll(RegExp(r'\D'), ''),
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
            labelText: widget.isCreateMode || widget.allowEmptyCoordinates
                ? 'WGS84 Coordinates (Lat, Long — optional)'
                : 'WGS84 Coordinates (Lat, Long)',
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
        */
        // Gene - Nov, 21, 2026: Attach _previewMapController so auto-locate & edits move the mini preview map camera, and make the mini preview map tappable to open LcpNapMapPickerScreen.
        if (currentLatLng != null && _tiles != null) ...[
          GestureDetector(
            key: const ValueKey('btnPreviewMapOpenPicker'),
            behavior: HitTestBehavior.opaque,
            onTap: _isSaving ? null : _openMapPinPicker,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: FlutterMap(
                        mapController: _previewMapController,
                        options: MapOptions(
                          initialCenter: currentLatLng,
                          initialZoom: 16,
                          onMapReady: _onPreviewMapReady,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: MapTiles.streetUrl,
                            maxNativeZoom: MapTiles.streetMaxNativeZoom,
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
                                      lcpColorSeed(activeLcp),
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
                                      activeNap.replaceAll(RegExp(r'\D'), ''),
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
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              (Theme.of(context).brightness == Brightness.dark
                                      ? AppTheme.darkCard
                                      : Colors.white)
                                  .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.hairlineOf(context),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.open_in_full_rounded,
                              size: 20,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap map to adjust',
                              style: context.text.labelSmall!.copyWith(
                                fontWeight: FontWeight.w700,
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
          ),
          const SizedBox(height: 14),
        ],

        // Coordinates Input Field
        TextField(
          key: const ValueKey('inputCoordinates'),
          controller: _coordinatesController,
          decoration: InputDecoration(
            labelText: widget.isCreateMode || widget.allowEmptyCoordinates
                ? 'WGS84 Coordinates (Lat, Long — optional)'
                : 'WGS84 Coordinates (Lat, Long)',
            hintText: 'e.g. 14.586200, 121.061800',
            prefixIcon: const Icon(Icons.gps_fixed_rounded, size: 20),
            suffixIcon: _coordinatesController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() {
                      _coordinatesController.clear();
                      _resetPreviewMapState();
                    }),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onChanged: (_) {
            setState(() {});
            final parsed = _parsedLatLng;
            if (parsed == null) {
              _resetPreviewMapState();
            } else if (parsed != _lastPreviewCenter) {
              _movePreviewMap(parsed);
            }
          },
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom > 0
        ? MediaQuery.of(context).viewInsets.bottom
        : MediaQuery.of(context).padding.bottom;
    final currentLatLng = _parsedLatLng;
    final headerTitle = widget.sheetTitle ??
        (widget.isCreateMode
            ? 'Create LCP NAP Location'
            : 'Map LCP NAP Location');
    final headerSubtitle = _lcpNapController.text.trim().isNotEmpty
        ? _lcpNapController.text.trim()
        : (widget.isCreateMode
            ? 'Enter LCP Cabinet, NAP Box, and site details'
            : widget.location.lcpNap);

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
                      /*
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
                      */
                      // Gene - Nov, 11, 2026: Dynamic sheet title and subtitle for Create, Edit Details, and Map Location modes.
                      Text(
                        headerTitle,
                        style: context.text.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headerSubtitle,
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
                    /*
                    child: Text(
                      _errorMessage!,
                      style: context.text.bodySmall!
                          .copyWith(color: AppTheme.danger),
                    ),
                    */
                    // Gene - Nov, 12, 2026: Use WCAG-verified dangerInkOf token for error text in both light and dark modes.
                    child: Text(
                      _errorMessage!,
                      style: context.text.bodySmall!
                          .copyWith(color: AppTheme.dangerInkOf(context)),
                    ),
                  ),
                ],

                // Gene - Nov, 11, 2026: Render Site Identification & Capacity and GPS Coordinates sections in contextual order.
                if (widget.isCreateMode || widget.allowEmptyCoordinates) ...[
                  _buildSiteIdentitySection(context, isDark),
                  _buildCoordinatesSection(context, currentLatLng),
                ] else ...[
                  _buildCoordinatesSection(context, currentLatLng),
                  _buildSiteIdentitySection(context, isDark),
                ],

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
            /*
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
                    : Icon(
                        widget.isCreateMode
                            ? Icons.add_location_alt_rounded
                            : Icons.save_rounded,
                        size: 20,
                      ),
                label: Text(_isSaving
                    ? (widget.isCreateMode
                        ? 'Creating Location...'
                        : 'Saving Location...')
                    : (widget.isCreateMode
                        ? 'Create LCP NAP Location'
                        : 'Save & Update Location')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            */
            // Gene - Nov, 12, 2026: Upgraded primary action button to 56dp minimum height (growing vertically at 200% font scale) and AppTheme.radiusButton per DESIGN.md.
            child: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppTheme.primaryButtonHeight,
                ),
                child: ElevatedButton.icon(
                  key: const ValueKey('btnSaveLocation'),
                  onPressed: _isSaving ? null : _saveLocation,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          widget.isCreateMode
                              ? Icons.add_location_alt_rounded
                              : Icons.save_rounded,
                          size: 22,
                        ),
                  label: Text(_isSaving
                      ? (widget.isCreateMode
                          ? 'Creating Location...'
                          : 'Saving Location...')
                      : (widget.isCreateMode
                          ? 'Create LCP NAP Location'
                          : 'Save & Update Location')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
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
  // Gene - Nov, 21, 2026: Allow callers (e.g. detail screen tap-to-open map) to customize the confirmation button label.
  final String confirmButtonLabel;

  /*
  const LcpNapMapPickerScreen({
    super.key,
    required this.location,
    this.initialLatLng,
    this.tileProvider,
    this.placeLookup,
    this.locationService,
  });
  */
  const LcpNapMapPickerScreen({
    super.key,
    required this.location,
    this.initialLatLng,
    this.tileProvider,
    this.placeLookup,
    this.locationService,
    this.confirmButtonLabel = 'Confirm Pin Location',
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
  // Gene - Nov, 21, 2026: Track map readiness, pending camera move, and live user GPS marker so auto-locate always moves both pin and camera cleanly.
  bool _mapReady = false;
  LatLng? _pendingMoveTarget;
  double? _pendingMoveZoom;
  LatLng? _currentUserGps;

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

  // Gene - Nov, 21, 2026: Dispose MapController when LcpNapMapPickerScreen closes.
  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTiles() async {
    try {
      final p = await MapTiles.provider();
      if (mounted) setState(() => _tiles = p);
    } catch (_) {}
  }

  LocationService get _locationService =>
      widget.locationService ?? LocationService.instance;

  // Gene - Nov, 21, 2026: Safe camera move helper that flushes queued moves once MapOptions.onMapReady fires.
  void _onMapReady() {
    _mapReady = true;
    final pendingTarget = _pendingMoveTarget;
    final pendingZoom = _pendingMoveZoom;
    if (pendingTarget != null && pendingZoom != null) {
      _pendingMoveTarget = null;
      _pendingMoveZoom = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(pendingTarget, pendingZoom);
        } catch (_) {}
      });
    }
  }

  void _moveCamera(LatLng target, double zoom) {
    final maxAllowed =
        _satellite ? MapTiles.satelliteMaxZoom : MapTiles.streetMaxZoom;
    final clampedZoom = zoom.clamp(4.0, maxAllowed);
    if (_mapReady) {
      try {
        _mapController.move(target, clampedZoom);
      } catch (_) {
        _pendingMoveTarget = target;
        _pendingMoveZoom = clampedZoom;
      }
    } else {
      _pendingMoveTarget = target;
      _pendingMoveZoom = clampedZoom;
    }
  }

  /*
  Future<void> _centerOnGps() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() => _pinLocation = target);
        /*
        _mapController.move(target, 17);
        */
        // Gene - Nov, 11, 2026: Zoom closer (19.5) when centering on GPS so technicians can pin the exact pole or wall.
        _mapController.move(target, 19.5);
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
    /*
    _mapController.move(target, 17);
    */
    // Gene - Nov, 11, 2026: Zoom closer (19.0) after place search for street/pole-level pinning.
    _mapController.move(target, 19.0);
  }
  */
  // Gene - Nov, 21, 2026: Move both the pin and camera reliably on auto-locate/search, display user GPS halo, and report GPS lookup failures via SnackBar.
  Future<void> _centerOnGps() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;
      if (pos != null) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _pinLocation = target;
          _currentUserGps = target;
        });
        _moveCamera(target, 19.5);
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

  void _onPlaceLocated(LatLng target, String query) {
    setState(() {
      _pinLocation = target;
    });
    _moveCamera(target, 19.0);
  }

  // Gene - Nov, 11, 2026: Added explicit zoom-in / zoom-out helpers up to maxZoom (22) for precise pole pinning.
  void _zoomIn() {
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom + 1).clamp(4.0, MapTiles.streetMaxZoom),
    );
  }

  void _zoomOut() {
    _mapController.move(
      _mapController.camera.center,
      (_mapController.camera.zoom - 1).clamp(4.0, MapTiles.streetMaxZoom),
    );
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
            /*
            options: MapOptions(
              initialCenter: _pinLocation,
              /*
              initialZoom: 16.5,
              */
              // Gene - Nov, 11, 2026: Open map pin picker at zoom 18.0 and allow deep zoom up to 22 for exact pole placement.
              initialZoom: 18.0,
              minZoom: 4,
              maxZoom: MapTiles.streetMaxZoom,
              onTap: (_, point) {
                setState(() => _pinLocation = point);
              },
            ),
            */
            // Gene - Nov, 21, 2026: Wire onMapReady so queued GPS/search camera moves execute reliably.
            options: MapOptions(
              initialCenter: _pinLocation,
              initialZoom: 18.0,
              minZoom: 4,
              maxZoom: MapTiles.streetMaxZoom,
              onMapReady: _onMapReady,
              onTap: (_, point) {
                setState(() => _pinLocation = point);
              },
            ),
            children: [
              if (_tiles != null)
                /*
                TileLayer(
                  urlTemplate:
                      _satellite ? MapTiles.satelliteUrl : MapTiles.streetUrl,
                  maxZoom: _satellite
                      ? MapTiles.satelliteMaxZoom
                      : MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: _tiles,
                ),
                */
                // Gene - Nov, 11, 2026: Pass maxNativeZoom so flutter_map scales native high-res tiles smoothly up to zoom 22 without "no data" tiles.
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
                  tileProvider: _tiles,
                ),
              // Marker for the pinned location
              /*
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
              */
              // Gene - Nov, 21, 2026: Show live blue GPS halo dot when auto-located alongside the adjustable site pin marker.
              MarkerLayer(
                markers: [
                  if (_currentUserGps != null)
                    Marker(
                      key: const Key('pickerUserGpsMarker'),
                      point: _currentUserGps!,
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

          /*
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
          */
          /*
          // Gene - Nov, 11, 2026: Added + / - zoom buttons above the GPS button on the Pin Picker screen so technicians can zoom to level 22 and pin accurately.
          Positioned(
            right: 16,
            bottom: 125,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(10),
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const ValueKey('btnPickerZoomIn'),
                        onTap: _zoomIn,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.add_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppTheme.darkSlate,
                          ),
                        ),
                      ),
                      Container(
                        height: 1,
                        width: 28,
                        color:
                            isDark ? AppTheme.borderDark : AppTheme.borderLight,
                      ),
                      InkWell(
                        key: const ValueKey('btnPickerZoomOut'),
                        onTap: _zoomOut,
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.remove_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppTheme.darkSlate,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
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
              ],
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
          */
          // Gene - Nov, 21, 2026: Stack zoom controls & auto-locate FAB cleanly above the bottom confirmation card so fabCenterGps is never obscured by the card.
          Positioned(
            left: 14,
            right: 14,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(10),
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              key: const ValueKey('btnPickerZoomIn'),
                              onTap: _zoomIn,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.darkSlate,
                                ),
                              ),
                            ),
                            Container(
                              height: 1,
                              width: 28,
                              color: isDark
                                  ? AppTheme.borderDark
                                  : AppTheme.borderLight,
                            ),
                            InkWell(
                              key: const ValueKey('btnPickerZoomOut'),
                              onTap: _zoomOut,
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(
                                  Icons.remove_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.darkSlate,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FloatingActionButton.small(
                        key: const ValueKey('fabCenterGps'),
                        heroTag: 'fabMapPickerGps',
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        backgroundColor:
                            isDark ? AppTheme.darkCard : Colors.white,
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
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
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: AppTheme.minTarget,
                            ),
                            child: ElevatedButton.icon(
                              key: const ValueKey('btnConfirmPinLocation'),
                              onPressed: () =>
                                  Navigator.of(context).pop(_pinLocation),
                              icon: const Icon(Icons.check_rounded, size: 20),
                              label: Text(widget.confirmButtonLabel),
                            ),
                          ),
                        ),
                      ],
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
