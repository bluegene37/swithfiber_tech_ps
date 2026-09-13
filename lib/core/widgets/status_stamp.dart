import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// The outline status stamp for detail headers (DESIGN.md, Layout): a 1.5px
/// border, a 6px radius and one uppercase word in the status ink. Replaces
/// the filled status pills.
class StatusStamp extends StatelessWidget {
  final String label;
  final Color color;

  const StatusStamp({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
        ),
        child: Text(
          label.toUpperCase(),
          style: context.text.labelMedium!.copyWith(color: color),
          maxLines: 1,
        ),
      ),
    );
  }
}
