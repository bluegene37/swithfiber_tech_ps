import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_rail_row.dart';
import '../models/job_order_model.dart';

/// One row of the technician's done-job history, in the same anatomy as the
/// scheduled rows on Today (DESIGN.md, Screen placement): the date in the
/// mono left column where a scheduled row shows its distance, a status rail,
/// the subscriber, the place, the ticket as the data line and one status
/// word. No pills, no chevron, no icon-in-a-circle.
class JobHistoryTile extends StatelessWidget {
  final JobOrderDto job;
  final VoidCallback? onTap;

  const JobHistoryTile({super.key, required this.job, this.onTap});

  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _dayFormat = DateFormat('MMM d');
  static final _yearFormat = DateFormat('yyyy');

  /// The full date for [job], or null when nothing is known.
  static String? dateLabel(JobOrderDto job) {
    final d = job.historyDate;
    return d == null ? null : _dateFormat.format(d);
  }

  /// The two-line date for the 56dp mono column: `Sep 5` over `2026`.
  static String leadingLabel(JobOrderDto job) {
    final d = job.historyDate;
    if (d == null) return 'No\ndate';
    return '${_dayFormat.format(d)}\n${_yearFormat.format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final (label, rail, ink) = historyStatusWord(context, job);
    final place = [
      job.address.trim(),
      if (job.barangay?.isNotEmpty == true) job.barangay!,
      if (job.city?.isNotEmpty == true) job.city!,
    ].where((s) => s.isNotEmpty).join(', ');
    final power = job.opticalPower;
    // Above a 1.2 text scale the 56dp mono column cannot hold `2026`, so the
    // column keeps only the day and the full date moves to the footnote.
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.2;
    final d = job.historyDate;
    final footnote = [
      if (large) dateLabel(job) ?? 'No date recorded',
      if (job.planName?.isNotEmpty == true) job.planName!,
      if (power != null) '${power.toStringAsFixed(1)} dBm',
    ].join(' · ');

    return StatusRailRow(
      leading: large
          ? (d == null ? 'No\ndate' : _dayFormat.format(d))
          : leadingLabel(job),
      railColor: rail,
      statusInk: ink,
      title: job.customerName,
      subtitle: place.isEmpty ? null : place,
      data: job.ticketNumber,
      footnote: footnote.isEmpty ? null : footnote,
      statusLabel: label,
      onTap: onTap,
    );
  }
}

/// The one status word for a done job and its rail and ink colours. A
/// pending sync or a site exception outranks the plain done state, because
/// that is what the technician still has to act on.
(String, Color, Color) historyStatusWord(BuildContext context, JobOrderDto j) {
  if (!j.isSynced) {
    return ('Pending sync', AppTheme.warning, AppTheme.warningInkOf(context));
  }
  switch (j.siteException) {
    case SiteException.failed:
      return ('Failed', AppTheme.danger, AppTheme.dangerInkOf(context));
    case SiteException.reschedule:
      return ('Reschedule', AppTheme.warning, AppTheme.warningInkOf(context));
    case null:
      break;
  }
  if (j.isCompleted) {
    return ('Completed', AppTheme.success, AppTheme.successInkOf(context));
  }
  if (j.isActivated) {
    return ('Activated', AppTheme.success, AppTheme.successInkOf(context));
  }
  final raw = j.status.trim();
  return (
    raw.isEmpty ? 'Done' : raw,
    AppTheme.success,
    AppTheme.successInkOf(context),
  );
}
