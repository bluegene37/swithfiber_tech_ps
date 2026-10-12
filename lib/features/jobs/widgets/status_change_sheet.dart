import 'package:flutter/material.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../models/job_order_model.dart';

/// What the technician chose on the [StatusChangeSheet].
class StatusChange {
  final JobStatus status;

  /// The reason, from [RescheduleReasons], when [status] is
  /// [JobStatus.rescheduled]; null otherwise.
  final String? statusRemarks;

  const StatusChange({required this.status, this.statusRemarks});
}

/// Bottom sheet where the technician moves an open job between Scheduled
/// and Rescheduled. Picking Rescheduled reveals the status remarks, which
/// is a fixed list of reasons rather than free text so the office can
/// count them.
class StatusChangeSheet extends StatefulWidget {
  final JobStatus current;
  final String? currentRemarks;

  const StatusChangeSheet({
    super.key,
    required this.current,
    this.currentRemarks,
  });

  /// Presents the sheet; resolves to the chosen change, or null when closed
  /// without saving.
  static Future<StatusChange?> show(
    BuildContext context, {
    required JobStatus current,
    String? currentRemarks,
  }) {
    return showModalBottomSheet<StatusChange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatusChangeSheet(
        current: current,
        currentRemarks: currentRemarks,
      ),
    );
  }

  @override
  State<StatusChangeSheet> createState() => _StatusChangeSheetState();
}

class _StatusChangeSheetState extends State<StatusChangeSheet> {
/*
  late JobStatus _status = widget.current == JobStatus.rescheduled
      ? JobStatus.rescheduled
      : JobStatus.scheduled;
*/
  // Gene - Oct 12, 2026: Added In Progress status option matching AppSheet Onsite Status flow.
  late JobStatus _status = widget.current == JobStatus.rescheduled
      ? JobStatus.rescheduled
      : (widget.current == JobStatus.inProgress
          ? JobStatus.inProgress
          : JobStatus.scheduled);
  late String? _reason = RescheduleReasons.all.contains(widget.currentRemarks)
      ? widget.currentRemarks
      : null;

  bool get _isRescheduled => _status == JobStatus.rescheduled;

  /// Scheduled needs nothing more; Rescheduled needs a reason.
  bool get _canSave => !_isRescheduled || _reason != null;

  void _save() {
    Navigator.of(context).pop(StatusChange(
      status: _status,
      statusRemarks: _isRescheduled ? _reason : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkCard : Colors.white;
    final muted = AppTheme.secondaryInkOf(context);

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.event_repeat_rounded,
                      size: 22, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Change status',
                      style: context.text.titleMedium!
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
/*
                  _OptionRow(
                    key: const ValueKey('status_option_scheduled'),
                    label: JobStatus.scheduled.label,
                    hint: 'Visit goes ahead as planned',
                    icon: Icons.calendar_today_rounded,
                    selected: !_isRescheduled,
                    onTap: () => setState(() => _status = JobStatus.scheduled),
                  ),
                  _OptionRow(
                    key: const ValueKey('status_option_rescheduled'),
                    label: JobStatus.rescheduled.label,
                    hint: 'Visit could not go ahead today',
                    icon: Icons.event_repeat_rounded,
                    selected: _isRescheduled,
                    onTap: () =>
                        setState(() => _status = JobStatus.rescheduled),
                  ),
*/
                  // Gene - Oct 12, 2026: Added In Progress option alongside Scheduled and Rescheduled.
                  _OptionRow(
                    key: const ValueKey('status_option_scheduled'),
                    label: JobStatus.scheduled.label,
                    hint: 'Visit goes ahead as planned',
                    icon: Icons.calendar_today_rounded,
                    selected: _status == JobStatus.scheduled,
                    onTap: () => setState(() => _status = JobStatus.scheduled),
                  ),
                  _OptionRow(
                    key: const ValueKey('status_option_inprogress'),
                    label: JobStatus.inProgress.label,
                    hint: 'Technician currently working on site',
                    icon: Icons.pending_actions_rounded,
                    selected: _status == JobStatus.inProgress,
                    onTap: () => setState(() => _status = JobStatus.inProgress),
                  ),
                  _OptionRow(
                    key: const ValueKey('status_option_rescheduled'),
                    label: JobStatus.rescheduled.label,
                    hint: 'Visit could not go ahead today',
                    icon: Icons.event_repeat_rounded,
                    selected: _isRescheduled,
                    onTap: () =>
                        setState(() => _status = JobStatus.rescheduled),
                  ),
                  // Status remarks: only once Rescheduled is chosen, and only
                  // from the list. No free text.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _isRescheduled
                        ? Column(
                            key: const ValueKey('status_remarks_field'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 1),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 14, 20, 4),
                                child: Text(
                                  'STATUS REMARKS',
                                  style: context.text.labelMedium!
                                      .copyWith(color: muted),
                                ),
                              ),
                              for (final reason in RescheduleReasons.all)
                                _OptionRow(
                                  key: ValueKey('status_reason_$reason'),
                                  label: reason,
                                  icon: Icons.notes_rounded,
                                  selected: _reason == reason,
                                  onTap: () => setState(() => _reason = reason),
                                ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const ValueKey('status_change_save'),
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(_isRescheduled && _reason == null
                      ? 'Pick a reason to save'
                      : 'Save status'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ticked row: leading icon in a tinted box, the label, an optional hint
/// line, and a check when selected. 48dp minimum.
class _OptionRow extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: ListTile(
        minTileHeight: AppTheme.minTarget,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primarySubtleBgOf(context)
                : AppTheme.fillOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color:
                selected ? AppTheme.primary : AppTheme.secondaryInkOf(context),
          ),
        ),
        title: Text(
          label,
          style: context.text.titleSmall!.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppTheme.brandInkOf(context) : null,
          ),
        ),
        subtitle:
            hint == null ? null : Text(hint!, style: context.text.bodySmall),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded,
                color: AppTheme.primary, size: 20)
            : null,
        onTap: onTap,
      ),
    );
  }
}
