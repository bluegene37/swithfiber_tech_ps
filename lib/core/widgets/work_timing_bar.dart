import 'package:flutter/material.dart';

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

/// Compact list-row timing bar with `Start` -> `Finish` -> disabled `Finished`.
class WorkTimingBar extends StatelessWidget {
  final WorkTimingStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool isBusy;
  final Key? startButtonKey;
  final Key? finishButtonKey;
  final Key? finishedButtonKey;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;

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

  @override
  Widget build(BuildContext context) {
    final normalizedStart = normalizeTimingTimestamp(startTime);
    final normalizedEnd = normalizeTimingTimestamp(endTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryInk = AppTheme.secondaryInkOf(context);

    final (IconData statusIcon, Color statusColor, String summaryText) =
        switch (status) {
      WorkTimingStatus.notStarted => (
          Icons.lock_outline_rounded,
          secondaryInk,
          'Tap Start to unlock',
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
    switch (status) {
      case WorkTimingStatus.notStarted:
        return FilledButton.icon(
          key: startButtonKey,
          onPressed: isBusy ? null : onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
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
            backgroundColor: AppTheme.infoInkOf(context),
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
          label: const Text('Finish'),
        );

      case WorkTimingStatus.finished:
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
    }
  }
}

/// Detail-screen banner communicating why reporting/editing is locked or unlocked.
class WorkTimingLockBanner extends StatelessWidget {
  final WorkTimingStatus status;
  final DateTime? startTime;
  final DateTime? endTime;

  const WorkTimingLockBanner({
    super.key,
    required this.status,
    this.startTime,
    this.endTime,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStart = normalizeTimingTimestamp(startTime);
    final normalizedEnd = normalizeTimingTimestamp(endTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
