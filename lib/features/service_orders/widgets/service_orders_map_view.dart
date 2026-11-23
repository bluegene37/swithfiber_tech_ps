import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../lcp_nap/services/map_tiles.dart';
import '../models/service_order_model.dart';
import '../signals/service_orders_signals.dart';

/// Interactive map view plotting filtered service orders with priority-colored pins.
class ServiceOrdersMapView extends StatefulWidget {
  final ServiceOrdersSignals signals;
  final TileProvider? tileProvider;
  final void Function(ServiceOrderDto order)? onOpenTicket;
  final LocationService? locationService;

  const ServiceOrdersMapView({
    super.key,
    required this.signals,
    this.tileProvider,
    this.onOpenTicket,
    this.locationService,
  });

  @override
  State<ServiceOrdersMapView> createState() => _ServiceOrdersMapViewState();
}

class _ServiceOrdersMapViewState extends State<ServiceOrdersMapView> {
  final MapController _mapController = MapController();

  static const LatLng _fallbackCenter = LatLng(
    LocationService.fallbackLat,
    LocationService.fallbackLng,
  );

  TileProvider? _tiles;
  ServiceOrderDto? _selectedOrder;
  LatLng? _techPosition;
  bool _satellite = false;
  bool _mapReady = false;
  bool _didInitialFit = false;

  LocationService get _location =>
      widget.locationService ?? LocationService.instance;

  @override
  void initState() {
    super.initState();
    _tiles = widget.tileProvider;
    if (_tiles == null) _loadTiles();
    final cachedPos = _location.lastKnownPosition;
    if (cachedPos != null) {
      _techPosition = LatLng(cachedPos.latitude, cachedPos.longitude);
    } else {
      _fetchLocation();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTiles() async {
    try {
      final provider = await MapTiles.provider();
      if (!mounted) return;
      setState(() => _tiles = provider);
    } catch (_) {
      // Headless/test hosts without a cache dir still display vector pins.
    }
  }

  Future<void> _fetchLocation() async {
    final pos = await _location.getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _techPosition = LatLng(pos.latitude, pos.longitude);
    });
  }

  Color _pinColorFor(ServiceOrderDto order) {
    if (order.isUrgent) return AppTheme.danger;
    if ((order.priorityLevel ?? '').toLowerCase().contains('high')) {
      return AppTheme.warning;
    }
    return AppTheme.primary;
  }

