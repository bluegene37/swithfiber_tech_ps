import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_service.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Central reactive signals for technician authentication state.
class AuthSignals {
  static final AuthSignals instance = AuthSignals._internal();
  factory AuthSignals() => instance;
  AuthSignals._internal();

  final AuthService _authService = AuthService();

  // Signals
  final currentUser = signal<UserModel?>(null);
  final authLoading = signal<bool>(false);
  final authError = signal<String?>(null);
  final rememberMe = signal<bool>(true);

  // Computed state
  late final ReadonlySignal<bool> isAuthenticated = computed(
    () => currentUser.value != null,
  );

  /// Restore user session on startup
  Future<void> restoreSession() async {
    authLoading.value = true;
    try {
      final user = await _authService.restoreSession();
      currentUser.value = user;
      if (user != null && PowerSyncService.instance.isInitialized) {
        unawaited(PowerSyncService.instance.reconnect());
      }
    } catch (e) {
      authError.value = e.toString();
    } finally {
      authLoading.value = false;
    }
  }

  /// Perform technician login
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    authLoading.value = true;
    authError.value = null;
    try {
      final user = await _authService.login(
        username: username,
        password: password,
      );
      currentUser.value = user;
      if (PowerSyncService.instance.isInitialized) {
        unawaited(PowerSyncService.instance.reconnect());
      }
      return true;
    } catch (e) {
      authError.value = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      authLoading.value = false;
    }
  }

  /// Refresh the signed-in technician's profile from the server.
  /// Silently keeps the cached profile when offline.
  Future<void> refreshProfile() async {
    final current = currentUser.value;
    if (current == null) return;
    try {
      final previousEmail = current.email.trim().toLowerCase();
      final updated = await _authService.fetchProfile(current.id);
      currentUser.value = updated;
      /*
      if (PowerSyncService.instance.isInitialized) {
        unawaited(PowerSyncService.instance.reconnect());
      }
      */
      // Gene - Nov, 28, 2026: Only reconnect PowerSync on profile refresh if the email changed or sync is disconnected, avoiding needless stream restarts.
      final nextEmail = updated.email.trim().toLowerCase();
      if (PowerSyncService.instance.isInitialized &&
          (previousEmail != nextEmail ||
              !PowerSyncService.instance.isConnected)) {
        unawaited(PowerSyncService.instance.reconnect());
      }
    } catch (_) {
      // Offline or endpoint unavailable: the cached session stays valid.
    }
  }

  /// Perform technician logout
  /*
  Future<void> logout() async {
    await _authService.logout();
    currentUser.value = null;
    authError.value = null;
    if (PowerSyncService.instance.isInitialized) {
      unawaited(PowerSyncService.instance.disconnectAndClear());
    }
  }
  */
  // Gene - Nov, 28, 2026: Preserve optional reason banner message when 401 session expiry triggers automatic logout.
  Future<void> logout({String? reason}) async {
    await _authService.logout();
    currentUser.value = null;
    authError.value = reason;
    if (PowerSyncService.instance.isInitialized) {
      unawaited(PowerSyncService.instance.disconnectAndClear());
    }
  }
}
