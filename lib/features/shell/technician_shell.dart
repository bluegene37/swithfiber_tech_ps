import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../core/network/network_connectivity_service.dart';
import '../../core/services/badge_service.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../auth/signals/auth_signals.dart';
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
  final bool enableAutoSync;

  const TechnicianShell({
    super.key,
    required this.authSignals,
    required this.jobsSignals,
    required this.lcpNapSignals,
    this.serviceOrdersSignals,
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
    NetworkConnectivityService.instance.initialize();
    _removeOnlineListener =
        NetworkConnectivityService.instance.addOnlineListener(() async {
      await widget.jobsSignals.repository.syncWorker.syncPendingJobs();
      await _serviceOrdersSignals.syncWorker?.syncPendingOrders();
      await widget.jobsSignals.fetchRemote();
      await _serviceOrdersSignals.fetchRemote(
        technicianEmail: widget.authSignals.currentUser.value?.email,
      );
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
    if (widget.enableAutoSync) {
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

    // Gene - Oct 3, 2026: Synchronize launcher icon badge count with total active open work (scheduled jobs + repair service orders).
    _disposeBadgeEffect = effect(() {
      final scheduled = widget.jobsSignals.scheduledCount.value;
      final repairs = _serviceOrdersSignals.totalCount.value;
      final totalOpen = scheduled + repairs;
      BadgeService.instance.updateBadgeCount(totalOpen).catchError((_) {});
    });
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
      // Gene - Oct 3, 2026: Update launcher icon badge count when app is minimized, closed, or paused.
      final scheduled = widget.jobsSignals.scheduledCount.value;
      final repairs = _serviceOrdersSignals.totalCount.value;
      BadgeService.instance
          .updateBadgeCount(scheduled + repairs)
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
  void _openReportForJob(JobOrderDto job) {
    if (job.isRescheduled || job.siteException == SiteException.reschedule) return;
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
      ServiceOrdersScreen(
        signals: _serviceOrdersSignals,
      ),
      LcpNapListScreen(signals: widget.lcpNapSignals),
      const ToolkitScreen(),
      SettingsScreen(
        authSignals: auth,
        jobsSignals: jobs,
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          screens[_currentIndex],
          _buildNewJobAlertBanner(context),
        ],
      ),
      bottomNavigationBar: _buildIosBottomBar(context, jobs, isDark),
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
