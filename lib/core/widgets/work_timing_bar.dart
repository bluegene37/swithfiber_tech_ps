import 'package:flutter/material.dart';

import '../../features/auth/signals/auth_signals.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

// Gene - Nov, 25, 2026: Shared work-timing lifecycle helpers and widgets (Start -> Finish -> Finished) for Job Orders and Service Orders.

/// Three-state work timing progression on an assigned Job Order or Service Order.
enum WorkTimingStatus {
  /// Neither start nor end timestamp has been recorded; editing/reporting is locked.
  notStarted,

  /// Technician pressed Start (`startTime != null` and `endTime` is missing or `<= startTime`).
  inProgress,

  /// Technician pressed Finish (`startTime != null` and `endTime > startTime`); re-locked.
  finished,
}

/// Drops null or sentinel ASP.NET `default(DateTime)` (`0001-01-01`) timestamps.
DateTime? normalizeTimingTimestamp(DateTime? value) {
  if (value == null || value.year <= 1900) return null;
  return value;
}

/// Parses and normalizes a raw timing timestamp string or [DateTime] from API/DB.
DateTime? parseTimingTimestamp(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return normalizeTimingTimestamp(raw);
  final s = raw.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return normalizeTimingTimestamp(DateTime.tryParse(s));
}

/// Computes the [WorkTimingStatus] from a record's normalized timestamps.
///
/// The backend OpenAPI `createtiming` schema requires a non-nullable `endTime`,
/// so starting a task sends `endTime: startTime`. Treating `end <= start` as
/// [WorkTimingStatus.inProgress] guarantees in-progress state across restarts
/// until [Finish] stamps a strictly later `endTime`.
WorkTimingStatus resolveWorkTimingStatus(DateTime? start, DateTime? end) {
  final normalizedStart = normalizeTimingTimestamp(start);
  if (normalizedStart == null) return WorkTimingStatus.notStarted;
  final normalizedEnd = normalizeTimingTimestamp(end);
  if (normalizedEnd != null && normalizedEnd.isAfter(normalizedStart)) {
    return WorkTimingStatus.finished;
  }
  return WorkTimingStatus.inProgress;
}

