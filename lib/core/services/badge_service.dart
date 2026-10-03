import 'dart:io';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

// Gene - Oct 3, 2026: Application launcher icon badge management service for tracking open dispatch counts when app is backgrounded or closed.
class BadgeService {
  /// The shared instance. Not final so tests can install a stand-in or mock.
  static BadgeService instance = BadgeService();

  static bool get isRunningInTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  bool isEnabled = true;

  /// Updates the launcher icon badge number with the total pending/open items count.
  /// If [count] <= 0, the badge is removed.
  Future<void> updateBadgeCount(int count) async {
    if (!isEnabled || isRunningInTest) return;
    try {
      final isSupported = await AppBadgePlus.isSupported();
      if (!isSupported) return;

      if (count > 0) {
        await AppBadgePlus.updateBadge(count);
      } else {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (_) {
      // Gracefully ignored on platforms or OEM launchers that do not support badge counts
    }
  }

  /// Removes the launcher icon badge.
  Future<void> removeBadge() async {
    await updateBadgeCount(0);
  }
}
