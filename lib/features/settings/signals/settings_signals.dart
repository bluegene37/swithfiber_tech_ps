import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/secure_storage_service.dart';

// Gene - Nov, 23, 2026: Added technician preferred turn-by-turn navigation app setting.
enum PreferredNavApp {
  google('Google Maps'),
  waze('Waze'),
  apple('Apple Maps'),
  ask('Always ask');

  final String label;
  const PreferredNavApp(this.label);

  static PreferredNavApp parse(String? raw) {
    final norm = raw?.trim().toLowerCase();
    for (final v in values) {
      if (v.name == norm) return v;
    }
    return PreferredNavApp.google;
  }
}

/// Device-level preferences that are not tied to a technician's session.
///
/// Stored alongside the API base URL and cleared only by a full reset, so a
/// logout does not throw away the technician's display choices.
class SettingsSignals {
  static final SettingsSignals instance = SettingsSignals._internal();
  factory SettingsSignals() => instance;
  SettingsSignals._internal();

  final SecureStorageService _storage = SecureStorageService.instance;

  final themeMode = signal<ThemeMode>(ThemeMode.light);
  // Gene - Nov, 23, 2026: Preferred turn-by-turn map application (defaults to Google Maps).
  final preferredNavApp = signal<PreferredNavApp>(PreferredNavApp.google);

  bool get isDarkMode => themeMode.value == ThemeMode.dark;

  /// Load saved preferences. Falls back to light on anything unreadable so a
  /// corrupt value can never leave the app themeless.
  Future<void> restore() async {
    try {
      final saved = await _storage.read(AppConstants.keyDarkMode);
      themeMode.value = saved?.trim().toLowerCase() == 'true'
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (_) {
      themeMode.value = ThemeMode.light;
    }
    try {
      final navSaved = await _storage.read(AppConstants.keyPreferredNavApp);
      preferredNavApp.value = PreferredNavApp.parse(navSaved);
    } catch (_) {
      preferredNavApp.value = PreferredNavApp.google;
    }
  }

  Future<void> setDarkMode(bool enabled) async {
    themeMode.value = enabled ? ThemeMode.dark : ThemeMode.light;
    await _storage.write(AppConstants.keyDarkMode, enabled.toString());
  }

  /// Persist the technician's preferred turn-by-turn navigation app.
  Future<void> setPreferredNavApp(PreferredNavApp app) async {
    preferredNavApp.value = app;
    try {
      await _storage.write(AppConstants.keyPreferredNavApp, app.name);
    } catch (_) {
      // Ignore storage failures in headless test environments.
    }
  }
}
