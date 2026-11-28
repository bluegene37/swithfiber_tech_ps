import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:powersync/powersync.dart' show SyncStatus;
import 'package:signals_flutter/signals_flutter.dart';
import '../../core/database/daos/pending_attachments_dao.dart';
import '../../core/network/network_connectivity_service.dart';
import '../../core/services/badge_service.dart';
import '../../core/sync/lookups_sync_service.dart';
// Gene - Nov, 27, 2026: Added PowerSyncService import to skip legacy REST polling timer when replicated sync is active.
import '../../core/sync/powersync_service.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../auth/signals/auth_signals.dart';
import '../auth/widgets/reauth_dialog.dart';
import '../diagnostics/screens/sync_conflicts_screen.dart';
import '../diagnostics/signals/sync_conflicts_signals.dart';
import '../jobs/models/job_order_model.dart';
import '../jobs/screens/job_order_detail_screen.dart';
import '../jobs/screens/job_orders_screen.dart';
import '../jobs/signals/jobs_signals.dart';
import '../lcp_nap/screens/lcp_nap_list_screen.dart';
import '../lcp_nap/signals/lcp_nap_signals.dart';
import '../reports/screens/create_report_screen.dart';
import '../reports/signals/report_signals.dart';
import '../service_orders/screens/service_orders_screen.dart';
import '../service_orders/signals/service_orders_signals.dart';
// Gene - Oct, 1, 2026: Added imports for ServiceOrderDto and ServiceOrderDetailScreen for service order alert navigation.
import '../service_orders/models/service_order_model.dart';
import '../service_orders/screens/service_order_detail_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../toolkit/screens/toolkit_screen.dart';

/// Main technician navigation shell: five bottom tabs, one shared bar on both
/// platforms (DESIGN.md, Navigation). There is no drawer, so nothing is reachable
/// by a hidden edge swipe.
class TechnicianShell extends StatefulWidget {
  final AuthSignals authSignals;
  final JobsSignals jobsSignals;
  final LcpNapSignals lcpNapSignals;
  final ServiceOrdersSignals? serviceOrdersSignals;
  final SyncConflictsSignals? syncConflictsSignals;
  final LookupsSyncService? lookupsSyncService;
  final PendingAttachmentsDao? pendingAttachmentsDao;
  final bool enableAutoSync;

  // Gene - Nov, 28, 2026: Accept optional SyncConflictsSignals, LookupsSyncService, and PendingAttachmentsDao for v12 conflict review, lookups refresh, and pending upload counters.
  const TechnicianShell({
    super.key,
    required this.authSignals,
    required this.jobsSignals,
    required this.lcpNapSignals,
    this.serviceOrdersSignals,
    this.syncConflictsSignals,
    this.lookupsSyncService,
    this.pendingAttachmentsDao,
    this.enableAutoSync = true,
  });

  @override
  State<TechnicianShell> createState() => _TechnicianShellState();
}

