import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// The one red verb on a screen (DESIGN.md, Layout): a 64dp primary button
/// pinned to the bottom, with an optional line above it that says why the
/// action is unavailable instead of greying it out silently.
class StickyActionBar extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Shown above the button, e.g. `3 of 7 photos missing`. Always visible
  /// when set, so the technician knows what to do next.
  final String? why;

  const StickyActionBar({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.why,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      height: AppTheme.stickyBarHeight,
      child: icon == null
          ? ElevatedButton(onPressed: onPressed, child: Text(label))
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 24),
              label: Text(label),
            ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pageOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.hairlineOf(context), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (why != null && why!.isNotEmpty) ...[
                Text(
                  why!,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              button,
            ],
          ),
        ),
      ),
    );
  }
}
