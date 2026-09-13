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

  const TodayGlancePanel({
    super.key,
    required this.jobCount,
    required this.summary,
    this.actions = const [],
    this.now,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
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
                          style: context.text.displaySmall,
                          semanticsLabel: '$jobCount jobs today',
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            jobCount == 1 ? 'job today' : 'jobs today',
                            style: context.text.titleMedium!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