// class _TechnicianShellState extends State<TechnicianShell> {
// Gene - Oct, 3, 2026: Add WidgetsBindingObserver mixin to detect app resume and trigger immediate auto-sync without manual refresh.
class _TechnicianShellState extends State<TechnicianShell>
    with WidgetsBindingObserver {
  static const int _tabScheduled = 0;
  static const int _tabRepairs = 1;
  static const int _tabLcpNap = 2;
  static const int _tabToolkit = 3;
  static const int _tabSettings = 4;

  int _currentIndex = _tabScheduled;
  late final ReportSignals _reportSignals;
  late final ServiceOrdersSignals _serviceOrdersSignals;
  late final void Function() _disposeEmailSync;
  late final void Function() _removeOnlineListener;
  late final void Function() _disposeAlertEffect;
  // Gene - Oct 3, 2026: Disposer for reactive launcher icon badge count updates.
  late final void Function() _disposeBadgeEffect;
  void Function()? _disposeReauthEffect;
  StreamSubscription<SyncStatus>? _psStatusSub;
  StreamSubscription<int>? _attCountSub;
  bool _reauthDialogVisible = false;
  int _pendingUploadsCount = 0;
  int _pendingAttachmentCount = 0;
  Timer? _autoSyncTimer;
  Timer? _bannerDismissTimer;
  // Gene - Oct, 1, 2026: Added tracking for most recent alert between Job Orders and Service Orders.
  JobOrderDto? _lastSeenJobAlert;
  ServiceOrderDto? _lastSeenOrderAlert;
  bool _lastAlertIsJob = true;
  // Gene - Oct 3, 2026: Single-flight mutex and sync completion tracking to throttle auto-sync and prevent overlapping network storms.
  bool _isBackgroundSyncing = false;
  DateTime? _lastSyncCompletedAt;

  @override
  void initState() {
    super.initState();
    // Gene - Oct, 3, 2026: Register lifecycle observer for auto-sync on app resume.
    WidgetsBinding.instance.addObserver(this);
    _reportSignals = ReportSignals();
    _serviceOrdersSignals =
        widget.serviceOrdersSignals ?? ServiceOrdersSignals();
    // The job history is scoped to the signed-in technician's email. Kept in
    // sync reactively so a profile refresh that fills in the email (the login
    // response does not carry it) immediately unlocks the history.
    String? lastEmail;
    _disposeEmailSync = effect(() {
      final email = widget.authSignals.currentUser.value?.email.trim();
      widget.jobsSignals.setTechnicianEmail(email);
      // _serviceOrdersSignals.technicianEmail.value = email;
      // Gene - Oct, 1, 2026: Use setTechnicianEmail to reset snapshot cache when technician changes.
      _serviceOrdersSignals.setTechnicianEmail(email);
      // The activated history is fetched per technician, so the first time
      // the email becomes known (the login response lacks it) the jobs are
      // pulled again to fill it in.
      final becameKnown =
          (email?.isNotEmpty ?? false) && (lastEmail?.isEmpty ?? true);
      lastEmail = email;
      if (becameKnown) {
        // The one and only initial pull of job orders and repair tickets.
        // It waits for the email on purpose: a pull without it is not scoped to this
        // technician, and foreign records would otherwise conflict with PowerSync.
        widget.jobsSignals.fetchRemote(initial: true);
        _serviceOrdersSignals.fetchRemote(technicianEmail: email);
      }
    });
    // Initial fetch / local seed for plant sites. Runs here rather than at construction
    // time so that requests are only made once the technician is authenticated.
    // `initial` walks each screen through downloading -> skeleton -> data.
    widget.lcpNapSignals.fetchRemote(initial: true);
    // The login response carries no email, and the job history/repairs are matched on
    // it, so the full profile is pulled as soon as the shell appears rather
    // than only when the technician happens to open Settings.
    widget.authSignals.refreshProfile();

    // Reconnection listener: automatically triggers pending mutations sync
    // and remote cache refresh whenever connectivity is restored.
    /*
    NetworkConnectivityService.instance.initialize();
    */
    // Gene - Nov, 11, 2026: Avoid cancelling an already-initialized connectivity stream subscription when mounting TechnicianShell.
    if (!NetworkConnectivityService.instance.isInitialized) {
      NetworkConnectivityService.instance.initialize();
    }
    /*
    _removeOnlineListener =
        NetworkConnectivityService.instance.addOnlineListener(() async {
      await widget.jobsSignals.repository.syncWorker.syncPendingJobs();
      await _serviceOrdersSignals.syncWorker?.syncPendingOrders();
      await widget.jobsSignals.fetchRemote();
      await _serviceOrdersSignals.fetchRemote(
        technicianEmail: widget.authSignals.currentUser.value?.email,
      );
    });
    */
    // Gene - Nov, 11, 2026: Flush pending offline LCP NAP photo/GPS edits and refresh remote plant records automatically whenever network connectivity returns.
    _removeOnlineListener =
        NetworkConnectivityService.instance.addOnlineListener(() async {
      // Gene - Nov, 27, 2026: When PowerSync replicated mode is active, reconnect PowerSync & clear photo caches instead of legacy REST pulls/pushes.
      if (PowerSyncService.instance.isReplicatedMode) {
        unawaited(PowerSyncService.instance.connectIfConfigured());
        unawaited(widget.lookupsSyncService?.sync());
        widget.jobsSignals.repository.clearImagesCache();
        _serviceOrdersSignals.clearImagesCache();
        widget.lcpNapSignals.repository.invalidateImagesCache();
        await _refreshPendingUploadsCount();
        return;
      }
      unawaited(widget.lookupsSyncService?.sync());
      await widget.jobsSignals.repository.syncWorker.syncPendingJobs();
      await _serviceOrdersSignals.syncWorker?.syncPendingOrders();
      await widget.lcpNapSignals.syncPending();
      await widget.jobsSignals.fetchRemote();
      await _serviceOrdersSignals.fetchRemote(
        technicianEmail: widget.authSignals.currentUser.value?.email,
      );
      await widget.lcpNapSignals.fetchRemote();
    });

    /*
    // Periodic background auto-sync timer (every 30 seconds) ensuring
    // newly scheduled work orders and repair tickets are automatically refreshed
    // without requiring manual pull-to-refresh.
    if (widget.enableAutoSync) {
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (mounted && !widget.jobsSignals.isRefreshing.value) {
          await widget.jobsSignals.fetchRemote();
          await _serviceOrdersSignals.fetchRemote(
            technicianEmail: widget.authSignals.currentUser.value?.email,
          );
        }
      });
    }
    */
    // Gene - Oct, 3, 2026: Periodic auto-sync runs every 15s guarded by try-catch so network drops don't halt the timer, ensuring status hide/show transitions reflect automatically without manual refresh.
    // Gene - Nov, 27, 2026: Skip periodic 15s REST polling when live PowerSync streaming is active.
    if (widget.enableAutoSync && !PowerSyncService.instance.isReplicatedMode) {
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _triggerBackgroundSync();
      });
    }

    // Auto-dismiss the new job alert banner after 7 seconds.
    /*
    _disposeAlertEffect = effect(() {
      final alert = widget.jobsSignals.newJobAlert.value;
      _bannerDismissTimer?.cancel();
      if (alert != null) {
        _bannerDismissTimer = Timer(const Duration(seconds: 7), () {
          widget.jobsSignals.dismissAlert();
        });
      }
    });
    */
    // Gene - Oct, 1, 2026: Auto-dismiss alert banner for either Job Orders or Service Orders after 7 seconds.
    _disposeAlertEffect = effect(() {
      final jobAlert = widget.jobsSignals.newJobAlert.value;
      final orderAlert = _serviceOrdersSignals.newOrderAlert.value;
      if (jobAlert != null && jobAlert != _lastSeenJobAlert) {
        _lastSeenJobAlert = jobAlert;
        _lastAlertIsJob = true;
      }
      if (orderAlert != null && orderAlert != _lastSeenOrderAlert) {
        _lastSeenOrderAlert = orderAlert;
        _lastAlertIsJob = false;
      }
      _bannerDismissTimer?.cancel();
      if (jobAlert != null || orderAlert != null) {
        _bannerDismissTimer = Timer(const Duration(seconds: 7), () {
          widget.jobsSignals.dismissAlert();
          _serviceOrdersSignals.dismissAlert();
        });
      }
    });

    /*
    // Gene - Oct 3, 2026: Synchronize launcher icon badge count with total active open work (scheduled jobs + repair service orders).
    _disposeBadgeEffect = effect(() {
      final scheduled = widget.jobsSignals.scheduledCount.value;
      final repairs = _serviceOrdersSignals.totalCount.value;
      final totalOpen = scheduled + repairs;
      BadgeService.instance.updateBadgeCount(totalOpen).catchError((_) {});
    });
    */
    // Gene - Nov, 20, 2026: Synchronize launcher icon badge count with unread Today jobs and unread Repairs only.
    _disposeBadgeEffect = effect(() {
      final unreadScheduled = widget.jobsSignals.unreadScheduledCount.value;
      final unreadRepairs = _serviceOrdersSignals.unreadCount.value;
      final totalUnread = unreadScheduled + unreadRepairs;
      BadgeService.instance.updateBadgeCount(totalUnread).catchError((_) {});
    });

    // Gene - Nov, 28, 2026: Observe pending upload counts, 401 reauth prompts, and trigger lookups refresh on launch.
    if (PowerSyncService.instance.isInitialized &&
        PowerSyncService.instance.isReplicatedMode) {
      _psStatusSub = PowerSyncService.instance.statusStream?.listen((_) {
        unawaited(_refreshPendingUploadsCount());
      });
    }
    _attCountSub =
        widget.pendingAttachmentsDao?.watchPendingCount().listen((count) {
      if (mounted) {
        setState(() => _pendingAttachmentCount = count);
      }
      unawaited(_refreshPendingUploadsCount());
    });
    unawaited(_refreshPendingUploadsCount());
    unawaited(widget.lookupsSyncService?.sync());

    _disposeReauthEffect = effect(() {
      final needsReauth = widget.authSignals.reauthRequired.value;
      if (needsReauth) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showReauthDialogIfNeeded();
        });
      }
    });
  }

  Future<void> _refreshPendingUploadsCount() async {
    if (!PowerSyncService.instance.isInitialized ||
        !PowerSyncService.instance.isReplicatedMode) {
      return;
    }
    final count = await PowerSyncService.instance.countPendingUploads();
    if (mounted && count != _pendingUploadsCount) {
      setState(() => _pendingUploadsCount = count);
    }
  }

  Future<void> _showReauthDialogIfNeeded() async {
    if (!mounted ||
        _reauthDialogVisible ||
        !widget.authSignals.reauthRequired.value) {
      return;
    }
    _reauthDialogVisible = true;
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => ReauthDialog(authSignals: widget.authSignals),
      );
    } finally {
      _reauthDialogVisible = false;
    }
  }

  /*
  // Gene - Oct, 3, 2026: Centralized background sync method with try/catch to protect periodic timer and trigger immediately on app resume or tab selection.
  Future<void> _triggerBackgroundSync() async {
    if (!mounted) return;
    try {
      if (!widget.jobsSignals.isRefreshing.value) {
        await widget.jobsSignals.fetchRemote();
      }
      if (!_serviceOrdersSignals.isSyncing.value) {
        await _serviceOrdersSignals.fetchRemote(
          technicianEmail: widget.authSignals.currentUser.value?.email,
        );
      }
    } catch (_) {
      // Ignored: silent background refresh
    }
  }
  */
  // Gene - Oct 3, 2026: Single-flight coordinator with cooldown to prevent network storms, race conditions, and duplicate simultaneous syncs.
  Future<void> _triggerBackgroundSync({bool force = false}) async {
    if (!mounted || _isBackgroundSyncing) return;
    final now = DateTime.now();
    if (!force &&
        _lastSyncCompletedAt != null &&
        now.difference(_lastSyncCompletedAt!) < const Duration(seconds: 10)) {
      return;
    }
    _isBackgroundSyncing = true;
    try {
      // Gene - Nov, 27, 2026: In replicated PowerSync mode, verify stream connection & clear image caches instead of pulling via legacy REST APIs.
      if (PowerSyncService.instance.isReplicatedMode) {
        unawaited(PowerSyncService.instance.connectIfConfigured());
        unawaited(widget.lookupsSyncService?.sync());
        widget.jobsSignals.repository.clearImagesCache();
        _serviceOrdersSignals.clearImagesCache();
        widget.lcpNapSignals.repository.invalidateImagesCache();
        unawaited(_refreshPendingUploadsCount());
        _lastSyncCompletedAt = DateTime.now();
        return;
      }
      unawaited(widget.lookupsSyncService?.sync());
      if (!widget.jobsSignals.isRefreshing.value) {
        await widget.jobsSignals.fetchRemote();
      }
      final email = widget.authSignals.currentUser.value?.email.trim();
      if (!_serviceOrdersSignals.isSyncing.value &&
          email != null &&
          email.isNotEmpty) {
        await _serviceOrdersSignals.fetchRemote(
          technicianEmail: email,
        );
      }
      // Gene - Nov, 8, 2026: Also auto-sync LCP NAP plant locations during background sync cycles.
      if (!widget.lcpNapSignals.isLoading.value) {
        await widget.lcpNapSignals.fetchRemote();
      }
      _lastSyncCompletedAt = DateTime.now();
    } catch (_) {
      // Ignored: silent background refresh
    } finally {
      _isBackgroundSyncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerBackgroundSync(force: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      /*
      // Gene - Oct 3, 2026: Update launcher icon badge count when app is minimized, closed, or paused.
      final scheduled = widget.jobsSignals.scheduledCount.value;
      final repairs = _serviceOrdersSignals.totalCount.value;
      BadgeService.instance
          .updateBadgeCount(scheduled + repairs)
          .catchError((_) {});
      */
      // Gene - Nov, 20, 2026: Update launcher icon badge count with unread Today and Repairs items when backgrounded.
      final unreadScheduled = widget.jobsSignals.unreadScheduledCount.value;
      final unreadRepairs = _serviceOrdersSignals.unreadCount.value;
      BadgeService.instance
          .updateBadgeCount(unreadScheduled + unreadRepairs)
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    // Gene - Oct, 3, 2026: Unregister lifecycle observer on disposal.
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _bannerDismissTimer?.cancel();
    _disposeAlertEffect();
    // Gene - Oct 3, 2026: Dispose launcher badge effect.
    _disposeBadgeEffect();
    _disposeReauthEffect?.call();
    _psStatusSub?.cancel();
    _attCountSub?.cancel();
    _removeOnlineListener();
    _disposeEmailSync();
    if (widget.serviceOrdersSignals == null) {
      _serviceOrdersSignals.dispose();
    }
    super.dispose();
  }

  /// Opens the on-site report for a job order as its own page, rather than a
  /// separate tab: a report only ever belongs to a job.
  /*
  void _openReportForJob(JobOrderDto job) {
    _reportSignals.setJobOrder(job);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: widget.jobsSignals,
          reportSignals: _reportSignals,
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Guarded _openReportForJob so rescheduled jobs cannot open report screen or modify records.
  // Gene - Nov, 26, 2026: Require active Start work timing unlock before opening completion report or pushing alert details.
  void _openReportForJob(JobOrderDto job) {
    // Gene - Nov 07, 2026: Wrapped single-line if statement in curly braces for linter compliance (curly_braces_in_flow_control_structures).
    // if (job.isRescheduled || job.siteException == SiteException.reschedule)
    //   return;
    /*
    if (job.isRescheduled || job.siteException == SiteException.reschedule) {
      return;
    }
    */
    if (!job.isWorkUnlocked ||
        job.isRescheduled ||
        job.siteException == SiteException.reschedule) {
      return;
    }
    _reportSignals.setJobOrder(job);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: widget.jobsSignals,
          reportSignals: _reportSignals,
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  /*
  void _viewAlertJob(JobOrderDto job) {
    widget.jobsSignals.dismissAlert();
    if (_currentIndex != _tabScheduled) {
      setState(() => _currentIndex = _tabScheduled);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobOrderDetailScreen(
          jobId: job.id,
          jobsSignals: widget.jobsSignals,
          lcpNapSignals: widget.lcpNapSignals,
          onOpenReport: _openReportForJob,
        ),
      ),
    );
  }
  */
  // Gene - Nov, 20, 2026: Mark job as read when opened from the top dispatch alert banner.
  void _viewAlertJob(JobOrderDto job) {
    widget.jobsSignals.markJobAsRead(job.id);
    widget.jobsSignals.dismissAlert();
    if (_currentIndex != _tabScheduled) {
      setState(() => _currentIndex = _tabScheduled);
    }
    // Gene - Nov, 26, 2026: Land on Today list instead of pushing unstarted JobOrderDetailScreen.
    if (job.canActivate && !job.isTimingInProgress) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobOrderDetailScreen(
          jobId: job.id,
          jobsSignals: widget.jobsSignals,
          lcpNapSignals: widget.lcpNapSignals,
          onOpenReport: _openReportForJob,
        ),
      ),
    );
  }

  /*
  // Gene - Oct, 1, 2026: Navigates to ServiceOrderDetailScreen from service order alert banner and switches tab to Repairs.
  void _viewAlertServiceOrder(ServiceOrderDto order) {
    _serviceOrdersSignals.dismissAlert();
    if (_currentIndex != _tabRepairs) {
      setState(() => _currentIndex = _tabRepairs);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceOrderDetailScreen(
          orderId: order.id,
          signals: _serviceOrdersSignals,
        ),
      ),
    );
  }
  */
  // Gene - Nov, 20, 2026: Mark service order as read when opened from the top repair alert banner.
  void _viewAlertServiceOrder(ServiceOrderDto order) {
    _serviceOrdersSignals.markOrderAsRead(order.id);
    _serviceOrdersSignals.dismissAlert();
    if (_currentIndex != _tabRepairs) {
      setState(() => _currentIndex = _tabRepairs);
    }
    // Gene - Nov, 26, 2026: Land on Repairs list instead of pushing unstarted ServiceOrderDetailScreen.
    if (order.isOpen && !order.isTimingInProgress) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceOrderDetailScreen(
          orderId: order.id,
          signals: _serviceOrdersSignals,
          lcpNapSignals: widget.lcpNapSignals,
          jobsSignals: widget.jobsSignals,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.jobsSignals;
    final auth = widget.authSignals;

    final screens = [
      JobOrdersScreen(
        jobsSignals: jobs,
        authSignals: auth,
        lcpNapSignals: widget.lcpNapSignals,
        serviceOrdersSignals: _serviceOrdersSignals,
        onSelectJobForReport: _openReportForJob,
      ),
      /*
      ServiceOrdersScreen(
        signals: _serviceOrdersSignals,
      ),
      LcpNapListScreen(signals: widget.lcpNapSignals),
      const ToolkitScreen(),
      SettingsScreen(
        authSignals: auth,
        jobsSignals: jobs,
      ),
      */
      // Gene - Nov, 23, 2026: Wire cross-feature signals into Repairs, Plant, and Me for port occupancy, pole deep links, and combined sync queue.
      ServiceOrdersScreen(
        signals: _serviceOrdersSignals,
        lcpNapSignals: widget.lcpNapSignals,
        jobsSignals: jobs,
      ),
      LcpNapListScreen(
        signals: widget.lcpNapSignals,
        jobsSignals: jobs,
        serviceOrdersSignals: _serviceOrdersSignals,
      ),
      const ToolkitScreen(),
      SettingsScreen(
        authSignals: auth,
        jobsSignals: jobs,
        serviceOrdersSignals: _serviceOrdersSignals,
        lcpNapSignals: widget.lcpNapSignals,
        syncConflictsSignals: widget.syncConflictsSignals,
        lookupsSyncService: widget.lookupsSyncService,
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SignalBuilder(
        builder: (context) {
          final hasStrip = _hasSyncStatusStrip();
          return Column(
            children: [
              _buildSyncStatusStrip(context, isDark),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: hasStrip,
                  child: Stack(
                    children: [
                      screens[_currentIndex],
                      _buildNewJobAlertBanner(context),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildIosBottomBar(context, jobs, isDark),
    );
  }

  bool _hasSyncStatusStrip() {
    final conflictsCount =
        widget.syncConflictsSignals?.unresolvedCount.value ?? 0;
    final needsReauth = widget.authSignals.reauthRequired.value;
    final localPending = widget.jobsSignals.unsyncedCount.value +
        _serviceOrdersSignals.allOrders.value.where((o) => !o.isSynced).length +
        widget.lcpNapSignals.unsyncedCount.value;
    final pendingUploads = PowerSyncService.instance.isReplicatedMode
        ? (_pendingUploadsCount > _pendingAttachmentCount
            ? _pendingUploadsCount
            : _pendingAttachmentCount)
        : localPending;
    return conflictsCount > 0 || pendingUploads > 0 || needsReauth;
  }

  Widget _buildSyncStatusStrip(BuildContext context, bool isDark) {
    return SignalBuilder(
      builder: (context) {
        final conflictsCount =
            widget.syncConflictsSignals?.unresolvedCount.value ?? 0;
        final needsReauth = widget.authSignals.reauthRequired.value;
        final localPending = widget.jobsSignals.unsyncedCount.value +
            _serviceOrdersSignals.allOrders.value
                .where((o) => !o.isSynced)
                .length +
            widget.lcpNapSignals.unsyncedCount.value;
        final pendingUploads = PowerSyncService.instance.isReplicatedMode
            ? (_pendingUploadsCount > _pendingAttachmentCount
                ? _pendingUploadsCount
                : _pendingAttachmentCount)
            : localPending;

        if (conflictsCount <= 0 && pendingUploads <= 0 && !needsReauth) {
          return const SizedBox.shrink();
        }

        final topPad = MediaQuery.paddingOf(context).top;
        return Material(
          color: AppTheme.cardOf(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, topPad + 4, 12, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (needsReauth)
                  InkWell(
                    key: const ValueKey('reauth_banner'),
                    onTap: _showReauthDialogIfNeeded,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.dangerInkOf(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.lock_fill,
                            size: 20,
                            color: AppTheme.dangerInkOf(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Session expired — tap to sign in and resume syncing',
                              style: context.text.labelMedium!.copyWith(
                                color: AppTheme.dangerInkOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (conflictsCount > 0 && widget.syncConflictsSignals != null)
                  InkWell(
                    key: const ValueKey('needs_review_banner'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SyncConflictsScreen(
                            signals: widget.syncConflictsSignals!,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warningSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.warningInkOf(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_octagon_fill,
                            size: 20,
                            color: AppTheme.warningInkOf(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$conflictsCount conflict${conflictsCount == 1 ? '' : 's'} — Needs Review',
                              style: context.text.labelMedium!.copyWith(
                                color: AppTheme.warningInkOf(context),
                              ),
                            ),
                          ),
                          Text(
                            'Review',
                            style: context.text.labelLarge!.copyWith(
                              color: AppTheme.warningInkOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (pendingUploads > 0)
                  Container(
                    key: const ValueKey('pending_uploads_pill'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.fillOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.hairlineOf(context)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.cloud_upload,
                          size: 20,
                          color: AppTheme.infoInkOf(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$pendingUploads pending upload${pendingUploads == 1 ? '' : 's'}',
                            style: context.text.labelMedium!.copyWith(
                              color: AppTheme.inkOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /*
  Widget _buildNewJobAlertBanner(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final job = widget.jobsSignals.newJobAlert.value;
        if (job == null) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final topPadding = MediaQuery.paddingOf(context).top;

        return Positioned(
          top: topPadding + 10,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.bell_fill,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'NEW DISPATCH',
                                style: context.text.labelSmall!.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                job.ticketNumber,
                                style: context.text.labelMedium!.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          job.customerName,
                          style: context.text.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (job.address.isNotEmpty)
                          Text(
                            [
                              job.address,
                              if (job.barangay?.isNotEmpty == true)
                                job.barangay!,
                            ].join(', '),
                            style: context.text.bodySmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _viewAlertJob(job),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      'View',
                      style: context.text.labelLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    color: AppTheme.secondaryInkOf(context),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Dismiss',
                    onPressed: widget.jobsSignals.dismissAlert,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  */
  // Gene - Oct, 1, 2026: Enhanced alert banner to display either New Dispatch (Job Order) or New Service Order with direct View navigation and auto-dismiss.
  Widget _buildNewJobAlertBanner(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final job = widget.jobsSignals.newJobAlert.value;
        final order = _serviceOrdersSignals.newOrderAlert.value;
        if (job == null && order == null) return const SizedBox.shrink();

        final isJob =
            (_lastAlertIsJob && job != null) || (order == null && job != null);
        final currentOrder = isJob ? null : order;
        final currentJob = isJob ? job : null;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final topPadding = MediaQuery.paddingOf(context).top;

        final badgeTitle = isJob ? 'NEW DISPATCH' : 'NEW SERVICE ORDER';
        final ticketOrAccount = isJob
            ? currentJob!.ticketNumber
            : (currentOrder!.accountNumber.isNotEmpty
                ? currentOrder.accountNumber
                : 'SO #${currentOrder.id}');
        final clientName =
            isJob ? currentJob!.customerName : currentOrder!.fullName;
        final subtitleText = isJob
            ? [
                currentJob!.address,
                if (currentJob.barangay?.isNotEmpty == true)
                  currentJob.barangay!,
              ].join(', ')
            : [
                currentOrder!.concern,
                if (currentOrder.address.isNotEmpty) currentOrder.address,
              ].join(' • ');

        return Positioned(
          top: topPadding + 10,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isJob
                          ? CupertinoIcons.bell_fill
                          : CupertinoIcons.wrench_fill,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badgeTitle,
                                style: context.text.labelSmall!.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                ticketOrAccount,
                                style: context.text.labelMedium!.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          clientName,
                          style: context.text.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleText.isNotEmpty)
                          Text(
                            subtitleText,
                            style: context.text.bodySmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: isJob
                        ? () => _viewAlertJob(currentJob!)
                        : () => _viewAlertServiceOrder(currentOrder!),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      'View',
                      style: context.text.labelLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    color: AppTheme.secondaryInkOf(context),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Dismiss',
                    onPressed: isJob
                        ? widget.jobsSignals.dismissAlert
                        : _serviceOrdersSignals.dismissAlert,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// iOS Apple HIG Translucent/Frosted Glass Bottom Tab Bar
  Widget _buildIosBottomBar(
      BuildContext context, JobsSignals jobs, bool isDark) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final barBg = isDark ? const Color(0xEB161F30) : const Color(0xF8FFFFFF);
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: barBg,
            border: Border(
              top: BorderSide(color: borderColor, width: 0.5),
            ),
          ),
          padding: EdgeInsets.only(
            top: 7,
            bottom: bottomPadding > 0 ? bottomPadding : 7,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              /*
              // 1. Scheduled Job Orders
              _buildIosTabItem(
                index: _tabScheduled,
                icon: CupertinoIcons.calendar,
                activeIcon: CupertinoIcons.calendar_today,
                label: 'Today',
                badgeSignal: jobs.scheduledCount,
                badgeColor: AppTheme.primary,
                isDark: isDark,
              ),

              // 2. Service & Repair Tickets
              _buildIosTabItem(
                index: _tabRepairs,
                icon: CupertinoIcons.hammer,
                activeIcon: CupertinoIcons.hammer_fill,
                label: 'Repairs',
                badgeSignal: _serviceOrdersSignals.totalCount,
                badgeColor: AppTheme.warning,
                isDark: isDark,
              ),

              // 3. LCP NAP Plant Sites
              _buildIosTabItem(
                index: _tabLcpNap,
                icon: CupertinoIcons.map,
                activeIcon: CupertinoIcons.map_fill,
                label: 'Plant',
                badgeSignal: widget.lcpNapSignals.totalSitesCount,
                badgeColor: AppTheme.info,
                isDark: isDark,
              ),
              */
              // Gene - Nov, 20, 2026: Show only unread counts on Today and Repairs bubbles, and remove the count bubble from Plant.
              // 1. Scheduled Job Orders
              _buildIosTabItem(
                index: _tabScheduled,
                icon: CupertinoIcons.calendar,
                activeIcon: CupertinoIcons.calendar_today,
                label: 'Today',
                badgeSignal: jobs.unreadScheduledCount,
                badgeColor: AppTheme.primary,
                isDark: isDark,
              ),

              // 2. Service & Repair Tickets
              _buildIosTabItem(
                index: _tabRepairs,
                icon: CupertinoIcons.hammer,
                activeIcon: CupertinoIcons.hammer_fill,
                label: 'Repairs',
                badgeSignal: _serviceOrdersSignals.unreadCount,
                badgeColor: AppTheme.warning,
                isDark: isDark,
              ),

              // 3. LCP NAP Plant Sites
              _buildIosTabItem(
                index: _tabLcpNap,
                icon: CupertinoIcons.map,
                activeIcon: CupertinoIcons.map_fill,
                label: 'Plant',
                isDark: isDark,
              ),

              // 4. Technician Toolkit
              _buildIosTabItem(
                index: _tabToolkit,
                icon: CupertinoIcons.wrench,
                activeIcon: CupertinoIcons.wrench_fill,
                label: 'Tools',
                isDark: isDark,
              ),

              // 5. Settings & Terminal Diagnostics
              _buildIosTabItem(
                index: _tabSettings,
                icon: CupertinoIcons.person,
                activeIcon: CupertinoIcons.person_fill,
                label: 'Me',
                badgeSignal: jobs.unsyncedCount,
                badgeColor: AppTheme.warning,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIosTabItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
    ReadonlySignal<int>? badgeSignal,
    Color? badgeColor,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = AppTheme.brandInkOf(context);
    final inactiveColor =
        isDark ? AppTheme.textSecondaryDark : AppTheme.secondaryInk;

    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          /*
          onTap: () {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
            }
          },
          */
          /*
          onTap: () {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
              _triggerBackgroundSync();
            } else if (index == _tabScheduled || index == _tabRepairs) {
              _triggerBackgroundSync();
            }
          },
          */
          /*
          // Gene - Oct 3, 2026: Pass force: true on user tap to bypass throttling cooldown while respecting the single-flight lock.
          onTap: () {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
              _triggerBackgroundSync(force: true);
            } else if (index == _tabScheduled || index == _tabRepairs) {
              _triggerBackgroundSync(force: true);
            }
          },
          */
          // Gene - Nov, 11, 2026: Include _tabLcpNap (Plant) when re-tapping active tab so technicians can trigger immediate plant & photo sync.
          onTap: () {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
              _triggerBackgroundSync(force: true);
            } else if (index == _tabScheduled ||
                index == _tabRepairs ||
                index == _tabLcpNap) {
              _triggerBackgroundSync(force: true);
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isSelected ? activeIcon : icon,
                      size: 22,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                    if (badgeSignal != null)
                      Positioned(
                        top: -4,
                        right: -10,
                        child: SignalBuilder(
                          builder: (context) {
                            final count = badgeSignal.value;
                            if (count <= 0) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor ?? AppTheme.primary,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: context.text.labelSmall!
                                    .copyWith(color: Colors.white),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: context.text.labelSmall!.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.brandInkOf(context)
                        : AppTheme.secondaryInkOf(context),
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
