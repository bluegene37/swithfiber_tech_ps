// Gene - Nov, 12, 2026: Created Calm Utility extended floating pill button for bottom-anchored Add actions on Plant and Cabinet screens.

import 'package:flutter/material.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';

/// Calm Utility bottom-floating extended pill button ("Read at the top, act at
/// the bottom" & "Red is a verb" in DESIGN.md).
///
/// Uses [Flexible] text and [ConstrainedBox] rather than [FloatingActionButton.extended]
/// so the button grows vertically and wraps cleanly up to 200% font scale on narrow
/// 402dp phones without overflowing.
class LcpNapFloatingAddButton extends StatelessWidget {
  final Key? buttonKey;
  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final double? maxWidth;

  const LcpNapFloatingAddButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final capWidth = maxWidth ?? (MediaQuery.sizeOf(context).width - 32);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 52,
        maxWidth: capWidth > 120 ? capWidth : 120,
      ),
      child: ElevatedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: AppTheme.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(AppTheme.minTarget, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: StadiumBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppTheme.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: context.text.labelLarge!.copyWith(
                  color: AppTheme.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
