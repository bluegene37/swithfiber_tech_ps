// Gene - Nov, 26, 2026: Work Timing History screen & per-order timing sessions card showing Start/Finish/Stop date+time filtered by userId and date.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/database/daos/work_timing_history_dao.dart';
import '../../../core/database/models/work_timing_entry.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/work_timing_bar.dart';

/// Displays recorded technician Start -> Finish/Stop work timing sessions,
/// filtered by technician `userId`, calendar date, and order type.
class WorkTimingHistoryScreen extends StatefulWidget {
  final WorkTimingHistoryDao? dao;
  final String? initialUserId;
  final String? initialOrderType;
  final DateTime? initialDate;

  const WorkTimingHistoryScreen({
    super.key,
    required this.dao,
    this.initialUserId,
    this.initialOrderType,
    this.initialDate,
  });

  @override
  State<WorkTimingHistoryScreen> createState() =>
      _WorkTimingHistoryScreenState();
}

class _WorkTimingHistoryScreenState extends State<WorkTimingHistoryScreen> {
  late DateTime _selectedDate;
  bool _showAllDates = false;
  late String _orderTypeFilter; // 'ALL', 'JOB_ORDER', or 'SERVICE_ORDER'

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _orderTypeFilter = widget.initialOrderType ?? 'ALL';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _showAllDates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userId = resolveTimingUserId(override: widget.initialUserId);
    final userName = resolveTimingUserName();
    final dao = widget.dao;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Timing History'),
      ),
      body: dao == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Local timing history storage is not available in this session.',
                  style: context.text.bodyMedium!.copyWith(
                    color: AppTheme.secondaryInkOf(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User ID identity banner
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppTheme.darkCard : AppTheme.lightCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.hairlineOf(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 20,
                              color: AppTheme.infoInkOf(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                userName != null && userName.isNotEmpty
                                    ? 'User ID: $userId · $userName'
                                    : 'User ID: $userId',
                                style: context.text.labelLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Date navigation row
                      Row(
                        children: [
                          IconButton(
                            key: const ValueKey('timing_history_prev_day'),
                            tooltip: 'Previous day',
                            constraints: const BoxConstraints(
                              minWidth: AppTheme.minTarget,
                              minHeight: AppTheme.minTarget,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedDate = _selectedDate
                                    .subtract(const Duration(days: 1));
                                _showAllDates = false;
                              });
                            },
                            icon: const Icon(Icons.chevron_left_rounded,
                                size: 24),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('timing_history_date_picker'),
                              onPressed: _pickDate,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, AppTheme.minTarget),
                              ),
                              icon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 20,
                              ),
                              label: Text(
                                _showAllDates
                                    ? 'All Dates'
                                    : (_isSameDay(_selectedDate, DateTime.now())
                                        ? 'Today · ${formatTimingDateFull(_selectedDate)}'
                                        : formatTimingDateFull(_selectedDate)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('timing_history_next_day'),
                            tooltip: 'Next day',
                            constraints: const BoxConstraints(
                              minWidth: AppTheme.minTarget,
                              minHeight: AppTheme.minTarget,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedDate =
                                    _selectedDate.add(const Duration(days: 1));
                                _showAllDates = false;
                              });
                            },
                            icon: const Icon(Icons.chevron_right_rounded,
                                size: 24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Date quick-filters & Order type filters
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            key: const ValueKey('timing_history_filter_today'),
                            label: const Text('Today'),
                            selected: !_showAllDates &&
                                _isSameDay(_selectedDate, DateTime.now()),
                            onSelected: (_) {
                              setState(() {
                                _selectedDate = DateTime.now();
                                _showAllDates = false;
                              });
                            },
                          ),
                          ChoiceChip(
                            key: const ValueKey(
                                'timing_history_filter_all_dates'),
                            label: const Text('All Dates'),
                            selected: _showAllDates,
                            onSelected: (_) {
                              setState(() => _showAllDates = true);
                            },
                          ),
                          ChoiceChip(
                            key: const ValueKey('timing_history_type_all'),
                            label: const Text('All Orders'),
                            selected: _orderTypeFilter == 'ALL',
                            onSelected: (_) {
                              setState(() => _orderTypeFilter = 'ALL');
                            },
                          ),
                          ChoiceChip(
                            key: const ValueKey('timing_history_type_job'),
                            label: const Text('Job Orders'),
                            selected: _orderTypeFilter ==
                                WorkTimingEntry.orderTypeJobOrder,
                            onSelected: (_) {
                              setState(() => _orderTypeFilter =
                                  WorkTimingEntry.orderTypeJobOrder);
                            },
                          ),
                          ChoiceChip(
                            key: const ValueKey('timing_history_type_service'),
                            label: const Text('Service Orders'),
                            selected: _orderTypeFilter ==
                                WorkTimingEntry.orderTypeServiceOrder,
                            onSelected: (_) {
                              setState(() => _orderTypeFilter =
                                  WorkTimingEntry.orderTypeServiceOrder);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<WorkTimingEntry>>(
                    // Gene - Nov, 26, 2026: Stream all sessions for active userId once and apply date/orderType filters synchronously for instant zero-flicker switching.
                    key: ValueKey('wth_stream_$userId'),
                    stream: dao.watchByUserAndDate(userId: userId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final selectedKey = formatTimingDateKey(_selectedDate);
                      final entries =
                          (snapshot.data ?? const <WorkTimingEntry>[])
                              .where((e) {
                        if (!_showAllDates && e.workDate != selectedKey) {
                          return false;
                        }
                        if (_orderTypeFilter != 'ALL' &&
                            e.orderType != _orderTypeFilter) {
                          return false;
                        }
                        return true;
                      }).toList();
                      if (entries.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history_toggle_off_rounded,
                                  size: 40,
                                  color: AppTheme.secondaryInkOf(context),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No timing sessions recorded',
                                  style: context.text.titleSmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _showAllDates
                                      ? 'Tap Start on a Job Order or Service Order to begin recording your work sessions.'
                                      : 'No sessions recorded for User ID $userId on ${formatTimingDateFull(_selectedDate)}.',
                                  style: context.text.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                                if (!_showAllDates) ...[
                                  const SizedBox(height: 14),
                                  OutlinedButton(
                                    onPressed: () {
                                      setState(() => _showAllDates = true);
                                    },
                                    child: const Text('Show All Dates'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }

                      final totalMinutes = entries.fold<int>(0, (acc, e) {
                        if (e.durationMinutes != null) {
                          return acc + e.durationMinutes!;
                        }
                        final d = e.elapsed;
                        return d == null ? acc : acc + d.inMinutes;
                      });

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${entries.length} ${entries.length == 1 ? 'session' : 'sessions'}'
                                '${totalMinutes > 0 ? ' · ${totalMinutes}m total' : ''}',
                                style: context.text.labelMedium!.copyWith(
                                  color: AppTheme.secondaryInkOf(context),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: entries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  _WorkTimingHistoryCard(entry: entries[index]),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _WorkTimingHistoryCard extends StatelessWidget {
  final WorkTimingEntry entry;

  const _WorkTimingHistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isService = entry.isServiceOrder;
    final railColor = isService ? AppTheme.serviceOrderAccent : AppTheme.info;
    final typeInk = isService
        ? AppTheme.serviceOrderInkOf(context)
        : AppTheme.infoInkOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeBg = isService
        ? AppTheme.serviceOrderSubtleBgOf(context)
        : (isDark ? AppTheme.darkCardElevated : AppTheme.infoSubtle);
    final typeBorder = isService
        ? AppTheme.serviceOrderSubtleBorderOf(context)
        : AppTheme.hairlineOf(context);
    final endLabel = isService ? 'Stop' : 'Finish';

    return Material(
      color: AppTheme.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        side: BorderSide(
          color: isService
              ? AppTheme.serviceOrderSubtleBorderOf(context)
              : AppTheme.hairlineOf(context),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: railColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeBg,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusStamp),
                            border: Border.all(color: typeBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isService
                                    ? CupertinoIcons.wrench_fill
                                    : Icons.work_outline_rounded,
                                size: 20,
                                color: typeInk,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isService ? 'SERVICE ORDER' : 'JOB ORDER',
                                style: context.text.labelSmall!.copyWith(
                                  color: typeInk,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          entry.orderReference,
                          style: context.text.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w600,
                            color: typeInk,
                          ),
                        ),
                        Icon(
                          entry.isSynced
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          size: 20,
                          color: entry.isSynced
                              ? AppTheme.successInkOf(context)
                              : AppTheme.warningInkOf(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.customerName,
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Start: ${formatTimingDateTime(entry.startTime, includeYear: true)}',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.isInProgress
                          ? '$endLabel: In progress'
                          : '$endLabel: ${formatTimingDateTime(entry.endTime!, includeYear: true)}',
                      style: context.text.bodySmall!.copyWith(
                        color: entry.isInProgress
                            ? AppTheme.infoInkOf(context)
                            : AppTheme.successInkOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'User ID: ${entry.userId}',
                          style: context.text.labelSmall,
                        ),
                        if (!entry.isInProgress)
                          Text(
                            'Duration: ${formatTimingDurationHuman(entry.startTime, entry.endTime!)}',
                            style: context.text.labelMedium!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact card rendered inside Job Order / Service Order details showing every
/// recorded Start -> Finish/Stop session for that specific order.
class OrderTimingHistoryCard extends StatelessWidget {
  final WorkTimingHistoryDao? dao;
  final String orderType;
  final int orderId;
  final String finishLabel;
  // Gene - Nov, 28, 2026: Optional server-synced fallback timestamps when local work_timing_history is empty (e.g. fresh install or session started on another device).
  final String? orderReference;
  final String? customerName;
  final DateTime? fallbackStartTime;
  final DateTime? fallbackEndTime;
  final String? fallbackUserId;

  /*
  const OrderTimingHistoryCard({
    super.key,
    required this.dao,
    required this.orderType,
    required this.orderId,
    this.finishLabel = 'Finish',
  });
  */
  const OrderTimingHistoryCard({
    super.key,
    required this.dao,
    required this.orderType,
    required this.orderId,
    this.finishLabel = 'Finish',
    this.orderReference,
    this.customerName,
    this.fallbackStartTime,
    this.fallbackEndTime,
    this.fallbackUserId,
  });

  WorkTimingEntry? _buildFallbackEntry() {
    final start = fallbackStartTime;
    if (start == null) return null;
    final normalizedStart = normalizeTimingTimestamp(start) ?? start;
    final normalizedEnd = normalizeTimingTimestamp(fallbackEndTime);
    final userId = (fallbackUserId?.trim().isNotEmpty ?? false)
        ? fallbackUserId!.trim()
        : 'Server record';
    final durationMinutes =
        normalizedEnd?.difference(normalizedStart).inMinutes.clamp(0, 1440);
    return WorkTimingEntry(
      id: 'server_fallback_${orderType}_$orderId',
      orderType: orderType,
      orderId: orderId,
      orderReference: orderReference ?? '$orderId',
      customerName: customerName ?? '',
      userId: userId,
      workDate: formatTimingDateKey(normalizedStart),
      startTime: normalizedStart,
      endTime: normalizedEnd,
      durationMinutes: durationMinutes,
      isSynced: true,
      createdAt: normalizedStart,
    );
  }

  Widget _buildCard(
    BuildContext context,
    List<WorkTimingEntry> entries, {
    bool isServerFallback = false,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Card(
      key: ValueKey('order_timing_history_card_${orderType}_$orderId'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: orderType == WorkTimingEntry.orderTypeServiceOrder
                      ? AppTheme.serviceOrderInkOf(context)
                      : AppTheme.infoInkOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Work Timing Sessions (${entries.length})',
                    style: context.text.titleSmall,
                  ),
                ),
              ],
            ),
            if (isServerFallback) ...[
              const SizedBox(height: 4),
              Text(
                'Latest synced session from server (prior multi-session logs stay on the device where they were started).',
                style: context.text.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 14,
                  color: AppTheme.hairlineOf(context),
                ),
              _OrderSessionRow(
                entry: entries[i],
                sessionNumber: entries.length - i,
                finishLabel: finishLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    /*
    if (dao == null) return const SizedBox.shrink();
    return StreamBuilder<List<WorkTimingEntry>>(
      stream: dao!.watchByOrder(orderType: orderType, orderId: orderId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <WorkTimingEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();

        return Card(
          key: ValueKey('order_timing_history_card_${orderType}_$orderId'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: orderType == WorkTimingEntry.orderTypeServiceOrder
                          ? AppTheme.serviceOrderInkOf(context)
                          : AppTheme.infoInkOf(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Work Timing Sessions (${entries.length})',
                        style: context.text.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 14,
                      color: AppTheme.hairlineOf(context),
                    ),
                  _OrderSessionRow(
                    entry: entries[i],
                    sessionNumber: entries.length - i,
                    finishLabel: finishLabel,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    */
    final fallback = _buildFallbackEntry();
    if (dao == null) {
      if (fallback == null) return const SizedBox.shrink();
      return _buildCard(context, [fallback], isServerFallback: true);
    }
    return StreamBuilder<List<WorkTimingEntry>>(
      stream: dao!.watchByOrder(orderType: orderType, orderId: orderId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <WorkTimingEntry>[];
        if (entries.isNotEmpty) {
          return _buildCard(context, entries);
        }
        if (fallback != null) {
          return _buildCard(context, [fallback], isServerFallback: true);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _OrderSessionRow extends StatelessWidget {
  final WorkTimingEntry entry;
  final int sessionNumber;
  final String finishLabel;

  const _OrderSessionRow({
    required this.entry,
    required this.sessionNumber,
    required this.finishLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Session #$sessionNumber',
              style: context.text.labelMedium!.copyWith(
                color: AppTheme.inkOf(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'User ID: ${entry.userId}',
              style: context.text.labelSmall,
            ),
            if (!entry.isInProgress)
              Text(
                formatTimingDurationHuman(entry.startTime, entry.endTime!),
                style: context.text.labelMedium!.copyWith(
                  color: AppTheme.successInkOf(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Start: ${formatTimingDateTime(entry.startTime, includeYear: true)}',
          style: context.text.bodySmall,
        ),
        Text(
          entry.isInProgress
              ? '$finishLabel: In progress'
              : '$finishLabel: ${formatTimingDateTime(entry.endTime!, includeYear: true)}',
          style: context.text.bodySmall!.copyWith(
            color: entry.isInProgress
                ? AppTheme.infoInkOf(context)
                : AppTheme.secondaryInkOf(context),
          ),
        ),
      ],
    );
  }
}
