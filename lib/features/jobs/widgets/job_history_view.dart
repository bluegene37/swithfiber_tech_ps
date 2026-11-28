import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:powersync/powersync.dart' show SyncStreamSubscription;
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/sync/powersync_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/loading_states.dart';
import '../../auth/signals/auth_signals.dart';
import '../models/job_order_model.dart';
import '../signals/jobs_signals.dart';
import '../widgets/job_history_tile.dart';
import '../screens/job_order_detail_screen.dart';

/// The signed-in technician's done jobs (activated or completed), shown on
/// Today behind the "Show done jobs" toggle.
///
/// Header, top to bottom: the search field, one line of counts, and one row
/// of filter buttons (status · date · area) that each open a sheet. The old
/// four-number strip and three chip rows took 290dp before the first job;
/// this takes about half that.
class JobHistoryView extends StatefulWidget {
  final JobsSignals jobsSignals;
  final AuthSignals? authSignals;
  final void Function(JobOrderDto job)? onSelectJob;

  const JobHistoryView({
    super.key,
    required this.jobsSignals,
    this.authSignals,
    this.onSelectJob,
  });

  /// `8 done · 2 activated · 6 completed · 6 this week`, the plain-text form
  /// of the summary line (for tests and semantics).
  static String summaryText({
    required int total,
    required int activated,
    required int completed,
    required int thisWeek,
  }) =>
      '$total done · $activated activated · $completed completed · '
      '$thisWeek this week';

  @override
  State<JobHistoryView> createState() => _JobHistoryViewState();
}

class _JobHistoryViewState extends State<JobHistoryView> {
  final TextEditingController _searchController = TextEditingController();
  // Gene - Nov, 28, 2026: On-demand PowerSync v12 history stream subscription with 15m TTL, cleaned up when leaving history view.
  SyncStreamSubscription? _historySub;
  bool _isSyncingHistory = false;

