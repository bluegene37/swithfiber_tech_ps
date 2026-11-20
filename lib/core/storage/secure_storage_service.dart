// Gene - Nov, 20, 2026: Added dart:convert import for JSON encoding/decoding integer ID sets in secure storage.
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// Secure key-value storage service using platform Keychain / Keystore.
class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._internal();

  factory SecureStorageService() => instance;

  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Get Bearer JWT token
  Future<String?> getToken() async {
    return await _storage.read(key: AppConstants.keyJwtToken);
  }

  /// Store Bearer JWT token
  Future<void> saveToken(String token) async {
    await _storage.write(key: AppConstants.keyJwtToken, value: token);
  }

  /// Delete Bearer JWT token
  Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.keyJwtToken);
  }

  /// Get cached serialized user session
  Future<String?> getUserSession() async {
    return await _storage.read(key: AppConstants.keyUserSession);
  }

  /// Store serialized user session
  Future<void> saveUserSession(String sessionJson) async {
    await _storage.write(key: AppConstants.keyUserSession, value: sessionJson);
  }

  /// Delete user session
  Future<void> deleteUserSession() async {
    await _storage.delete(key: AppConstants.keyUserSession);
  }

  /// Get customized Base URL if overridden in Settings
  Future<String> getBaseUrl() async {
    final customUrl = await _storage.read(key: AppConstants.keyApiBaseUrl);
    return customUrl?.trim().isNotEmpty == true
        ? customUrl!
        : AppConstants.defaultBaseUrl;
  }

  /// Save customized Base URL
  Future<void> saveBaseUrl(String url) async {
    await _storage.write(key: AppConstants.keyApiBaseUrl, value: url);
  }

  /// Read an arbitrary preference key.
  Future<String?> read(String key) => _storage.read(key: key);

  /// Write an arbitrary preference key.
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  // Gene - Nov, 20, 2026: Added safe JSON-encoded integer-set persistence helpers for unread badge state across app restarts.
  /// Reads a stored JSON integer list as a [Set<int>].
  /// Returns an empty set when absent, malformed, or when secure storage is unavailable (e.g. headless tests).
  Future<Set<int>> readIntSet(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.trim().isEmpty) return <int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      final result = <int>{};
      for (final item in decoded) {
        if (item is int) {
          result.add(item);
        } else if (item is num) {
          result.add(item.toInt());
        } else if (item is String) {
          final parsed = int.tryParse(item.trim());
          if (parsed != null) result.add(parsed);
        }
      }
      return result;
    } catch (_) {
      return <int>{};
    }
  }

  /// Writes a [Set<int>] as a JSON integer list, capped to the most recent [maxEntries].
  /// Safely no-ops if platform storage is unavailable (e.g. headless tests).
  Future<void> writeIntSet(
    String key,
    Set<int> ids, {
    int maxEntries = 500,
  }) async {
    try {
      final list = ids.toList();
      final trimmed = list.length > maxEntries
          ? list.sublist(list.length - maxEntries)
          : list;
      await _storage.write(key: key, value: jsonEncode(trimmed));
    } catch (_) {
      // Ignored in headless test environments or if keychain/keystore write fails.
    }
  }

  /// Clear only the technician's credentials, preserving device configuration
  /// such as the API base URL, which is not a credential and must survive a
  /// logout or an expired-token 401.
  Future<void> clearCredentials() async {
    await deleteToken();
    await deleteUserSession();
  }

  /// Clear everything, including device configuration. Full factory reset.
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
