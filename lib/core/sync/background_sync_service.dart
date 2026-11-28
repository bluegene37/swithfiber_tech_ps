// Gene - Nov, 28, 2026: Best-effort background sync scheduler using workmanager (Android WorkManager & iOS BGTaskScheduler) that drains ps_crud + pending_attachments and refreshes lookups without ever calling disconnectAndClear.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/auth/services/auth_service.dart';
import '../constants/app_constants.dart';
import '../database/app_database.dart';
import '../storage/secure_storage_service.dart';
import 'lookups_sync_service.dart';
import 'powersync_backend_connector.dart';
import 'powersync_gateway_client.dart';
import 'powersync_service.dart';

const String switchfiberBackgroundSyncTask =
    'dev.genexis.swithfibertech.backgroundSync';
const String switchfiberImmediateSyncTask =
    'dev.genexis.swithfibertech.immediateSync';

@pragma('vm:entry-point')
void switchFiberWorkmanagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    return BackgroundSyncService.runBoundedBackgroundSync();
  });
}

class BackgroundSyncService {
  BackgroundSyncService._();

  static bool _initialized = false;

  static bool get _canUsePlatformScheduler =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> initializeAndRegister() async {
    if (_initialized || !_canUsePlatformScheduler) return;
    try {
      await Workmanager().initialize(switchFiberWorkmanagerDispatcher);
      await Workmanager().registerPeriodicTask(
        switchfiberBackgroundSyncTask,
        switchfiberBackgroundSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('BackgroundSyncService: failed to initialize workmanager: $e');
    }
  }

  static Future<void> scheduleOneOffSync() async {
    if (!_initialized || !_canUsePlatformScheduler) return;
    try {
      await Workmanager().registerOneOffTask(
        switchfiberImmediateSyncTask,
        switchfiberImmediateSyncTask,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {}
  }

  /// Runs a bounded best-effort background upload + lookups sync loop.
  /// Never calls `disconnectAndClear()`.
  static Future<bool> runBoundedBackgroundSync() async {
    try {
      final storage = SecureStorageService.instance;
      final gwToken =
          (await storage.read(AppConstants.keyPowerSyncGatewayToken))?.trim() ??
              '';
      final psToken =
          (await storage.read(AppConstants.keyPowerSyncToken))?.trim() ?? '';
      final jwt = (await storage.getToken())?.trim() ?? '';
      if (gwToken.isEmpty && psToken.isEmpty && jwt.isEmpty) {
        return true;
      }

      final powerSync = PowerSyncService.instance;
      if (!powerSync.isInitialized) {
        await PowerSyncService.clearStaleCredentialsOnFreshInstall();
        await powerSync.initialize();
      }
      if (!powerSync.isReplicatedMode) {
        return true;
      }

      final database = AppDatabase(powerSync.db);
      final connector = SwitchFiberBackendConnector(
        storage: storage,
        errorLog: database.syncErrorLogsDao,
        pendingAttachments: database.pendingAttachmentsDao,
        syncConflicts: database.syncConflictsDao,
        localIdMap: database.localIdMapDao,
        authService: AuthService(storage: storage),
      );

      if (!connector.hasGateway) {
        return true;
      }

      final deadline = DateTime.now().add(const Duration(seconds: 22));
      for (var i = 0; i < 5; i++) {
        if (DateTime.now().isAfter(deadline)) break;
        final pendingUploads = await powerSync.countPendingUploads();
        if (pendingUploads <= 0) break;
        await connector.uploadData(powerSync.db);
      }

      final lookupsSync = LookupsSyncService(
        lookupsDao: database.lookupsDao,
        storage: storage,
        authService: AuthService(storage: storage),
      );
      await lookupsSync.sync();
      return true;
    } on PowerSyncUploadException catch (e) {
      if (e.isUnauthorized) {
        // Keep local SQLite / ps_crud intact until user completes in-place re-login.
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
