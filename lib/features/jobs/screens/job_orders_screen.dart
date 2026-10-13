import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Gene - Oct 8, 2026: Added intl import for date group formatting on the Jobs list.
import 'package:intl/intl.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/loading_states.dart';
import '../../../core/widgets/status_rail_row.dart';
import '../../auth/signals/auth_signals.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../../service_orders/signals/service_orders_signals.dart';
import '../models/job_order_model.dart';
import '../signals/jobs_signals.dart';
import '../widgets/job_history_view.dart';
import '../widgets/job_navigation.dart';
import '../widgets/jobs_map_view.dart';
import '../widgets/job_contact.dart';
import '../widgets/today_glance_panel.dart';
import 'job_order_detail_screen.dart';
// Gene - Oct 13, 2026: Added imports for direct report creation shortcut from Job Orders list.
import '../../reports/screens/create_report_screen.dart';
import '../../reports/signals/report_signals.dart';

// Gene - Oct 13, 2026: Added JobGrouping enum to support grouping jobs by Date or Barangay.
enum JobGrouping { date, barangay }

/// The Today home (DESIGN.md, Screen placement): the technician's day on one
/// glance. A read-only panel at the top, the next job lifted with the
/// screen's one red verb, then plain rows. Done jobs sit behind a toggle,
/// search behind its icon, the map behind its icon. No app bar.
///
/// Keeps its old class name because the shell and the tablet master-detail
/// layout are built around it.
class JobOrdersScreen extends StatefulWidget {
  final JobsSignals jobsSignals;
  final AuthSignals? authSignals;
  final LcpNapSignals? lcpNapSignals;
  final ServiceOrdersSignals? serviceOrdersSignals;
  final void Function(JobOrderDto job)? onSelectJobForDetails;
  final void Function(JobOrderDto job)? onSelectJobForReport;

  const JobOrdersScreen({
    super.key,
    required this.jobsSignals,
    this.authSignals,
    this.lcpNapSignals,
    this.serviceOrdersSignals,
    this.onSelectJobForDetails,
    this.onSelectJobForReport,
  });

  /// `4 jobs · 1 done today · next Batingan`
  static String summaryLine({
    required int scheduled,
    required int doneToday,
    required JobOrderDto? next,
  }) {
    final jobs = scheduled == 0
        ? 'No scheduled jobs'
        : '$scheduled ${scheduled == 1 ? 'job' : 'jobs'}';
    final done = '$doneToday done today';
    final where = next == null
        ? null
        : (next.barangay?.isNotEmpty == true
            ? next.barangay!
            : (next.city?.isNotEmpty == true ? next.city! : null));
    return [jobs, done, if (where != null) 'next $where'].join(' · ');
  }

  /// Exposed for testing and queue calculation.
  static JobOrderDto pickNext(List<JobOrderDto> jobs) =>
      _JobOrdersScreenState.pickNext(jobs);

  // Gene - Oct 8, 2026: Exposed dateGroupLabel to format date headers (e.g. 'Today · Oct 8, 2026' or 'Oct 9, 2026').
  static String dateGroupLabel(DateTime? date, {int? count}) =>
      _JobOrdersScreenState.dateGroupLabel(date, count: count);


  @override
  State<JobOrdersScreen> createState() => _JobOrdersScreenState();
}

