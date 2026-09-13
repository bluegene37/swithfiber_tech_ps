import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// A numbered step title for long forms (DESIGN.md, completion report):
/// a 28dp badge with the step number, or a tick once the step is done, then
/// the title. The badge is the progress rail; no separate stepper widget.
class StepHeader extends StatelessWidget {
  final int number;
  final String title;
  final bool done;

  /// Shown after the title in secondary ink, e.g. `optional` or `4 / 7`.
  final String? hint;

  const StepHeader({
    super.key,
    required this.number,
    required this.title,
    this.done = false,
    this.hint,
  });

  static const double badgeSize = 28;

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.inkOf(context);
    final page = AppTheme.pageOf(context);
    final hairline = AppTheme.hairlineOf(context);

    return Row(
      children: [
        Semantics(
          label: done ? 'Step $number done' : 'Step $number',
          child: Container(
            width: badgeSize,
            height: badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? ink : Colors.transparent,
              border: Border.all(color: done ? ink : hairline, width: 1.5),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 18, color: page)
                : Text(
                    '$number',
                    style: context.text.labelMedium!.copyWith(color: ink),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: context.text.titleMedium),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Text(
            hint!,
            style: context.text.bodyLarge!
                .copyWith(color: AppTheme.secondaryInkOf(context)),
          ),
        ],
      ],
    );
  }
}
