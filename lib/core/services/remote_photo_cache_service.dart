// Gene - Nov, 28, 2026: Lazy disk-backed cache for remote site images fetched via authenticated GET endpoints, with local pending_attachments overlay and eviction.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RemotePhotoCacheService {
  static final RemotePhotoCacheService instance =
      RemotePhotoCacheService._internal();

  RemotePhotoCacheService._internal();

  Directory? _customCacheDir;

  void setCacheDirectoryForTesting(Directory? dir) {
    _customCacheDir = dir;
  }

  Future<Directory?> _entityDir(String entityType, int entityId) async {
    Directory base;
    if (_customCacheDir != null) {
      base = _customCacheDir!;
    } else if (Platform.environment.containsKey('FLUTTER_TEST')) {
      // Avoid cross-test contamination in shared Directory.systemTemp unless
      // a test explicitly configures setCacheDirectoryForTesting.
      return null;
    } else {
      try {
        base = await getTemporaryDirectory();
      } catch (_) {
        base = Directory.systemTemp;
      }
    }
    final dir =
        Directory(p.join(base.path, 'remote_photos', entityType, '$entityId'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Map<String, dynamic>?> readCachedJson(
    String entityType,
    int entityId,
  ) async {
    try {
      final dir = await _entityDir(entityType, entityId);
      if (dir == null) return null;
      final file = File(p.join(dir.path, 'images.json'));
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> writeCachedJson(
    String entityType,
    int entityId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final dir = await _entityDir(entityType, entityId);
      if (dir == null) return;
      final file = File(p.join(dir.path, 'images.json'));
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<void> invalidate(String entityType, [int? entityId]) async {
    try {
      Directory base;
      if (_customCacheDir != null) {
        base = _customCacheDir!;
      } else if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return;
      } else {
        try {
          base = await getTemporaryDirectory();
        } catch (_) {
          base = Directory.systemTemp;
        }
      }
      final root = entityId != null
          ? Directory(
              p.join(base.path, 'remote_photos', entityType, '$entityId'),
            )
          : Directory(p.join(base.path, 'remote_photos', entityType));
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }
}
