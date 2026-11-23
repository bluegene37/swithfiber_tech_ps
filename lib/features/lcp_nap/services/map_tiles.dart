import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';

// Gene - Nov, 23, 2026: Coordinates of a single slippy-map tile for offline prefetch calculations.
typedef TileCoord = ({int z, int x, int y});

/// Tile source and on-disk cache for the plant and job maps.
///
/// Tiles are fetched over the network and cached to disk, so areas a technician
/// has already viewed keep rendering without a signal. Pin data itself comes
/// from the local database and is always available offline.
class MapTiles {
  MapTiles._();

  /// Base layers. Both come from Esri's public tile server, which needs no
  /// API key and serves real tiles down to zoom 19 (verified 2026-09-03).
  ///
  /// Why not the alternatives:
  ///
  /// * CARTO, which the web console uses, began stamping "API KEY REQUIRED"
  ///   across every free tile in September 2026, so it was dropped.
  /// * Raw OpenStreetMap tiles are free but the OSM Foundation's usage
  ///   policy does not permit distributed apps to use their servers.
  /// * Esri's dark canvas basemap returns a "map data not yet available"
  ///   placeholder past zoom 16, which is exactly where a technician zooms to
  ///   find a pole. So there is no separate dark street layer: dark mode
  ///   shows the same street map, as the satellite view already does.
  ///
  /// Esri World Imagery backs the satellite view, which technicians use to
  /// spot an actual pole or wall.
  /*
  static const String streetUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/'
      'MapServer/tile/{z}/{y}/{x}';
  static const String satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/'
      'MapServer/tile/{z}/{y}/{x}';

  static const String streetAttribution =
      'Tiles © Esri — Esri, HERE, Garmin, © OpenStreetMap contributors';
  static const String satelliteAttribution =
      'Imagery © Esri — Source: Esri, Maxar, Earthstar Geographics';

  /// Neither Esri service serves tiles past zoom 19.
  static const double satelliteMaxZoom = 19;
  static const double streetMaxZoom = 19;
  */
  // Gene - Nov, 11, 2026: Switched from Esri (which returns "Map data not yet available" past zoom 17 in the Philippines) to Google Street & Hybrid Satellite tiles with native zoom up to 21 and smooth over-zoom to 22 for exact pole-level pinning.
  static const String streetUrl =
      'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
  static const String satelliteUrl =
      'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';

  static const String streetAttribution = 'Map data © Google';
  static const String satelliteAttribution = 'Imagery © Google';

  /// Highest native tile zoom served before flutter_map scales tiles smoothly.
  static const int streetMaxNativeZoom = 21;
  static const int satelliteMaxNativeZoom = 20;

  /// Maximum interactive zoom level for pole-level precision pinning.
  static const double satelliteMaxZoom = 22;
  static const double streetMaxZoom = 22;

  /// Identifies this client to the tile provider.
  static const String userAgentPackageName = 'dev.genexis.swithfibertech';

  /// How long a cached tile stays usable offline before it is refetched.
  static const Duration _cacheDuration = Duration(days: 30);

  /*
  static TileProvider? _provider;
  */
  // Gene - Nov, 23, 2026: Retained CachedTileProvider subtype so offline prefetch shares the same DioCacheInterceptor store.
  static CachedTileProvider? _provider;

  /// Build the caching tile provider. Safe to call repeatedly; the underlying
  /// store is created once.
  ///
  /// Uses its own [Dio] instance rather than the app's API client, which is
  /// pinned to the Switch Fiber server's self-signed certificate and must not
  /// be reused for public hosts.
  static Future<TileProvider> provider() async {
    final existing = _provider;
    if (existing != null) return existing;

    final dir = await cacheDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Gene - Nov, 11, 2026: Bumped tile cache directory to map_tiles_v2 so any previously cached Esri "Map data not yet available" placeholder tiles are bypassed.
    final store = FileCacheStore(dir.path);

    final created = CachedTileProvider(
      store: store,
      maxStale: _cacheDuration,
      dio: Dio(),
    );
    _provider = created;
    return created;
  }