  void _fitOrders(List<ServiceOrderDto> mappable) {
    final points = <LatLng>[
      for (final o in mappable)
        if (o.latLng != null) o.latLng!,
      if (_techPosition != null) _techPosition!,
    ];
    if (points.isEmpty) {
      _mapController.move(_fallbackCenter, 13.5);
      return;
    }
    if (points.length == 1) {
      _mapController.move(points.first, 15.5);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(48, 72, 72, 160),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SignalBuilder(
      builder: (context) {
        final orders = widget.signals.filteredOrders.value;
        final mappable = orders.where((o) => o.latLng != null).toList();
        final unmappedCount = orders.length - mappable.length;

        if (!_didInitialFit && _mapReady) {
          _didInitialFit = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitOrders(mappable);
          });
        }

        // Clear selection if current filter hides the selected order.
        final selected = _selectedOrder != null &&
                orders.any((o) => o.id == _selectedOrder!.id)
            ? _selectedOrder
            : null;

        final String? distanceText;
        if (selected != null &&
            selected.latLng != null &&
            _location.lastKnownPosition != null) {
          final pos = _location.lastKnownPosition!;
          final meters = _location.distanceBetween(
            startLat: pos.latitude,
            startLng: pos.longitude,
            endLat: selected.latLng!.latitude,
            endLng: selected.latLng!.longitude,
          );
          distanceText = _location.formatDistance(meters);
        } else {
          distanceText = null;
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mappable.isNotEmpty
                    ? mappable.first.latLng!
                    : (_techPosition ?? _fallbackCenter),
                initialZoom: 14,
                minZoom: 4,
                maxZoom: MapTiles.streetMaxZoom,
                onMapReady: () {
                  _mapReady = true;
                  if (!_didInitialFit) {
                    _didInitialFit = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fitOrders(mappable);
                    });
                  }
                },
                onTap: (_, __) {
                  if (_selectedOrder != null) {
                    setState(() => _selectedOrder = null);
                  }
                },
              ),
              children: [
                if (_tiles != null)
                  TileLayer(
                    urlTemplate:
                        _satellite ? MapTiles.satelliteUrl : MapTiles.streetUrl,
                    tileProvider: _tiles,
                    maxNativeZoom: _satellite
                        ? MapTiles.satelliteMaxNativeZoom
                        : MapTiles.streetMaxNativeZoom,
                    maxZoom: _satellite
                        ? MapTiles.satelliteMaxZoom
                        : MapTiles.streetMaxZoom,
                    userAgentPackageName: MapTiles.userAgentPackageName,
                  ),
                MarkerLayer(
                  markers: [
                    if (_techPosition != null)
                      Marker(
                        point: _techPosition!,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.info,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                    for (final order in mappable)
                      Marker(
                        point: order.latLng!,
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          key: ValueKey('repair_map_pin_${order.id}'),
                          onTap: () {
                            widget.signals.markOrderAsRead(order.id);
                            setState(() => _selectedOrder = order);
                            _mapController.move(
                              order.latLng!,
                              _mapController.camera.zoom.clamp(14.5, 18.0),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _pinColorFor(order),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected?.id == order.id
                                    ? Colors.amber
                                    : Colors.white,
                                width: selected?.id == order.id ? 3 : 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.wrench_fill,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (unmappedCount > 0)
              Positioned(
                top: 12,
                left: 16,
                right: 76,
                child: Container(
                  key: const ValueKey('repairs_map_unmapped_banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkCard.withValues(alpha: 0.94)
                        : Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    ),
                  ),
                  child: Text(
                    '$unmappedCount unmapped repair ticket${unmappedCount == 1 ? '' : 's'} (missing GPS)',
                    style: context.text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      key: const ValueKey('repairs_map_recenter_button'),
                      tooltip: 'Recenter Map',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () {
                        unawaited(_fetchLocation());
                        _fitOrders(mappable);
                      },
                      icon: Icon(
                        Icons.my_location_rounded,
                        size: 24,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      key: const ValueKey('repairs_map_satellite_button'),
                      tooltip: 'Toggle Satellite',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => setState(() => _satellite = !_satellite),
                      icon: Icon(
                        _satellite
                            ? Icons.map_outlined
                            : Icons.satellite_alt_rounded,
                        size: 24,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: Card(
                  key: const ValueKey('repairs_map_popup_card'),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'SO-${selected.id.toString().padLeft(4, '0')}',
                              style: context.text.labelMedium!.copyWith(
                                fontFamily: 'JetBrains Mono',
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandInkOf(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selected.concern,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium!.copyWith(
                                  color: AppTheme.secondaryInkOf(context),
                                ),
                              ),
                            ),
                            if (selected.isUrgent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'URGENT',
                                  style: context.text.labelSmall!
                                      .copyWith(color: Colors.white),
                                ),
                              ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _selectedOrder = null),
                              icon: const Icon(Icons.close_rounded, size: 24),
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                        Text(
                          selected.fullName,
                          style: context.text.titleSmall,
                        ),
                        if (selected.address.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            selected.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ],
                        if (distanceText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$distanceText away',
                            style: context.text.labelSmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey(
                                    'repairs_map_navigate_button'),
                                onPressed: () =>
                                    MapNavigationService.navigateTo(
                                  selected.latLng!,
                                  label: selected.fullName,
                                  context: context,
                                ),
                                icon: const Icon(Icons.navigation_rounded,
                                    size: 20),
                                label: const Text('Navigate'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const ValueKey('repairs_map_open_button'),
                                onPressed: () =>
                                    widget.onOpenTicket?.call(selected),
                                icon: const Icon(Icons.open_in_new_rounded,
                                    size: 20),
                                label: const Text('Open Ticket'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