  static final _short = DateFormat('MMM d');

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.jobsSignals.historySearch.value;
    _subscribeHistory();
  }

  Future<void> _subscribeHistory() async {
    if (!PowerSyncService.instance.isInitialized ||
        !PowerSyncService.instance.isReplicatedMode) {
      return;
    }
    if (mounted) setState(() => _isSyncingHistory = true);
    try {
      final sub = await PowerSyncService.instance.subscribeHistoryStream(
        'assigned_job_orders_history',
        ttl: const Duration(minutes: 15),
      );
      if (!mounted) {
        sub?.unsubscribe();
        return;
      }
      _historySub = sub;
      await sub?.waitForFirstSync();
    } catch (_) {
      // Offline or transient sync failure: show locally cached history rows.
    } finally {
      if (mounted) setState(() => _isSyncingHistory = false);
    }
  }

  @override
  void dispose() {
    _historySub?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(JobOrderDto job) {
    if (widget.onSelectJob != null) {
      widget.onSelectJob!(job);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobOrderDetailScreen(
          jobId: job.id,
          jobsSignals: widget.jobsSignals,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _pickStatus() async {
    final signals = widget.jobsSignals;
    final picked = await showFilterSheet<HistoryStatusFilter>(
      context,
      title: 'Status',
      options: [
        for (final f in HistoryStatusFilter.values)
          FilterOption(
              f, f == HistoryStatusFilter.all ? 'All statuses' : f.label),
      ],
      selected: signals.historyStatus.value,
    );
    if (picked != null) signals.setHistoryStatus(picked);
  }

  Future<void> _pickRange() async {
    final signals = widget.jobsSignals;
    final start = signals.historyRangeStart.value;
    final end = signals.historyRangeEnd.value;
    final picked = await showFilterSheet<HistoryRange>(
      context,
      title: 'Date',
      options: [
        for (final r in HistoryRange.values)
          FilterOption(
            r,
            r == HistoryRange.custom && start != null && end != null
                ? '${_short.format(start)} – ${_short.format(end)}'
                : r.label,
            hint:
                r == HistoryRange.custom ? 'Choose a start and end day' : null,
          ),
      ],
      selected: signals.historyRange.value,
    );
    if (picked == null) return;
    if (picked == HistoryRange.custom) {
      await _pickCustomRange();
    } else {
      signals.setHistoryRange(picked);
    }
  }

  Future<void> _pickCustomRange() async {
    final signals = widget.jobsSignals;
    final now = signals.clock();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: signals.historyRangeStart.value != null &&
              signals.historyRangeEnd.value != null
          ? DateTimeRange(
              start: signals.historyRangeStart.value!,
              end: signals.historyRangeEnd.value!,
            )
          : null,
      helpText: 'Show jobs done between',
    );
    if (picked == null) return;
    signals.setHistoryRange(HistoryRange.custom,
        start: picked.start, end: picked.end);
  }

  Future<void> _pickCity(List<String> cities) async {
    final signals = widget.jobsSignals;
    // The sheet cannot carry a null value, so "every area" travels as ''.
    final picked = await showFilterSheet<String>(
      context,
      title: 'Area',
      options: [
        const FilterOption('', 'All areas'),
        for (final c in cities) FilterOption(c, c),
      ],
      selected: signals.historyCity.value ?? '',
    );
    if (picked != null) signals.setHistoryCity(picked.isEmpty ? null : picked);
  }

  void _clearFilters() {
    _searchController.clear();
    widget.jobsSignals.clearHistoryFilters();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final signals = widget.jobsSignals;
    final auth = widget.authSignals ?? AuthSignals.instance;

    return SignalBuilder(
      builder: (context) {
        final email = signals.technicianEmail.value?.trim() ?? '';
        if (email.isEmpty && signals.assignedJobs.value.isEmpty) {
          return _NoEmailState(onRefreshProfile: auth.refreshProfile);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSearchField(
                    controller: _searchController,
                    hintText: 'Search ticket #, subscriber, address',
                    onChanged: (v) {
                      signals.setHistorySearch(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  _HistorySummaryLine(signals: signals),
                  const SizedBox(height: 8),
                  _HistoryFilterRow(
                    signals: signals,
                    onStatus: _pickStatus,
                    onRange: _pickRange,
                    onCity: _pickCity,
                    onReset: _clearFilters,
                  ),
                  if (_isSyncingHistory) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final phase = signals.loadPhase.value;
                  if (phase == DataLoadPhase.downloading) {
                    return const DownloadingIndicator(
                      title: 'Downloading Job Orders',
                      subtitle: 'Fetching your history from the server...',
                    );
                  }
                  if (phase == DataLoadPhase.skeleton) {
                    return const SkeletonCardList();
                  }

                  final jobs = signals.historyJobs.value;
                  if (jobs.isEmpty) {
                    final total = signals.historyTotalCount.value;
                    return _EmptyState(
                      filtered: total > 0,
                      onRefresh: () => signals.fetchRemote(),
                      onClearFilters: _clearFilters,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: signals.fetchRemote,
                    color: AppTheme.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: jobs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        return JobHistoryTile(
                          job: job,
                          onTap: () => _openDetails(job),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Totals across the technician's whole history, regardless of filter, as
/// one line of measured numbers: `8 done · 2 activated · 6 completed ·
/// 6 this week`. Same anatomy as the Plant counts line.
class _HistorySummaryLine extends StatelessWidget {
  final JobsSignals signals;

  const _HistorySummaryLine({required this.signals});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final total = signals.historyTotalCount.value;
        final activated = signals.historyActivatedCount.value;
        final completed = signals.historyCompletedCount.value;
        final week = signals.historyThisWeekCount.value;

        final mono =
            context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w500);
        final unit = context.text.bodyMedium!
            .copyWith(color: AppTheme.secondaryInkOf(context));
        TextSpan pair(int n, String u) => TextSpan(children: [
              TextSpan(text: '$n', style: mono),
              TextSpan(text: ' $u', style: unit),
            ]);
        final dot = TextSpan(text: '  ·  ', style: unit);

        return Semantics(
          label: JobHistoryView.summaryText(
            total: total,
            activated: activated,
            completed: completed,
            thisWeek: week,
          ),
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(children: [
              pair(total, 'done'),
              dot,
              pair(activated, 'activated'),
              dot,
              pair(completed, 'completed'),
              dot,
              pair(week, 'this week'),
            ]),
          ),
        );
      },
    );
  }
}

/// One row of filter buttons, each naming its current value: `All statuses`
/// · `All time` · `All areas`. A button with a filter applied is filled in
/// ink so the narrowed list is never a surprise. Wraps to a second line at
/// large text instead of scrolling off the edge.
class _HistoryFilterRow extends StatelessWidget {
  final JobsSignals signals;
  final VoidCallback onStatus;
  final VoidCallback onRange;
  final void Function(List<String> cities) onCity;
  final VoidCallback onReset;

  const _HistoryFilterRow({
    required this.signals,
    required this.onStatus,
    required this.onRange,
    required this.onCity,
    required this.onReset,
  });

  static final _short = DateFormat('MMM d');

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final status = signals.historyStatus.value;
        final range = signals.historyRange.value;
        final start = signals.historyRangeStart.value;
        final end = signals.historyRangeEnd.value;
        final city = signals.historyCity.value;
        final cities = signals.historyCities.value;

        final rangeLabel =
            range == HistoryRange.custom && start != null && end != null
                ? '${_short.format(start)} – ${_short.format(end)}'
                : range.label;
        final anyActive = status != HistoryStatusFilter.all ||
            range != HistoryRange.all ||
            city != null;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterButton(
              label: status == HistoryStatusFilter.all
                  ? 'All statuses'
                  : status.label,
              active: status != HistoryStatusFilter.all,
              onTap: onStatus,
            ),
            FilterButton(
              label: rangeLabel,
              active: range != HistoryRange.all,
              onTap: onRange,
            ),
            if (cities.isNotEmpty)
              FilterButton(
                label: city ?? 'All areas',
                active: city != null,
                onTap: () => onCity(cities),
              ),
            if (anyActive)
              TextButton(
                onPressed: onReset,
                child: const Text('Reset'),
              ),
          ],
        );
      },
    );
  }
}

/// A pill that names the current value of one filter and opens its sheet.
/// Hairline on card when nothing is applied; ink fill when something is.
/// 48dp tall so it is a full target with gloves on.
class FilterButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const FilterButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.inkOf(context);
    final fg = active ? AppTheme.pageOf(context) : ink;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: active ? ink : AppTheme.cardOf(context),
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? ink : AppTheme.hairlineOf(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flexible so a long area name at 200% text wraps inside
                  // the pill instead of running past the screen edge.
                  Flexible(
                    child: Text(
                      label,
                      style: context.text.labelLarge!.copyWith(color: fg),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 20, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in a [showFilterSheet].
class FilterOption<T> {
  final T value;
  final String label;
  final String? hint;

  const FilterOption(this.value, this.label, {this.hint});
}

/// Presents [options] as a sheet of 52dp rows with the current choice ticked
/// and returns the tapped value, or null when dismissed. Sheets are how
/// pickers present in this app (DESIGN.md, Navigation).
Future<T?> showFilterSheet<T>(
  BuildContext context, {
  required String title,
  required List<FilterOption<T>> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.cardOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.7;
      final ink = AppTheme.inkOf(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: sheetContext.text.titleMedium),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = option.value == selected;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(option.value),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option.label,
                                      style: context.text.bodyMedium!.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    if (option.hint != null)
                                      Text(
                                        option.hint!,
                                        style: context.text.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.check_rounded, size: 24, color: ink),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// Shown when the profile carries no email, so nothing can be matched.
class _NoEmailState extends StatelessWidget {
  final Future<void> Function() onRefreshProfile;

  const _NoEmailState({required this.onRefreshProfile});

  @override
  Widget build(BuildContext context) {
    /*
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.alternate_email_rounded,
              size: 40,
              color: AppTheme.secondaryInkOf(context),
            ),
            const SizedBox(height: 16),
            Text('No email on your profile', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Job orders are matched to you by the email address on your '
              'technician account. Refresh your profile, or ask Dispatch to '
              'add one.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRefreshProfile,
              icon: const Icon(Icons.person_search_rounded, size: 24),
              label: const Text('Refresh my profile'),
            ),
          ],
        ),
      ),
    );
    */
    // Gene - Nov, 28, 2026: Wrap _NoEmailState in SingleChildScrollView so 200% text scaling on compact viewports never overflows.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.alternate_email_rounded,
              size: 40,
              color: AppTheme.secondaryInkOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No email on your profile',
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Job orders are matched to you by the email address on your '
              'technician account. Refresh your profile, or ask Dispatch to '
              'add one.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRefreshProfile,
              icon: const Icon(Icons.person_search_rounded, size: 24),
              label: const Text('Refresh my profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  /// True when the technician has history but the filters hide it.
  final bool filtered;
  final VoidCallback onRefresh;
  final VoidCallback onClearFilters;

  const _EmptyState({
    required this.filtered,
    required this.onRefresh,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                filtered ? Icons.filter_alt_off_rounded : Icons.history_rounded,
                size: 40,
                color: AppTheme.secondaryInkOf(context),
              ),
              const SizedBox(height: 16),
              Text(
                filtered ? 'Nothing matches' : 'No done jobs yet',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                filtered
                    ? 'No done job matches the current status, date, area or '
                        'search.'
                    : 'Jobs you activate or complete stay here as a record. '
                        'Pull down to refresh from the server.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 20),
              if (filtered)
                OutlinedButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.clear_all_rounded, size: 24),
                  label: const Text('Clear filters'),
                )
              else
                ElevatedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 24),
                  label: const Text('Refresh from server'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
