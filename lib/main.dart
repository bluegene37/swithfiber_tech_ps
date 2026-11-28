/*
import 'dart:async';
*/
// Gene - Nov, 28, 2026: Restored dart:async unawaited and wired v12 LookupsSyncService, SyncConflictsSignals, BackgroundSyncService, and non-destructive 401 reauth.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'core/database/app_database.dart';
import 'core/database/daos/pending_attachments_dao.dart';
import 'core/network/api_client.dart';
import 'core/network/network_connectivity_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/sync/background_sync_service.dart';
import 'core/sync/lookups_sync_service.dart';
import 'core/sync/powersync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/signals/auth_signals.dart';
import 'features/catalogs/services/catalog_service.dart';
import 'features/diagnostics/signals/sync_conflicts_signals.dart';
import 'features/jobs/repositories/job_repository.dart';
import 'features/jobs/signals/jobs_signals.dart';
import 'features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'features/lcp_nap/signals/lcp_nap_signals.dart';
import 'features/service_orders/signals/service_orders_signals.dart';
import 'features/settings/signals/settings_signals.dart';
import 'features/shell/technician_shell.dart';
import 'features/splash/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Open the PowerSync database (the app's only local store) and the
  //    DAOs over it. Cloud sync is joined later, only when a PowerSync token
  //    has been configured; the REST API remains the sync transport until
  //    then (see powersync_schema.dart).
  // Gene - Nov, 28, 2026: Wipe orphaned Keychain/backup credentials on genuine fresh install before initializing PowerSync and session restore.
  await PowerSyncService.clearStaleCredentialsOnFreshInstall();
  final powerSync = PowerSyncService.instance;
  await powerSync.initialize();
  final database = AppDatabase(powerSync.db);
  // Gene - Nov, 27, 2026: Only prune sample seed rows in local-only mode so replicated PowerSync mode never queues deletes against real server IDs.
  if (!powerSync.isReplicatedMode) {
    await database.jobOrdersDao.deleteSampleJobs();
    await database.lcpNapLocationsDao.deleteSampleLocations();
  }
  /*
  final jobRepository =
      JobRepository(database.jobOrdersDao, errorLog: database.syncErrorLogsDao);
  final lcpNapRepository = LcpNapRepository(database.lcpNapLocationsDao);
  // Gene - Nov, 23, 2026: Pass SyncErrorLogsDao into ServiceOrdersSignals so refused repair uploads are logged.
  final serviceOrdersSignals = ServiceOrdersSignals(
    dao: database.serviceOrdersDao,
    errorLog: database.syncErrorLogsDao,
  );
  */
  // Gene - Nov, 28, 2026: Attach SQLite LookupsDao for offline-first catalog reads and wire v12 transactional photo/conflict/ID-map dependencies.
  CatalogService.instance.attachLookupsDao(database.lookupsDao);
  final authSignals = AuthSignals.instance;
  final lookupsSyncService = LookupsSyncService(
    lookupsDao: database.lookupsDao,
    onUnauthorized: () {
      authSignals.requireReauth(
        reason: 'Your session expired. Sign in to refresh offline catalogs.',
      );
    },
  );
  final syncConflictsSignals = SyncConflictsSignals(
    database.syncConflictsDao,
    pendingAttachmentsDao: database.pendingAttachmentsDao,
  );

  /*
  // Gene - Nov, 26, 2026: Wire WorkTimingHistoryDao into JobRepository and ServiceOrdersSignals.
  final jobRepository = JobRepository(
    database.jobOrdersDao,
    errorLog: database.syncErrorLogsDao,
    timingHistory: database.workTimingHistoryDao,
  );
  final lcpNapRepository = LcpNapRepository(database.lcpNapLocationsDao);
  final serviceOrdersSignals = ServiceOrdersSignals(
    dao: database.serviceOrdersDao,
    errorLog: database.syncErrorLogsDao,
    timingHistory: database.workTimingHistoryDao,
  );
  */
  final jobRepository = JobRepository(
    database.jobOrdersDao,
    errorLog: database.syncErrorLogsDao,
    timingHistory: database.workTimingHistoryDao,
    pendingAttachments: database.pendingAttachmentsDao,
    runInTransaction: database.writeTransaction,
  );
  final lcpNapRepository = LcpNapRepository(
    database.lcpNapLocationsDao,
    null,
    null,
    database.pendingAttachmentsDao,
    database.writeTransaction,
  );
  final serviceOrdersSignals = ServiceOrdersSignals(
    dao: database.serviceOrdersDao,
    errorLog: database.syncErrorLogsDao,
    timingHistory: database.workTimingHistoryDao,
    pendingAttachments: database.pendingAttachmentsDao,
    runInTransaction: database.writeTransaction,
  );

  // Gene - Nov, 28, 2026: Wire v12 DAOs and non-destructive 401 reauth callback into PowerSync connector.
  powerSync.setUploadHooks(
    errorLog: database.syncErrorLogsDao,
    pendingAttachments: database.pendingAttachmentsDao,
    syncConflicts: database.syncConflictsDao,
    localIdMap: database.localIdMapDao,
    onEntityUploaded: (table, entityId) {
      switch (table) {
        case 'job_orders':
          jobRepository.clearImagesCache(entityId);
          break;
        case 'service_orders':
          serviceOrdersSignals.clearImagesCache(entityId);
          break;
        case 'lcp_nap_locations':
          lcpNapRepository.invalidateImagesCache(entityId);
          break;
      }
    },
    onUnauthorized: () {
      authSignals.requireReauth(
        reason:
            'Your sync session expired. Sign in to resume uploading offline changes.',
      );
    },
  );

  // 2. Initialize Signals State Layer
  final jobsSignals = JobsSignals(jobRepository);
  final lcpNapSignals = LcpNapSignals(lcpNapRepository);

  // 3. Apply the technician's configured API base URL before any request is
  //    made, otherwise a URL saved in Settings is silently ignored after a
  //    restart and the app falls back to the compiled-in default.
  ApiClient.instance
      .setBaseUrl(await SecureStorageService.instance.getBaseUrl());

  // 4. Connect API client 401 callback to non-destructive in-place reauth (never wipe SQLite on 401).
  ApiClient.instance.onUnauthorized = () {
    /*
    authSignals.logout(
      reason: 'Your session expired. Please sign in again.',
    );
    */
    authSignals.requireReauth(
      reason: 'Your session expired. Sign in to continue syncing.',
    );
  };

  // 5. Restore display preferences and the active technician session
  await SettingsSignals.instance.restore();
  await authSignals.restoreSession();

  // 6. Initialize OS connectivity monitoring, best-effort background sync, and cached lookups refresh.
  NetworkConnectivityService.instance.initialize();
  NetworkConnectivityService.instance.addOnlineListener(() {
    if (authSignals.isAuthenticated.value) {
      unawaited(lookupsSyncService.sync());
    }
  });
  if (authSignals.isAuthenticated.value) {
    unawaited(lookupsSyncService.sync());
  }
  unawaited(BackgroundSyncService.initializeAndRegister());

  runApp(
    SwitchFiberTechApp(
      authSignals: authSignals,
      jobsSignals: jobsSignals,
      lcpNapSignals: lcpNapSignals,
      serviceOrdersSignals: serviceOrdersSignals,
      syncConflictsSignals: syncConflictsSignals,
      lookupsSyncService: lookupsSyncService,
      pendingAttachmentsDao: database.pendingAttachmentsDao,
      showSplash: true,
    ),
  );
}

