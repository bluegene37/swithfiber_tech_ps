import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../models/lcp_nap_model.dart';
import '../services/map_clustering.dart';
import '../services/map_tiles.dart';
import '../signals/lcp_nap_signals.dart';

/// Screen displaying comprehensive details and status controls for an LCP NAP site with full Dark Mode support.
class LcpNapDetailScreen extends StatefulWidget {
  final int locationId;
  final LcpNapSignals signals;
  final TileProvider? tileProvider;

  const LcpNapDetailScreen({
    super.key,
    required this.locationId,
    required this.signals,
    this.tileProvider,
  });

  @override
  State<LcpNapDetailScreen> createState() => _LcpNapDetailScreenState();
}

class _LcpNapDetailScreenState extends State<LcpNapDetailScreen> {
  TileProvider? _tiles;

  @override
  void initState() {
    super.initState();
    _tiles = widget.tileProvider;
    if (_tiles == null) _loadTileProvider();
  }

  Future<void> _loadTileProvider() async {
    final provider = await MapTiles.provider();
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
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 24),
                tooltip: 'Copy Dispatch Summary',
                onPressed: () => _copySiteSummary(context, location, isDark),
              ),
            ],
          ),
          body: ListView(
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
                                    color: cabinetColor.withValues(alpha: 0.15),
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
                                    style: context.text.labelSmall!
                                        .copyWith(fontWeight: FontWeight.w800),
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

              // 4. GPS Geolocation Card
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
                          Text(
                            'GPS Geolocation Coordinates',
                            style: context.text.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
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
                                  location.coordinates ?? 'No GPS fix recorded',
                                  style: context.text.titleSmall!
                                      .copyWith(fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                            if (location.coordinates != null)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                tooltip: 'Copy coordinates',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: location.coordinates!),
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
                            icon:
                                const Icon(Icons.navigation_rounded, size: 18),
                            label: const Text('Start Turn-by-Turn Navigation'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
                : FlutterMap(
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
                      TileLayer(
                        urlTemplate: MapTiles.streetUrl,
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
}
