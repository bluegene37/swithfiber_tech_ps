import 'package:flutter/material.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';

/// The read-only top of the Today home (DESIGN.md, Screen placement): the
/// date, the day's job count as the hero number, one summary line, and the
/// screen's ink icon actions on the right. No app bar sits above it.
class TodayGlancePanel extends StatelessWidget {
  final int jobCount;
  final String summary;
  final List<Widget> actions;

  /// Injectable for tests; defaults to the current time.
  final DateTime? now;

  // Gene - Nov, 26, 2026: Optional labels, type badge, and count color so ServiceOrdersScreen shares the same Glance header with distinct branding.
  final String singularLabel;
  final String pluralLabel;
  final Widget? typeBadge;
  final Color? countColor;

  /*
  const TodayGlancePanel({
    super.key,
    required this.jobCount,
    required this.summary,
    this.actions = const [],
    this.now,
  });
  */
  const TodayGlancePanel({
    super.key,
    required this.jobCount,
    required this.summary,
    this.actions = const [],
    this.now,
    this.singularLabel = 'job today',
    this.pluralLabel = 'jobs today',
    this.typeBadge,
    this.countColor,
  });

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
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

  /// `Friday · 5 Sep`, built without a locale package so it works offline
  /// and identically on both platforms.
  static String dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} · ${d.day} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final date = dateLabel(now ?? DateTime.now());
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stackActionsBelow = scale > 1.3 && actions.length > 3;

    final headerInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          date.toUpperCase(),
          style: context.text.labelMedium!.copyWith(
            color: AppTheme.secondaryInkOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$jobCount',
              style: context.text.displaySmall!.copyWith(
                color: countColor,
              ),
              semanticsLabel:
                  '$jobCount ${jobCount == 1 ? singularLabel : pluralLabel}',
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                jobCount == 1 ? singularLabel : pluralLabel,
                style: context.text.titleMedium!.copyWith(
                  color: AppTheme.secondaryInkOf(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 8, typeBadge != null ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gene - Nov, 26, 2026: Render typeBadge at full panel width above the date/actions row so badges never squeeze or overflow at 200% text scale.
          if (typeBadge != null) ...[
            typeBadge!,
            const SizedBox(height: 4),
          ],
          // Gene - Nov, 28, 2026: Stack icon actions cleanly below count when large text scale + multiple actions would squeeze date/count vertically.
          if (stackActionsBelow) ...[
            headerInfo,
            if (actions.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(children: actions),
              ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: headerInfo),
                // Actions stay in a Wrap so a large text setting never pushes
                // them off the row.
                Wrap(children: actions),
              ],
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(summary, style: context.text.bodyMedium),
          ),
        ],
      ),
    );
  }
}
