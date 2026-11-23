// Gene - Nov, 23, 2026: Added DraftStorageService to auto-save and restore completion report and service order drafts across app kills/switches.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists in-progress report and repair form drafts on the phone so
/// switching to a speedtest app, taking a call, or background termination
/// never wipes unsaved technician work.
class DraftStorageService {
  static final DraftStorageService instance = DraftStorageService._internal();

  factory DraftStorageService() => instance;

  DraftStorageService._internal();

  Directory? _customBaseDir;
  bool _platformDocsUnavailable = false;
  final Map<String, Map<String, dynamic>> _memoryFallback = {};

  /// Reset storage overrides and in-memory fallback for unit and widget tests.
  @visibleForTesting
  void resetForTesting({Directory? baseDir}) {
    _customBaseDir = baseDir;
    _platformDocsUnavailable = false;
    _memoryFallback.clear();
  }

  String _safeFileName(String key) =>
      key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<Directory?> _resolveDraftsDir() async {
    if (_customBaseDir != null) {
      final dir = Directory(p.join(_customBaseDir!.path, 'drafts'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    if (_platformDocsUnavailable) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'drafts'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      // MissingPluginException in headless test environments falls back cleanly
      // to the in-memory store.
      _platformDocsUnavailable = true;
      return null;
    }
  }

  /// Persist [data] under [key] to disk (or memory fallback in tests).
  Future<void> saveDraft(String key, Map<String, dynamic> data) async {
    final copy = Map<String, dynamic>.from(data);
    copy['savedAt'] = DateTime.now().toIso8601String();
    _memoryFallback[key] = copy;

    final dir = await _resolveDraftsDir();
    if (dir == null) return;

    try {
      final file = File(p.join(dir.path, '${_safeFileName(key)}.json'));
      await file.writeAsString(jsonEncode(copy), flush: true);
    } catch (_) {
      // Keep memory copy even if filesystem write fails.
    }
  }

  /// Load a previously saved draft for [key], or null if none exists.
  Future<Map<String, dynamic>?> loadDraft(String key) async {
    final dir = await _resolveDraftsDir();
    if (dir != null) {
      try {
        final file = File(p.join(dir.path, '${_safeFileName(key)}.json'));
        if (file.existsSync()) {
          final raw = await file.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            return Map<String, dynamic>.from(decoded);
          }
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(k.toString(), v));
          }
        }
        return null;
      } catch (_) {
        // Fall through to memory fallback if disk read/parse fails.
      }
    }
    final mem = _memoryFallback[key];
    return mem == null ? null : Map<String, dynamic>.from(mem);
  }

  /// Remove any saved draft for [key].
  Future<void> clearDraft(String key) async {
    _memoryFallback.remove(key);
    final dir = await _resolveDraftsDir();
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, '${_safeFileName(key)}.json'));
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors.
    }
  }
}