class _JobOrdersScreenState extends State<JobOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showDone = false;
  bool _showMap = false;
  bool _showSearch = false;
  int? _selectedJobId;
  // Gene - Oct 13, 2026: Added _grouping state to toggle grouping by date vs barangay.
  JobGrouping _grouping = JobGrouping.date;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(JobOrderDto job) {
    if (widget.onSelectJobForDetails != null) {
      widget.onSelectJobForDetails!(job);
      return;
    }

    final isTablet = MediaQuery.sizeOf(context).width >= 768;
    if (isTablet) {
      setState(() => _selectedJobId = job.id);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobOrderDetailScreen(
          jobId: job.id,
          jobsSignals: widget.jobsSignals,
          lcpNapSignals: widget.lcpNapSignals,
          onOpenReport: widget.onSelectJobForReport,
          readOnly: _showDone,
        ),
      ),
    );
  }

  // Gene - Oct 13, 2026: Opens the completion report directly from the Job Orders list card shortcut.
  /*
  void _openReport(JobOrderDto job) {
    if (widget.onSelectJobForReport != null) {
      widget.onSelectJobForReport!(job);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: widget.jobsSignals,
          reportSignals: ReportSignals()..setJobOrder(job),
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Guarded _openReport so rescheduled jobs cannot open the report screen or modify records.
  void _openReport(JobOrderDto job) {
    if (job.isRescheduled || job.siteException == SiteException.reschedule) return;
    if (widget.onSelectJobForReport != null) {
      widget.onSelectJobForReport!(job);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: widget.jobsSignals,
          reportSignals: ReportSignals()..setJobOrder(job),
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        widget.jobsSignals.setSearch('');
      }
    });
  }

  Future<void> _syncNow(BuildContext context, JobsSignals signals) async {
    final result = await signals.repository.syncWorker.syncPendingJobs();
    await signals.fetchRemote();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.failedCount == 0 ? 'Synced with the server.' : result.message,
        ),
      ),
    );
  }

  /// The nearest scheduled job when the phone has a fix, else the first.
  /// Prioritizes active scheduled/in-progress jobs over rescheduled jobs.
  static JobOrderDto pickNext(List<JobOrderDto> jobs) {
    final active = jobs.where((j) => !j.isRescheduled).toList();
    final candidates = active.isNotEmpty ? active : jobs;

    JobOrderDto best = candidates.first;
    double? bestMeters;
    for (final job in candidates) {
      final meters = distanceMetersFor(job);
      if (meters == null) continue;
      if (bestMeters == null || meters < bestMeters) {
        best = job;
        bestMeters = meters;
      }
    }
    return best;
  }

  static bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    final local = d.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  // Gene - Oct 8, 2026: Formats a date into a human-readable section label (e.g. 'Today · Oct 8, 2026', 'Tomorrow · Oct 9, 2026', etc.).
  static final DateFormat _groupDateFormat = DateFormat('MMM d, yyyy');

  static String dateGroupLabel(DateTime? date, {int? count}) {
    if (date == null) return 'No Scheduled Date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    final formatted = _groupDateFormat.format(date);
    final String dayPrefix;
    if (diff == 0) {
      dayPrefix = 'Today · $formatted';
    } else if (diff == 1) {
      dayPrefix = 'Tomorrow · $formatted';
    } else if (diff == -1) {
      dayPrefix = 'Yesterday · $formatted';
    } else {
      dayPrefix = formatted;
    }

    if (count != null && count > 1) {
      return '$dayPrefix ($count jobs)';
    }
    return dayPrefix;
  }


  @override
  Widget build(BuildContext context) {
    final signals = widget.jobsSignals;
    final isTablet = MediaQuery.sizeOf(context).width >= 768;
    final master = _buildMaster(context, signals);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: isTablet
            ? Row(
                children: [
                  SizedBox(width: 380, child: master),
                  VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppTheme.hairlineOf(context)),
                  Expanded(
                    child: _selectedJobId != null
                        ? JobOrderDetailScreen(
                            key: ValueKey(_selectedJobId),
                            jobId: _selectedJobId!,
                            jobsSignals: widget.jobsSignals,
                            lcpNapSignals: widget.lcpNapSignals,
                            onOpenReport: widget.onSelectJobForReport,
                            readOnly: _showDone,
                            automaticallyImplyLeading: false,
                          )
                        : _buildNoJobSelectedPlaceholder(context),
                  ),
                ],
              )
            : master,
      ),
    );
  }

  Widget _buildMaster(BuildContext context, JobsSignals signals) {
    return Column(
      children: [
        SignalBuilder(
          builder: (context) {
            final scheduled = signals.filteredJobs.value;
            final scheduledCount = signals.scheduledCount.value;
            final doneToday = signals.assignedJobs.value
                .where((j) => j.isHistory && _isToday(j.historyDate))
                .length;
            final next = scheduled.isEmpty ? null : pickNext(scheduled);
            final pending = signals.unsyncedCount.value;
            final syncing = signals.repository.syncWorker.isSyncing.value ||
                signals.isRefreshing.value;

            return TodayGlancePanel(
              jobCount: scheduledCount,
              summary: JobOrdersScreen.summaryLine(
                scheduled: scheduledCount,
                doneToday: doneToday,
                next: next,
              ),
              actions: [
                IconButton(
                  tooltip: _showSearch ? 'Hide search' : 'Search jobs',
                  isSelected: _showSearch,
                  onPressed: _toggleSearch,
                  icon: const Icon(CupertinoIcons.search),
                ),
                IconButton(
                  tooltip: _showMap ? 'Show list' : 'Show map',
                  isSelected: _showMap,
                  onPressed: () => setState(() {
                    _showMap = !_showMap;
                    if (_showMap) _showDone = false;
                  }),
                  icon: Icon(_showMap
                      ? CupertinoIcons.list_bullet
                      : CupertinoIcons.map),
                ),
                IconButton(
                  tooltip: 'Sync & refresh queue',
                  onPressed: syncing ? null : () => _syncNow(context, signals),
                  icon: Badge(
                    isLabelVisible: pending > 0,
                    label: Text('$pending'),
                    backgroundColor: AppTheme.primary,
                    child: syncing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.arrow_2_circlepath),
                  ),
                ),
              ],
            );
          },
        ),

        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Search subscriber, ticket #, address',
              onChanged: (text) {
                setState(() {});
                signals.setSearch(text);
              },
            ),
          ),

        // Offline state is one muted line, not a banner.
        SignalBuilder(
          builder: (context) {
            final pending = signals.unsyncedCount.value;
            if (pending == 0) return const SizedBox.shrink();
            return _PendingSyncLine(
              pending: pending,
              onSync: () => signals.repository.syncWorker.syncPendingJobs(),
            );
          },
        ),

        // Done jobs live behind one toggle instead of a second tab.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Show done jobs',
                  style: context.text.bodyMedium!.copyWith(
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ),
              ),
              Semantics(
                label: 'Show done jobs',
                toggled: _showDone,
                child: Switch.adaptive(
                  value: _showDone,
                  onChanged: (v) => setState(() {
                    _showDone = v;
                    if (v) _showMap = false;
                    _selectedJobId = null;
                  }),
                ),
              ),
            ],
          ),
        ),

        // Gene - Oct 13, 2026: Added Group By toggle (Date vs Barangay) allowing technicians to group the queue chronologically or geographically.
        if (!_showDone && !_showMap)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Group by',
                      style: context.text.bodyMedium!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<JobGrouping>(
                    segments: const [
                      ButtonSegment(
                        value: JobGrouping.date,
                        label: Text('Date'),
                      ),
                      ButtonSegment(
                        value: JobGrouping.barangay,
                        label: Text('Barangay'),
                      ),
                    ],
                    selected: {_grouping},
                    showSelectedIcon: false,
                    /*
                    // Gene - Oct 13, 2026: Previously used compact visual density and shrink wrap tap target; commented out to preserve touch target accessibility.
                    style: ButtonStyle(
                      visualDensity: VisualDensity.standard,
                    ),
                    */
                    // Gene - Oct 13, 2026: Default SegmentedButton style used to ensure accessible touch target sizes conforming to tap targets audit.
                    onSelectionChanged: (selection) =>
                        setState(() => _grouping = selection.first),
                  ),
                ],
              ),
            ),
          ),

        Expanded(child: _buildBody(context, signals)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, JobsSignals signals) {
    if (_showDone) {
      return JobHistoryView(
        jobsSignals: signals,
        authSignals: widget.authSignals,
        onSelectJob: _openDetails,
      );
    }

    return SignalBuilder(
      builder: (context) {
        final jobs = signals.filteredJobs.value;
        final phase = signals.loadPhase.value;

        if (phase == DataLoadPhase.downloading) {
          return const DownloadingIndicator(
            title: 'Downloading Job Orders',
            subtitle: 'Fetching your scheduled dispatches from the server...',
          );
        }
        if (phase == DataLoadPhase.skeleton) {
          return const SkeletonCardList();
        }

        if (_showMap) {
          return JobsMapView(
            jobsSignals: signals,
            lcpNapSignals: widget.lcpNapSignals,
            onOpenJob: _openDetails,
          );
        }

        if (jobs.isEmpty) {
          final query = _searchController.text.trim();
          if (query.isNotEmpty) {
            return _buildSearchEmptyState(signals, query);
          }
          return _buildEmptyState(signals);
        }

        /*
        // Every job is the same card with the same three actions, so the
        // technician picks freely. The nearest job leads under a NEXT kicker;
        // a search shows plain matches in their own order.
        final searching = _searchController.text.trim().isNotEmpty;
        final next = searching ? null : pickNext(jobs);
        final ordered = [
          if (next != null) next,
          for (final job in jobs)
            if (job.id != next?.id && !job.isRescheduled) job,
          for (final job in jobs)
            if (job.id != next?.id && job.isRescheduled) job,
        ];

        return RefreshIndicator(
          onRefresh: signals.fetchRemote,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (var i = 0; i < ordered.length; i++) ...[
                if (next != null && i == 0) const _Kicker('Next'),
                if (next != null && i == 1) const _Kicker('Then'),
                _JobRow(
                  job: ordered[i],
                  onTap: () => _openDetails(ordered[i]),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
        */
        // Gene - Oct 8, 2026: Group jobs by scheduled Date instead of Next and Then kickers.
        // Orders groups chronologically and keeps nearest GPS dispatch prioritized within its date.
        final searching = _searchController.text.trim().isNotEmpty;
        final next = searching ? null : pickNext(jobs);
        final prioritized = [
          if (next != null) next,
          for (final job in jobs)
            if (job.id != next?.id && !job.isRescheduled) job,
          for (final job in jobs)
            if (job.id != next?.id && job.isRescheduled) job,
        ];

        // Group prioritized jobs by scheduled calendar day
        final Map<String, List<JobOrderDto>> groupedJobs = {};
        final Map<String, DateTime?> groupDates = {};

        for (final job in prioritized) {
          final date = job.scheduledDate;
          final key = date != null
              ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
              : 'unscheduled';
          groupedJobs.putIfAbsent(key, () => []).add(job);
          if (!groupDates.containsKey(key)) {
            groupDates[key] =
                date != null ? DateTime(date.year, date.month, date.day) : null;
          }
        }

        // Sort groups chronologically: past/today first, future dates following, unscheduled last
        final sortedKeys = groupedJobs.keys.toList()
          ..sort((a, b) {
            final dateA = groupDates[a];
            final dateB = groupDates[b];
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return dateA.compareTo(dateB);
          });

/*
        return RefreshIndicator(
          onRefresh: signals.fetchRemote,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final key in sortedKeys) ...[
                _Kicker(dateGroupLabel(groupDates[key])),
                for (final job in groupedJobs[key]!) ...[
                  _JobRow(
                    job: job,
                    onTap: () => _openDetails(job),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        );
*/
        // Gene - Oct 13, 2026: If grouped by Barangay, group all jobs across all dates strictly by Barangay with 1 header per barangay.
        if (_grouping == JobGrouping.barangay) {
          final bgyMap = <String, List<JobOrderDto>>{};
          for (final job in prioritized) {
            final bgy = (job.barangay != null &&
                    job.barangay!.trim().isNotEmpty)
                ? job.barangay!.trim()
                : 'Other Area';
            bgyMap.putIfAbsent(bgy, () => []).add(job);
          }
          final sortedBgys = bgyMap.keys.toList()
            ..sort((a, b) {
              if (a == 'Other Area') return 1;
              if (b == 'Other Area') return -1;
              return a.compareTo(b);
            });

          return RefreshIndicator(
            onRefresh: signals.fetchRemote,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final bgy in sortedBgys) ...[
                  _BarangayHeader(
                    barangay: bgy,
                    count: bgyMap[bgy]!.length,
                  ),
                  for (final job in bgyMap[bgy]!) ...[
                    _JobRow(
                      job: job,
                      onTap: () => _openDetails(job),
                      onOpenReport: () => _openReport(job),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          );
        }

        // Gene - Oct 12, 2026: Sub-cluster jobs by Barangay under each Date group matching AppSheet hierarchy.
        return RefreshIndicator(
          onRefresh: signals.fetchRemote,
          color: AppTheme.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final key in sortedKeys) ...[
                _Kicker(dateGroupLabel(groupDates[key])),
                ...() {
                  final bgyMap = <String, List<JobOrderDto>>{};
                  for (final job in groupedJobs[key]!) {
                    final bgy = (job.barangay != null &&
                            job.barangay!.trim().isNotEmpty)
                        ? job.barangay!.trim()
                        : 'Other Area';
                    bgyMap.putIfAbsent(bgy, () => []).add(job);
                  }
                  final sortedBgys = bgyMap.keys.toList()
                    ..sort((a, b) {
                      if (a == 'Other Area') return 1;
                      if (b == 'Other Area') return -1;
                      return a.compareTo(b);
                    });

                  return [
                    for (final bgy in sortedBgys) ...[
                      if (sortedBgys.length > 1 || bgy != 'Other Area')
                        _BarangayHeader(
                          barangay: bgy,
                          count: bgyMap[bgy]!.length,
                        ),
                      for (final job in bgyMap[bgy]!) ...[
                        _JobRow(
                          job: job,
                          onTap: () => _openDetails(job),
                          onOpenReport: () => _openReport(job),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ];
                }(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoJobSelectedPlaceholder(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.doc_text_search,
              size: 36,
              color: AppTheme.secondaryInkOf(context),
            ),
            const SizedBox(height: 14),
            Text('Select a Job Order', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Choose a job from the list to view its details and workflow actions.',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(JobsSignals signals, String query) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 32,
              color: AppTheme.secondaryInkOf(context),
            ),
            const SizedBox(height: 10),
            Text(
              'No jobs matching "$query"',
              style: context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Check for typos or clear your search to see all scheduled jobs.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                signals.setSearch('');
                setState(() {});
              },
              icon: const Icon(CupertinoIcons.clear_circled, size: 20),
              label: const Text('Clear Search'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(140, 48)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(JobsSignals signals) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.calendar_badge_plus,
              size: 32,
              color: AppTheme.secondaryInkOf(context),
            ),
            const SizedBox(height: 10),
            Text('No Scheduled Jobs Pending', style: context.text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Every scheduled job has been activated. Pull down to refresh from the server.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: signals.fetchRemote,
              icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
              label: const Text('Pull Scheduled From Server'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small uppercase label above a group of rows: `NEXT`, `THEN`.
class _Kicker extends StatelessWidget {
  final String text;

  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 6),
      child: Text(
        text.toUpperCase(),
        style: context.text.labelMedium!.copyWith(
          color: AppTheme.secondaryInkOf(context),
        ),
      ),
    );
  }
}

// Gene - Oct 12, 2026: Sub-header banner grouping jobs within a calendar day by Barangay.
class _BarangayHeader extends StatelessWidget {
  final String barangay;
  final int count;

  const _BarangayHeader({required this.barangay, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: [
          // Gene - Oct 12, 2026: Set location icon size to 20 to satisfy field UI standard floor.
          const Icon(
            Icons.location_on_rounded,
            size: 20,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 6),
/*
          Text(
            barangay == 'Other Area' ? barangay : 'Brgy. $barangay',
            style: context.text.labelLarge!.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.brandInkOf(context),
            ),
          ),
*/
          // Gene - Oct 12, 2026: Expanded barangay label with ellipsis to prevent overflow at 200% text scale.
          Expanded(
            child: Text(
              barangay == 'Other Area' ? barangay : 'Brgy. $barangay',
              style: context.text.labelLarge!.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandInkOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.fillOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            // Gene - Oct 12, 2026: Used theme labelSmall token instead of literal fontSize.
            child: Text(
              '$count ${count == 1 ? 'job' : 'jobs'}',
              style: context.text.labelSmall!.copyWith(
                color: AppTheme.secondaryInkOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One scheduled job as a status-rail card: distance in the lead column, the
/// subscriber, the ticket with the record id in brackets as the mono data
/// line, then icon-led detail lines at one size (address, plant ids, plan,
/// phone, email) with a copy button for the contact, the status word, and
/// the same three actions on every card: Navigate, Call, SMS. Tapping the
/// card opens the job.
/*
class _JobRow extends StatelessWidget {
  final JobOrderDto job;
  final VoidCallback onTap;

  const _JobRow({required this.job, required this.onTap});

  /// A plant value the server left blank or wrote as "0" is unassigned.
  static String? _assigned(String? raw) {
    final v = raw?.trim();
    return v == null || v.isEmpty || v == '0' ? null : v;
  }

  /// `202609051153198108414 (3980)`: the application ticket and the record id.
  static String ticketLine(JobOrderDto job) =>
      '${job.ticketNumber} (${job.id})';

  @override
  Widget build(BuildContext context) {
    final (label, rail, ink) = jobStatusWord(context, job);
    final place = [
      job.address.trim(),
      if (job.barangay?.isNotEmpty == true) job.barangay!,
      if (job.city?.isNotEmpty == true) job.city!,
    ].where((s) => s.isNotEmpty).join(', ');
    final napText = _assigned(job.nap) ??
        (job.napId != null && job.napId! > 0 ? 'NAP ${job.napId}' : null);
    final plant = [
      if (job.lcpId != null && job.lcpId! > 0) 'LCP ${job.lcpId}',
      if (napText != null) napText,
      if (_assigned(job.portId) != null) _assigned(job.portId)!,
    ].join(' · ');
    final phone = [
      if (job.contactNumber?.trim().isNotEmpty == true)
        job.contactNumber!.trim(),
      if (job.secondContactNumber != null) job.secondContactNumber!,
    ].join(' · ');
    final email = job.subscriberEmail;

    return StatusRailRow(
      leading: distanceLabelFor(job),
      railColor: rail,
      statusInk: ink,
      title: job.customerName,
      data: ticketLine(job),
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (place.isNotEmpty)
            _DetailLine(icon: Icons.location_on_outlined, text: place),
          if (plant.isNotEmpty)
            _DetailLine(icon: Icons.hub_outlined, text: plant, mono: true),
          if (job.planName?.isNotEmpty == true)
            _DetailLine(icon: Icons.wifi_rounded, text: job.planName!),
          _ContactLines(phone: phone, email: email, job: job),
        ],
      ),
      statusLabel: label,
      onTap: onTap,
      actions: [
        StatusRailAction(
          icon: Icons.navigation_rounded,
          label: 'Navigate',
          onTap: () => navigateToJob(job),
        ),
        StatusRailAction(
          icon: Icons.call_rounded,
          label: 'Call',
          onTap: () => callJob(context, job),
        ),
        StatusRailAction(
          icon: Icons.sms_rounded,
          label: 'SMS',
          onTap: () => smsJob(context, job),
        ),
      ],
    );
  }
}
*/
// Gene - Oct 6, 2026: Made _JobRow expandable so secondary details (address, plant, contact, actions) are collapsed by default and toggleable via trailing chevron button.
// Gene - Oct 13, 2026: Added onOpenReport callback to trigger direct completion report creation from trailing shortcut.
class _JobRow extends StatefulWidget {
  final JobOrderDto job;
  final VoidCallback onTap;
  final VoidCallback? onOpenReport;

  const _JobRow({required this.job, required this.onTap, this.onOpenReport});

  /// A plant value the server left blank or wrote as "0" is unassigned.
  static String? _assigned(String? raw) {
    final v = raw?.trim();
    return v == null || v.isEmpty || v == '0' ? null : v;
  }

  /// `202609051153198108414 (3980)`: the application ticket and the record id.
  static String ticketLine(JobOrderDto job) =>
      '${job.ticketNumber} (${job.id})';

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final (label, rail, ink) = jobStatusWord(context, job);
    final place = [
      job.address.trim(),
      if (job.barangay?.isNotEmpty == true) job.barangay!,
      if (job.city?.isNotEmpty == true) job.city!,
    ].where((s) => s.isNotEmpty).join(', ');
    final napText = _JobRow._assigned(job.nap) ??
        (job.napId != null && job.napId! > 0 ? 'NAP ${job.napId}' : null);
    final plant = [
      if (job.lcpId != null && job.lcpId! > 0) 'LCP ${job.lcpId}',
      if (napText != null) napText,
      if (_JobRow._assigned(job.portId) != null) _JobRow._assigned(job.portId)!,
    ].join(' · ');
    final phone = [
      if (job.contactNumber?.trim().isNotEmpty == true)
        job.contactNumber!.trim(),
      if (job.secondContactNumber != null) job.secondContactNumber!,
    ].join(' · ');
    final email = job.subscriberEmail;

/*
    return StatusRailRow(
      leading: distanceLabelFor(job),
      railColor: rail,
      statusInk: ink,
      title: job.customerName,
      data: _JobRow.ticketLine(job),
      trailing: IconButton(
        key: ValueKey('job_expand_toggle_${job.id}'),
        icon: Icon(
          _isExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: AppTheme.secondaryInkOf(context),
        ),
        tooltip: _isExpanded ? 'Collapse details' : 'Expand details',
        onPressed: () => setState(() => _isExpanded = !_isExpanded),
      ),
      extra: _isExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (place.isNotEmpty)
                  _DetailLine(icon: Icons.location_on_outlined, text: place),
                if (plant.isNotEmpty)
                  _DetailLine(
                      icon: Icons.hub_outlined, text: plant, mono: true),
                if (job.planName?.isNotEmpty == true)
                  _DetailLine(icon: Icons.wifi_rounded, text: job.planName!),
                _ContactLines(phone: phone, email: email, job: job),
              ],
            )
          : null,
      statusLabel: label,
      onTap: widget.onTap,
      actions: _isExpanded
          ? [
              StatusRailAction(
                icon: Icons.navigation_rounded,
                label: 'Navigate',
                onTap: () => navigateToJob(job),
              ),
              StatusRailAction(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: () => callJob(context, job),
              ),
              StatusRailAction(
                icon: Icons.sms_rounded,
                label: 'SMS',
                onTap: () => smsJob(context, job),
              ),
            ]
          : null,
    );
*/
    // Gene - Oct 13, 2026: Made card tap toggle expand/collapse so tapping the card never triggers accidental navigation, and moved Details navigation to a dedicated action button at the end of the action footer.
    return StatusRailRow(
      leading: distanceLabelFor(job),
      railColor: rail,
      statusInk: ink,
      title: job.customerName,
      data: _JobRow.ticketLine(job),
      /*
      trailing: IconButton(
        key: ValueKey('job_expand_toggle_${job.id}'),
        icon: Icon(
          _isExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: AppTheme.secondaryInkOf(context),
        ),
        tooltip: _isExpanded ? 'Collapse details' : 'Expand details',
        onPressed: () => setState(() => _isExpanded = !_isExpanded),
      ),
      */
      /*
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('job_expand_toggle_${job.id}'),
            icon: Icon(
              _isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppTheme.secondaryInkOf(context),
            ),
            tooltip: _isExpanded ? 'Collapse details' : 'Expand details',
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
          ),
          IconButton(
            key: ValueKey('job_report_shortcut_${job.id}'),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primary,
            ),
            tooltip: 'Open report',
            onPressed: widget.onOpenReport,
          ),
        ],
      ),
      */
      // Gene - Oct 13, 2026: Positioned expand toggle chevron inside the card body, and dedicated trailing '>' button separated by vertical hairline divider.
      expandToggle: IconButton(
        key: ValueKey('job_expand_toggle_${job.id}'),
        icon: Icon(
          _isExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: AppTheme.secondaryInkOf(context),
        ),
        tooltip: _isExpanded ? 'Collapse details' : 'Expand details',
        onPressed: () => setState(() => _isExpanded = !_isExpanded),
      ),
      /*
      trailing: Tooltip(
        message: 'Open report',
        child: InkWell(
          key: ValueKey('job_report_shortcut_${job.id}'),
          onTap: widget.onOpenReport,
          child: const SizedBox(
            width: 48,
            child: Center(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      ),
      */
      // Gene - Oct 13, 2026: Disabled report shortcut button '>' for rescheduled jobs to prevent opening reports or modifying records.
      trailing: () {
        final isRescheduled = job.isRescheduled ||
            job.siteException == SiteException.reschedule;
        return Tooltip(
          message: isRescheduled
              ? 'Rescheduled (report locked)'
              : 'Open report',
          child: InkWell(
            key: ValueKey('job_report_shortcut_${job.id}'),
            onTap: isRescheduled ? null : widget.onOpenReport,
            child: SizedBox(
              width: 48,
              child: Center(
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: isRescheduled
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white24
                          : Colors.black26)
                      : AppTheme.primary,
                ),
              ),
            ),
          ),
        );
      }(),
      extra: _isExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (place.isNotEmpty)
                  _DetailLine(icon: Icons.location_on_outlined, text: place),
                if (plant.isNotEmpty)
                  _DetailLine(
                      icon: Icons.hub_outlined, text: plant, mono: true),
                if (job.planName?.isNotEmpty == true)
                  _DetailLine(icon: Icons.wifi_rounded, text: job.planName!),
                _ContactLines(phone: phone, email: email, job: job),
              ],
            )
          : null,
      statusLabel: label,
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      actions: _isExpanded
          ? [
              StatusRailAction(
                icon: Icons.navigation_rounded,
                label: 'Navigate',
                onTap: () => navigateToJob(job),
              ),
              StatusRailAction(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: () => callJob(context, job),
              ),
              StatusRailAction(
                icon: Icons.sms_rounded,
                label: 'SMS',
                onTap: () => smsJob(context, job),
              ),
              StatusRailAction(
                icon: Icons.assignment_outlined,
                label: 'Details',
                onTap: widget.onTap,
              ),
            ]
          : null,
    );
  }
}

/// One detail line on a job card: a muted 18px icon and body text that wraps.
/// Every line uses the same body role so address, plan, phone and email read
/// at one size.
class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool mono;

  const _DetailLine(
      {required this.icon, required this.text, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryInkOf(context);
    final base = mono ? context.text.bodyLarge! : context.text.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: base.copyWith(color: muted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone and email lines with one Copy contact button beside them, so the
/// technician can read a number back to a caller or paste both into a
/// message. Reads "No contact on file" when the order carries neither.
class _ContactLines extends StatelessWidget {
  final String phone;
  final String? email;
  final JobOrderDto job;

  const _ContactLines({
    required this.phone,
    required this.email,
    required this.job,
  });

  /// What the copy button puts on the clipboard: `phone · email`.
  static String copyText(JobOrderDto job) => [
        if (job.contactNumber?.trim().isNotEmpty == true)
          job.contactNumber!.trim(),
        if (job.secondContactNumber != null) job.secondContactNumber!,
        if (job.subscriberEmail != null) job.subscriberEmail!,
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    if (phone.isEmpty && email == null) {
      return const _DetailLine(
          icon: Icons.person_off_outlined, text: 'No contact on file');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phone.isNotEmpty)
                _DetailLine(icon: Icons.call_outlined, text: phone),
              if (email != null)
                _DetailLine(icon: Icons.alternate_email_rounded, text: email!),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Copy contact',
          icon: const Icon(Icons.copy_rounded, size: 20),
          onPressed: () {
            final text = copyText(job);
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Copied $text'),
              behavior: SnackBarBehavior.floating,
            ));
          },
        ),
      ],
    );
  }
}

/// The one status word for a scheduled job and its rail and ink colours.
/*
(String, Color, Color) jobStatusWord(BuildContext context, JobOrderDto j) {
  if (!j.isSynced) {
    return ('Pending sync', AppTheme.warning, AppTheme.warningInkOf(context));
  }
  if (j.isRescheduled) {
    return ('Rescheduled', AppTheme.warning, AppTheme.warningInkOf(context));
  }
  switch (j.onsiteStatus?.trim().toLowerCase()) {
    case 'failed':
      return ('Failed', AppTheme.danger, AppTheme.dangerInkOf(context));
    case 'reschedule':
      return ('Reschedule', AppTheme.warning, AppTheme.warningInkOf(context));
    case 'in progress':
    case 'inprogress':
      return ('In progress', AppTheme.info, AppTheme.infoInkOf(context));
    default:
      return ('Scheduled', AppTheme.info, AppTheme.infoInkOf(context));
  }
}
*/
// Gene - Oct 3, 2026: Check j.isInProgress before falling back to onsiteStatus so office status 'In Progress' / 'Inprogress' displays 'In progress' badge rather than falling through to 'Scheduled' when onsiteStatus is null or empty.
(String, Color, Color) jobStatusWord(BuildContext context, JobOrderDto j) {
  if (!j.isSynced) {
    return ('Pending sync', AppTheme.warning, AppTheme.warningInkOf(context));
  }
  if (j.isRescheduled) {
    return ('Rescheduled', AppTheme.warning, AppTheme.warningInkOf(context));
  }
  if (j.isInProgress) {
    return ('In progress', AppTheme.info, AppTheme.infoInkOf(context));
  }
  switch (j.onsiteStatus?.trim().toLowerCase()) {
    case 'failed':
      return ('Failed', AppTheme.danger, AppTheme.dangerInkOf(context));
    case 'reschedule':
      return ('Reschedule', AppTheme.warning, AppTheme.warningInkOf(context));
    case 'in progress':
    case 'inprogress':
      return ('In progress', AppTheme.info, AppTheme.infoInkOf(context));
    default:
      return ('Scheduled', AppTheme.info, AppTheme.infoInkOf(context));
  }
}

/// `2 saved on phone · send when online` with a Sync now button. Side by
/// side at ordinary text sizes; stacked above a 1.2 text scale so the button
/// never squeezes the sentence into a tall sliver.
class _PendingSyncLine extends StatelessWidget {
  final int pending;
  final VoidCallback onSync;

  const _PendingSyncLine({required this.pending, required this.onSync});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final line = Row(
      children: [
        Icon(Icons.cloud_off_rounded,
            size: 20, color: AppTheme.warningInkOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$pending saved on phone · '
            '${pending == 1 ? 'sends' : 'send'} when online',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
    final button = TextButton(onPressed: onSync, child: const Text('Sync now'));

    if (scale > 1.2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [line, button],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(children: [Expanded(child: line), button]),
    );
  }
}
