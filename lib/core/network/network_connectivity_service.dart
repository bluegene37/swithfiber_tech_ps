import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../sync/powersync_service.dart';

/// Callback invoked when the application transitions from offline to online.
typedef OnlineCallback = FutureOr<void> Function();

/// Reactive service that listens for network connectivity restoration and
/// executes registered reconnection handlers (e.g. flushing pending offline mutations
/// and pulling fresh remote data).
class NetworkConnectivityService {
  static NetworkConnectivityService? _instance;

  /// Global singleton instance.
  static NetworkConnectivityService get instance =>
      _instance ??= NetworkConnectivityService();

  /// Setter for testing dependency injection.
  @visibleForTesting
  static set instance(NetworkConnectivityService service) =>
      _instance = service;

  /// Resets the singleton instance, cancelling any active subscription.
  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<List<ConnectivityResult>>? _osSubscription;
  final List<OnlineCallback> _listeners = [];
  bool _isConnected = false;
  bool _isInitialized = false;

  /// Whether the app is currently known to be connected/online.
  bool get isConnected => _isConnected;

  /// Whether [initialize] has been called.
  bool get isInitialized => _isInitialized;

  /// Whether an underlying stream subscription is currently active.
  bool get hasActiveSubscription => _subscription != null;

  /// The number of registered online callbacks.
  int get listenerCount => _listeners.length;

  /// Creates a [NetworkConnectivityService].
  ///
  /// If [connectionStream] is provided, initializes immediately with that stream.
  NetworkConnectivityService({
    Stream<bool>? connectionStream,
    Stream<List<ConnectivityResult>>? osConnectivityStream,
    bool initialConnected = false,
  }) {
    if (connectionStream != null || osConnectivityStream != null) {
      initialize(
        connectionStream: connectionStream,
        osConnectivityStream: osConnectivityStream,
        initialConnected: initialConnected,
      );
    }
  }

  /// Initializes the service to monitor OS network & PowerSync connection transitions.
  void initialize({
    Stream<bool>? connectionStream,
    Stream<List<ConnectivityResult>>? osConnectivityStream,
    bool? initialConnected,
  }) {
    _subscription?.cancel();
    _subscription = null;
    _osSubscription?.cancel();
    _osSubscription = null;
    _isInitialized = true;

    if (connectionStream != null) {
      _isConnected = initialConnected ?? false;
      _subscription = connectionStream.listen(
        _handleConnectionChange,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'NetworkConnectivityService: stream error: $error\n$stackTrace',
          );
        },
        cancelOnError: false,
      );
      return;
    }

    if (PowerSyncService.instance.isInitialized) {
      _isConnected = initialConnected ?? PowerSyncService.instance.isConnected;
      _subscription = PowerSyncService.instance.db.statusStream
          .map((status) => status.connected)
          .listen(
        _handleConnectionChange,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'NetworkConnectivityService: statusStream error: $error\n$stackTrace',
          );
        },
        cancelOnError: false,
      );
    } else {
      _isConnected = initialConnected ?? false;
    }

    // Gene - Nov, 28, 2026: Also monitor OS connectivity via connectivity_plus so offline -> online restoration wakes lookups & PowerSync sync immediately (skipped in headless tests unless osConnectivityStream is injected).
    if (osConnectivityStream != null ||
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final Stream<List<ConnectivityResult>> source =
            osConnectivityStream ?? Connectivity().onConnectivityChanged;
        _osSubscription = source.listen(
          (results) {
            final online = results.any((r) => r != ConnectivityResult.none);
            _handleConnectionChange(online);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'NetworkConnectivityService: OS connectivity stream error: $error\n$stackTrace',
            );
          },
          cancelOnError: false,
        );
      } catch (_) {
        // Safe fallback in headless environments without platform plugins.
      }
    }
  }

  /// Registers a callback to be invoked when the app transitions from
  /// offline (`connected == false`) to online (`connected == true`).
  ///
  /// Returns a function that, when called, removes this listener.
  void Function() addOnlineListener(OnlineCallback callback) {
    if (!_isInitialized &&
        _subscription == null &&
        PowerSyncService.instance.isInitialized) {
      initialize();
    }
    _listeners.add(callback);
    return () => removeOnlineListener(callback);
  }

  /// Removes a previously registered [callback].
  void removeOnlineListener(OnlineCallback callback) {
    _listeners.remove(callback);
  }

  /// Internal handler for connection status changes.
  Future<void> _handleConnectionChange(bool connected) async {
    final wasConnected = _isConnected;
    _isConnected = connected;

    // Trigger only on offline -> online transition
    if (!wasConnected && connected) {
      await _notifyListeners();
    }
  }

  /// Iterates all registered callbacks gracefully. A failure in one
  /// callback does not interrupt others.
  Future<void> _notifyListeners() async {
    final callbacks = List<OnlineCallback>.from(_listeners);
    for (final callback in callbacks) {
      try {
        await callback();
      } catch (e, stackTrace) {
        debugPrint(
          'NetworkConnectivityService: error executing online listener: $e\n$stackTrace',
        );
      }
    }
  }

  /// Manually triggers online transition notification for testing.
  @visibleForTesting
  Future<void> triggerOnlineForTesting() async {
    await _handleConnectionChange(true);
  }

  /// Cancels active stream subscriptions and clears all listeners.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _osSubscription?.cancel();
    _osSubscription = null;
    _listeners.clear();
    _isConnected = false;
    _isInitialized = false;
  }
}
