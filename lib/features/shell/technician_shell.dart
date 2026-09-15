import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../auth/signals/auth_signals.dart';
import '../jobs/models/job_order_model.dart';
import '../jobs/screens/job_orders_screen.dart';
import '../jobs/signals/jobs_signals.dart';
import '../lcp_nap/screens/lcp_nap_list_screen.dart';
import '../lcp_nap/signals/lcp_nap_signals.dart';
import '../reports/screens/create_report_screen.dart';
import '../reports/signals/report_signals.dart';
import '../service_orders/screens/service_orders_screen.dart';
import '../service_orders/signals/service_orders_signals.dart';
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

  const TechnicianShell({
    super.key,
    required this.authSignals,
    required this.jobsSignals,
    required this.lcpNapSignals,
    this.serviceOrdersSignals,
  });

  @override
  State<TechnicianShell> createState() => _TechnicianShellState();
}

class _TechnicianShellState extends State<TechnicianShell> {
  static const int _tabScheduled = 0;
  static const int _tabRepairs = 1;
  static const int _tabLcpNap = 2;
  static const int _tabToolkit = 3;
  static const int _tabSettings = 4;

  int _currentIndex = _tabScheduled;
  late final ReportSignals _reportSignals;
  late final ServiceOrdersSignals _serviceOrdersSignals;
  late final void Function() _disposeEmailSync;

  @override
  void initState() {
    super.initState();
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
      _serviceOrdersSignals.technicianEmail.value = email;
      // The activated history is fetched per technician, so the first time
      // the email becomes known (the login response lacks it) the jobs are
      // pulled again to fill it in.
      final becameKnown =
          (email?.isNotEmpty ?? false) && (lastEmail?.isEmpty ?? true);
      lastEmail = email;
      if (becameKnown) {
        // The one and only initial pull of job orders. It waits for the
        // email on purpose: a pull without it is not scoped to this
        // technician, and the repository refuses to make one.
        widget.jobsSignals.fetchRemote(initial: true);
        _serviceOrdersSignals.fetchRemote();
      }
    });
    // Initial fetch / local seed. Runs here rather than at construction time so
    // that requests are only made once the technician is authenticated.
    // `initial` walks each screen through downloading -> skeleton -> data.
    widget.lcpNapSignals.fetchRemote(initial: true);
    _serviceOrdersSignals.fetchRemote();
    // The login response carries no email, and the job history is matched on
    // it, so the full profile is pulled as soon as the shell appears rather
    // than only when the technician happens to open Settings.
    widget.authSignals.refreshProfile();
  }

  @override
  void dispose() {
    _disposeEmailSync();
    if (widget.serviceOrdersSignals == null) {
      _serviceOrdersSignals.dispose();
    }
    super.dispose();
  }

  /// Opens the on-site report for a job order as its own page, rather than a
  /// separate tab: a report only ever belongs to a job.
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
      body: screens[_currentIndex],
      bottomNavigationBar: _buildIosBottomBar(context, jobs, isDark),
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
          onTap: () {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
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
