import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  static TileProvider? _provider;

  /// Build the caching tile provider. Safe to call repeatedly; the underlying
  /// store is created once.
  ///
  /// Uses its own [Dio] instance rather than the app's API client, which is
  /// pinned to the Switch Fiber server's self-signed certificate and must not
  /// be reused for public hosts.
  static Future<TileProvider> provider() async {
    final existing = _provider;
    if (existing != null) return existing;

    // Tiles are plain files on disk; the app's database is PowerSync's and
    // is not shared with the tile cache.
    final dir = await getApplicationCacheDirectory();
    /*
    final store = FileCacheStore(p.join(dir.path, 'map_tiles'));
    */
    // Gene - Nov, 11, 2026: Bumped tile cache directory to map_tiles_v2 so any previously cached Esri "Map data not yet available" placeholder tiles are bypassed.
    final store = FileCacheStore(p.join(dir.path, 'map_tiles_v2'));

    final created = CachedTileProvider(
      store: store,
      maxStale: _cacheDuration,
      dio: Dio(),
    );
    _provider = created;
    return created;
  }
}