  // Gene - Nov, 23, 2026: Offline tile cache management (directory, byte size, clear, radius slippy-tile math, and bounded area prefetch).
  static Future<Directory> cacheDirectory() async {
    final dir = await getApplicationCacheDirectory();
    return Directory(p.join(dir.path, 'map_tiles_v2'));
  }

  static Future<int> getCacheSizeBytes() async {
    try {
      final dir = await cacheDirectory();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final stat = await entity.stat();
          total += stat.size;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    _provider = null;
    try {
      final dir = await cacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static List<TileCoord> tilesForRadius({
    required double centerLat,
    required double centerLng,
    double radiusKm = 1.5,
    List<int> zooms = const [15, 16, 17, 18],
    int maxTiles = 200,
  }) {
    if (maxTiles <= 0 || radiusKm <= 0) return const [];
    final latDelta = radiusKm / 111.32;
    final cosLat = math.cos(centerLat * math.pi / 180.0).abs().clamp(0.1, 1.0);
    final lngDelta = radiusKm / (111.32 * cosLat);

    final minLat = (centerLat - latDelta).clamp(-85.0511, 85.0511);
    final maxLat = (centerLat + latDelta).clamp(-85.0511, 85.0511);
    final minLng = (centerLng - lngDelta).clamp(-180.0, 180.0);
    final maxLng = (centerLng + lngDelta).clamp(-180.0, 180.0);

    int latToY(double lat, int n) {
      final rad = lat * math.pi / 180.0;
      final raw =
          ((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) /
                  2.0 *
                  n)
              .floor();
      return raw.clamp(0, n - 1);
    }

    int lngToX(double lng, int n) {
      final raw = ((lng + 180.0) / 360.0 * n).floor();
      return raw.clamp(0, n - 1);
    }

    final coords = <TileCoord>[];
    for (final z in zooms) {
      final n = 1 << z;
      final xMin = lngToX(minLng, n);
      final xMax = lngToX(maxLng, n);
      // Higher latitude -> smaller tile Y index in Web Mercator.
      final yMin = latToY(maxLat, n);
      final yMax = latToY(minLat, n);

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          coords.add((z: z, x: x, y: y));
          if (coords.length >= maxTiles) return coords;
        }
      }
    }
    return coords;
  }

  static Future<({int downloaded, int total})> prefetchArea({
    required double centerLat,
    required double centerLng,
    double radiusKm = 1.5,
    List<int> zooms = const [15, 16, 17, 18],
    int maxTiles = 200,
    bool satellite = false,
    Dio? dio,
    void Function(int done, int total)? onProgress,
  }) async {
    final tiles = tilesForRadius(
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
      zooms: zooms,
      maxTiles: maxTiles,
    );
    if (tiles.isEmpty) return (downloaded: 0, total: 0);
    // Gene - Nov, 23, 2026: Use public ApiClient.isNetworkBlocked getter to respect visibleForTesting annotation.
    /*
    if (dio == null && ApiClient.blockNetworkForTesting) {
    */
    if (dio == null && ApiClient.isNetworkBlocked) {
      return (downloaded: 0, total: tiles.length);
    }

    final Dio client;
    try {
      client = dio ?? ((await provider()) as CachedTileProvider).dio;
    } catch (_) {
      return (downloaded: 0, total: tiles.length);
    }

    final template = satellite ? satelliteUrl : streetUrl;
    var downloaded = 0;
    var processed = 0;

    for (var i = 0; i < tiles.length; i += 4) {
      final batch = tiles.sublist(i, math.min(i + 4, tiles.length));
      await Future.wait(batch.map((t) async {
        final url = template
            .replaceAll('{z}', '${t.z}')
            .replaceAll('{x}', '${t.x}')
            .replaceAll('{y}', '${t.y}');
        try {
          final resp = await client.get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              headers: const {'User-Agent': userAgentPackageName},
            ),
          );
          if (resp.statusCode == 200) {
            downloaded++;
          }
        } catch (_) {
          // Best-effort offline cache: ignore individual tile errors cleanly.
        }
      }));
      processed += batch.length;
      onProgress?.call(processed, tiles.length);
    }

    return (downloaded: downloaded, total: tiles.length);
  }
}