/// Formats a timestamp as `h:mm AM/PM` in local time for compact timing pills.
String formatTimingClock(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour24 = local.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

// Gene - Nov, 26, 2026: Compute numeric whole-minute duration (>= 1) for UpdateJobOrderRequest / UpdateServiceOrderRequest.
String formatTimingDurationMinutes(DateTime start, DateTime end) {
  return end.difference(start).inMinutes.clamp(1, 999999).toString();
}

// Gene - Nov, 26, 2026: Date+time formatters, merge helper, and user identity resolvers for restartable Start/Finish/Stop timing and history.
const List<String> _timingMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Local calendar date key (`YYYY-MM-DD`) used for SQL indexing and date filters.
String formatTimingDateKey(DateTime timestamp) {
  final local = timestamp.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Short local date like `Nov 26`.
String formatTimingDateShort(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${_timingMonths[local.month - 1]} ${local.day}';
}

/// Full local date like `Nov 26, 2026`.
String formatTimingDateFull(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${formatTimingDateShort(local)}, ${local.year}';
}

/// Local date and time like `Nov 26 · 8:15 AM` (or `Nov 26, 2026 · 8:15 AM`).
String formatTimingDateTime(DateTime timestamp, {bool includeYear = false}) {
  final local = timestamp.toLocal();
  final datePart =
      includeYear ? formatTimingDateFull(local) : formatTimingDateShort(local);
  return '$datePart · ${formatTimingClock(local)}';
}

/// Formats a Start -> Finish/Stop range with date and time.
String formatTimingRange(
  DateTime start,
  DateTime? end, {
  bool includeYear = false,
}) {
  final localStart = start.toLocal();
  if (end == null || !end.isAfter(start)) {
    return formatTimingDateTime(localStart, includeYear: includeYear);
  }
  final localEnd = end.toLocal();
  final sameDay = localStart.year == localEnd.year &&
      localStart.month == localEnd.month &&
      localStart.day == localEnd.day;
  if (sameDay) {
    final datePart = includeYear
        ? formatTimingDateFull(localStart)
        : formatTimingDateShort(localStart);
    return '$datePart · ${formatTimingClock(localStart)} – ${formatTimingClock(localEnd)}';
  }
  return '${formatTimingDateTime(localStart, includeYear: includeYear)} – ${formatTimingDateTime(localEnd, includeYear: includeYear)}';
}

/// Human-friendly elapsed duration like `< 1m`, `12m`, or `1h 30m`.
String formatTimingDurationHuman(DateTime start, DateTime end) {
  final mins = end.difference(start).inMinutes;
  if (mins <= 0) return '< 1m';
  final hours = mins ~/ 60;
  final rem = mins % 60;
  if (hours == 0) return '${mins}m';
  if (rem == 0) return '${hours}h';
  return '${hours}h ${rem}m';
}

/// Merges server and local timing pairs so a restarted local session (newer start)
/// is never reverted by an older server session during background sync.
(DateTime?, DateTime?) mergeWorkTimingTimestamps({
  required DateTime? serverStart,
  required DateTime? serverEnd,
  required DateTime? localStart,
  required DateTime? localEnd,
}) {
  final sStart = normalizeTimingTimestamp(serverStart);
  final sEnd = normalizeTimingTimestamp(serverEnd);
  final lStart = normalizeTimingTimestamp(localStart);
  final lEnd = normalizeTimingTimestamp(localEnd);

  if (sStart == null && lStart == null) {
    return (null, sEnd ?? lEnd);
  }
  if (sStart == null) {
    return (lStart, lEnd);
  }
  if (lStart == null) {
    return (sStart, sEnd);
  }
  if (lStart.isAfter(sStart)) {
    return (lStart, lEnd);
  }
  if (sStart.isAfter(lStart)) {
    return (sStart, sEnd);
  }

  // Same start timestamp: keep whichever has a completed (strictly later) end.
  final sFinished = sEnd != null && sEnd.isAfter(sStart);
  final lFinished = lEnd != null && lEnd.isAfter(lStart);
  if (sFinished && lFinished) {
    return (sStart, lEnd.isAfter(sEnd) ? lEnd : sEnd);
  }
  if (sFinished) return (sStart, sEnd);
  if (lFinished) return (lStart, lEnd);
  return (sStart, sEnd ?? lEnd);
}

/// Resolves a stable user ID for timing endpoints and `work_timing_history`.
String resolveTimingUserId({String? override, String? fallbackEmail}) {
  final explicit = override?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final user = AuthSignals.instance.currentUser.value;
  if (user != null) {
    if (user.id > 0) return user.id.toString();
    if (user.email.trim().isNotEmpty) return user.email.trim();
  }
  final email = fallbackEmail?.trim();
  if (email != null && email.isNotEmpty) return email;
  return '0';
}

/// Resolves the technician display name for local timing history attribution.
String? resolveTimingUserName({String? fallbackEmail}) {
  final fullName = AuthSignals.instance.currentUser.value?.fullName.trim();
  if (fullName != null && fullName.isNotEmpty) return fullName;
  final username = AuthSignals.instance.currentUser.value?.username.trim();
  if (username != null && username.isNotEmpty) return username;
  final email = fallbackEmail?.trim();
  if (email != null && email.isNotEmpty) return email;
  return null;
}

/// Compact list-row timing bar with `Start` -> `Finish`/`Stop` -> `Start Again`.
class WorkTimingBar extends StatelessWidget {
  final WorkTimingStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool isBusy;
  // Gene - Nov, 26, 2026: Added hideStart and lockedHint so other cards hide Start while another Job/Service Order is active.
  final bool hideStart;
  final String? lockedHint;
  // Gene - Nov, 26, 2026: Added finishLabel ('Finish'/'Stop'), restartLabel ('Start Again'), accentColor, and sessionCount.
  final String finishLabel;
  final String restartLabel;
  final Color? accentColor;
  final int? sessionCount;
  final Key? startButtonKey;
  final Key? finishButtonKey;
  final Key? finishedButtonKey;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;

  /*
  const WorkTimingBar({
    super.key,
    required this.status,
    this.startTime,
    this.endTime,
    this.isBusy = false,
    this.startButtonKey,
    this.finishButtonKey,
    this.finishedButtonKey,
    this.onStart,
    this.onFinish,
  });
  */
  const WorkTimingBar({
    super.key,
    required this.status,
    this.startTime,
    this.endTime,
    this.isBusy = false,
    this.hideStart = false,
    this.lockedHint,
    this.finishLabel = 'Finish',
    this.restartLabel = 'Start Again',
    this.accentColor,
    this.sessionCount,
    this.startButtonKey,
    this.finishButtonKey,
    this.finishedButtonKey,
    this.onStart,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStart = normalizeTimingTimestamp(startTime);
    final normalizedEnd = normalizeTimingTimestamp(endTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryInk = AppTheme.secondaryInkOf(context);

    /*
    final (IconData statusIcon, Color statusColor, String summaryText) =
        switch (status) {
      WorkTimingStatus.notStarted => (
          Icons.lock_outline_rounded,
          secondaryInk,
          hideStart
              ? (lockedHint ?? 'Finish active order first')
              : 'Tap Start to unlock',
        ),
      WorkTimingStatus.inProgress => (
          Icons.timer_outlined,
          AppTheme.infoInkOf(context),
          normalizedStart != null
              ? 'Started ${formatTimingClock(normalizedStart)}'
              : 'In progress',
        ),
      WorkTimingStatus.finished => (
          Icons.check_circle_outline_rounded,
          AppTheme.successInkOf(context),
          normalizedStart != null && normalizedEnd != null
              ? '${formatTimingClock(normalizedStart)} – ${formatTimingClock(normalizedEnd)}'
              : 'Finished',
        ),
    };
    */
    // Gene - Nov, 26, 2026: Display date + time in WorkTimingBar summary and append session count when restarted.
    final sessionsSuffix =
        (sessionCount != null && sessionCount! > 1) ? ' · $sessionCount×' : '';
    final (IconData statusIcon, Color statusColor, String summaryText) =
        switch (status) {
      WorkTimingStatus.notStarted => (
          Icons.lock_outline_rounded,
          secondaryInk,
          hideStart
              ? (lockedHint ?? 'Finish active order first')
              : 'Tap Start to unlock',
        ),
      WorkTimingStatus.inProgress => (
          Icons.timer_outlined,
          accentColor != null
              ? AppTheme.serviceOrderInkOf(context)
              : AppTheme.infoInkOf(context),
          normalizedStart != null
              ? 'Started ${formatTimingDateTime(normalizedStart)}$sessionsSuffix'
              : 'In progress',
        ),
      /*
      WorkTimingStatus.finished => (
          Icons.check_circle_outline_rounded,
          AppTheme.successInkOf(context),
          normalizedStart != null && normalizedEnd != null
              ? '${formatTimingRange(normalizedStart, normalizedEnd)}$sessionsSuffix'
              : 'Finished$sessionsSuffix',
        ),
      */
      // Gene - Nov, 28, 2026: Append lockedHint on finished cards when another active order hides Start Again.
      WorkTimingStatus.finished => (
          Icons.check_circle_outline_rounded,
          AppTheme.successInkOf(context),
          () {
            final base = (normalizedStart != null && normalizedEnd != null)
                ? '${formatTimingRange(normalizedStart, normalizedEnd)}$sessionsSuffix'
                : 'Finished$sessionsSuffix';
            if (!hideStart) return base;
            return '$base · ${lockedHint ?? 'Finish active order first'}';
          }(),
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 20, color: statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  summaryText,
                  style: context.text.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          _buildActionButton(context, isDark),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool isDark) {
    final effectiveAccent = accentColor ?? AppTheme.primary;
    switch (status) {
      case WorkTimingStatus.notStarted:
        // Gene - Nov, 26, 2026: Hide Start button when another Job Order or Service Order is already started.
        if (hideStart) return const SizedBox.shrink();
        return FilledButton.icon(
          key: startButtonKey,
          onPressed: isBusy ? null : onStart,
          style: FilledButton.styleFrom(
            backgroundColor: effectiveAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(112, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text('Start'),
        );

      case WorkTimingStatus.inProgress:
        return FilledButton.icon(
          key: finishButtonKey,
          onPressed: isBusy ? null : onFinish,
          style: FilledButton.styleFrom(
            backgroundColor: accentColor ?? AppTheme.infoInkOf(context),
            foregroundColor: Colors.white,
            minimumSize: const Size(112, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.stop_rounded, size: 20),
          // Gene - Nov, 26, 2026: Render 'Finish' for Job Orders or 'Stop' for Service Orders.
          label: Text(finishLabel),
        );

      case WorkTimingStatus.finished:
        /*
        return OutlinedButton.icon(
          key: finishedButtonKey,
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.successInkOf(context),
            disabledForegroundColor:
                isDark ? AppTheme.secondaryInkDark : AppTheme.secondaryInk,
            backgroundColor: AppTheme.fillOf(context),
            side: BorderSide(color: AppTheme.hairlineOf(context)),
            minimumSize: const Size(112, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 20),
          label: const Text('Finished'),
        );
        */
        // Gene - Nov, 26, 2026: Allow restarting a finished/stopped order (recording a new session) unless another order is active.
        if (hideStart) return const SizedBox.shrink();
        return FilledButton.icon(
          key: startButtonKey ?? finishedButtonKey,
          onPressed: isBusy ? null : onStart,
          style: FilledButton.styleFrom(
            backgroundColor: effectiveAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(124, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.replay_rounded, size: 20),
          label: Text(restartLabel),
        );
    }
  }
}

/// Detail-screen banner communicating why reporting/editing is locked or unlocked.
class WorkTimingLockBanner extends StatelessWidget {
  final WorkTimingStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  // Gene - Nov, 26, 2026: Optional action label ('Finish' / 'Stop') for detail-screen banner instructions.
  final String finishLabel;

  const WorkTimingLockBanner({
    super.key,
    required this.status,
    this.startTime,
    this.endTime,
    this.finishLabel = 'Finish',
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStart = normalizeTimingTimestamp(startTime);
    final normalizedEnd = normalizeTimingTimestamp(endTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    /*
    final (
      IconData icon,
      Color inkColor,
      Color bgColor,
      Color borderColor,
      String title,
      String subtitle,
    ) = switch (status) {
      WorkTimingStatus.notStarted => (
          Icons.lock_outline_rounded,
          AppTheme.warningInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.warningSubtle,
          isDark
              ? AppTheme.borderDark
              : AppTheme.warning.withValues(alpha: 0.45),
          'Locked until started',
          'Go back to the list and tap Start to record your arrival time and unlock reporting.',
        ),
      WorkTimingStatus.inProgress => (
          Icons.timer_outlined,
          AppTheme.infoInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.infoSubtle,
          isDark ? AppTheme.borderDark : AppTheme.info.withValues(alpha: 0.35),
          normalizedStart != null
              ? 'Started ${formatTimingClock(normalizedStart)} · Editing unlocked'
              : 'Work in progress · Editing unlocked',
          'Tap Finish on the list item when done to lock and record the end time.',
        ),
      WorkTimingStatus.finished => (
          Icons.lock_clock_outlined,
          AppTheme.successInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.successSubtle,
          isDark
              ? AppTheme.borderDark
              : AppTheme.success.withValues(alpha: 0.35),
          normalizedStart != null && normalizedEnd != null
              ? 'Finished (${formatTimingClock(normalizedStart)} – ${formatTimingClock(normalizedEnd)})'
              : 'Work finished · Editing locked',
          'Timing is complete. Reporting and status edits are now locked.',
        ),
    };
    */
    // Gene - Nov, 26, 2026: Show date+time in lock banner and inform technician they can tap Start Again on the list to reopen.
    final (
      IconData icon,
      Color inkColor,
      Color bgColor,
      Color borderColor,
      String title,
      String subtitle,
    ) = switch (status) {
      WorkTimingStatus.notStarted => (
          Icons.lock_outline_rounded,
          AppTheme.warningInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.warningSubtle,
          isDark
              ? AppTheme.borderDark
              : AppTheme.warning.withValues(alpha: 0.45),
          'Locked until started',
          'Go back to the list and tap Start to record your arrival date & time and unlock reporting.',
        ),
      WorkTimingStatus.inProgress => (
          Icons.timer_outlined,
          AppTheme.infoInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.infoSubtle,
          isDark ? AppTheme.borderDark : AppTheme.info.withValues(alpha: 0.35),
          normalizedStart != null
              ? 'Started ${formatTimingDateTime(normalizedStart, includeYear: true)} · Editing unlocked'
              : 'Work in progress · Editing unlocked',
          'Tap $finishLabel on the list item when done to lock and record the end date & time.',
        ),
      WorkTimingStatus.finished => (
          Icons.lock_clock_outlined,
          AppTheme.successInkOf(context),
          isDark ? AppTheme.darkCardElevated : AppTheme.successSubtle,
          isDark
              ? AppTheme.borderDark
              : AppTheme.success.withValues(alpha: 0.35),
          normalizedStart != null && normalizedEnd != null
              ? 'Recorded (${formatTimingRange(normalizedStart, normalizedEnd, includeYear: true)})'
              : 'Work session recorded · Editing locked',
          'Timing session recorded. Go back to the list and tap Start Again to reopen and record another session.',
        ),
    };

    // Keep unlocked banner compact on detail screens so above-the-fold cards stay reachable.
    final verticalPadding = status == WorkTimingStatus.inProgress ? 8.0 : 12.0;

    return Container(
      margin: EdgeInsets.only(
          bottom: status == WorkTimingStatus.inProgress ? 8 : 12),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: inkColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.text.titleSmall?.copyWith(
                    color: inkColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status != WorkTimingStatus.inProgress) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.text.bodySmall?.copyWith(
                      color: AppTheme.secondaryInkOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Gene - Nov, 28, 2026: Shared Calm Utility banner surfaced at the top of Today & Repairs when an active order is running (even if hidden by filters or on the opposite tab), with a direct Finish action.
/// Compact banner displaying the currently started Job Order or Service Order
/// with a one-tap `Finish` control so technicians are never stranded when the
/// active order is on the other tab or hidden by filters.
class ActiveWorkOrderBanner extends StatelessWidget {
  final String orderLabel;
  final DateTime? startTime;
  final bool isBusy;
  final bool isServiceOrder;
  final VoidCallback? onFinish;

  const ActiveWorkOrderBanner({
    super.key,
    required this.orderLabel,
    this.startTime,
    this.isBusy = false,
    this.isServiceOrder = false,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStart = normalizeTimingTimestamp(startTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? AppTheme.darkCardElevated
        : (isServiceOrder
            ? AppTheme.serviceOrderSubtleBgOf(context)
            : AppTheme.infoSubtle);
    final borderColor = isServiceOrder
        ? AppTheme.serviceOrderSubtleBorderOf(context)
        : (isDark
            ? AppTheme.borderDark
            : AppTheme.info.withValues(alpha: 0.4));
    final accentInk = isServiceOrder
        ? AppTheme.serviceOrderInkOf(context)
        : AppTheme.infoInkOf(context);
    final buttonColor = isServiceOrder
        ? AppTheme.serviceOrderAccent
        : AppTheme.infoInkOf(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.timer_outlined, size: 20, color: accentInk),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active: $orderLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge?.copyWith(
                        color: accentInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (normalizedStart != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Started ${formatTimingDateTime(normalizedStart)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          FilledButton.icon(
            key: const ValueKey('active_order_banner_finish_button'),
            onPressed: isBusy ? null : onFinish,
            style: FilledButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(104, AppTheme.minTarget),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.stop_rounded, size: 20),
            label: const Text('Finish'),
          ),
        ],
      ),
    );
  }
}