class SwitchFiberTechApp extends StatelessWidget {
  final AuthSignals authSignals;
  final JobsSignals jobsSignals;
  final LcpNapSignals lcpNapSignals;
  final ServiceOrdersSignals? serviceOrdersSignals;
  final SyncConflictsSignals? syncConflictsSignals;
  final LookupsSyncService? lookupsSyncService;
  final PendingAttachmentsDao? pendingAttachmentsDao;
  final bool showSplash;

  const SwitchFiberTechApp({
    super.key,
    required this.authSignals,
    required this.jobsSignals,
    required this.lcpNapSignals,
    this.serviceOrdersSignals,
    this.syncConflictsSignals,
    this.lookupsSyncService,
    this.pendingAttachmentsDao,
    this.showSplash = true,
  });

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        return MaterialApp(
          // Gene - Oct 08, 2026: Updated MaterialApp title from 'Switch Fiber Tech' to 'SwitchFiber Tech'
          // title: 'Switch Fiber Tech',
          // Gene - Oct 09, 2026: Updated MaterialApp title to 'SF Tech' to match installed app label
          // title: 'SwitchFiber Tech',
          title: 'SF Tech',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: SettingsSignals.instance.themeMode.value,
          home: _RootView(
            authSignals: authSignals,
            jobsSignals: jobsSignals,
            lcpNapSignals: lcpNapSignals,
            serviceOrdersSignals: serviceOrdersSignals,
            syncConflictsSignals: syncConflictsSignals,
            lookupsSyncService: lookupsSyncService,
            pendingAttachmentsDao: pendingAttachmentsDao,
            showSplash: showSplash,
          ),
        );
      },
    );
  }
}

/// Root view that keeps authentication state as the single source of truth for
/// which screen is shown.
///
/// The splash is a one-shot gate in front of this; once it completes, the tree
/// below reacts to [AuthSignals.isAuthenticated], so signing in or signing out
/// swaps the screen without any imperative navigation.
class _RootView extends StatefulWidget {
  final AuthSignals authSignals;
  final JobsSignals jobsSignals;
  final LcpNapSignals lcpNapSignals;
  final ServiceOrdersSignals? serviceOrdersSignals;
  final SyncConflictsSignals? syncConflictsSignals;
  final LookupsSyncService? lookupsSyncService;
  final PendingAttachmentsDao? pendingAttachmentsDao;
  final bool showSplash;

  const _RootView({
    required this.authSignals,
    required this.jobsSignals,
    required this.lcpNapSignals,
    this.serviceOrdersSignals,
    this.syncConflictsSignals,
    this.lookupsSyncService,
    this.pendingAttachmentsDao,
    required this.showSplash,
  });

  @override
  State<_RootView> createState() => _RootViewState();
}

class _RootViewState extends State<_RootView> {
  late bool _splashComplete = !widget.showSplash;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: !_splashComplete
          ? SplashScreen(
              onComplete: () {
                if (mounted) setState(() => _splashComplete = true);
              },
            )
          : SignalBuilder(
              builder: (context) {
                final authenticated = widget.authSignals.isAuthenticated.value;
                if (!authenticated) {
                  return const LoginScreen();
                }
                return TechnicianShell(
                  authSignals: widget.authSignals,
                  jobsSignals: widget.jobsSignals,
                  lcpNapSignals: widget.lcpNapSignals,
                  serviceOrdersSignals: widget.serviceOrdersSignals,
                  syncConflictsSignals: widget.syncConflictsSignals,
                  lookupsSyncService: widget.lookupsSyncService,
                  pendingAttachmentsDao: widget.pendingAttachmentsDao,
                );
              },
            ),
    );
  }
}
