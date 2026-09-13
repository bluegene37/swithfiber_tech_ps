import 'package:flutter/material.dart';

/// The `Navigate | Call` pair under a detail header (DESIGN.md, Job detail):
/// two 56dp buttons side by side, or stacked past a 1.2 text scale so both
/// labels stay on one line. When there is no secondary action the primary
/// spans the full width. Shared by the job and service order details so the
/// pair sits in the same place with the same labels on both screens.
class ActionPair extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;

  const ActionPair({super.key, required this.primary, this.secondary});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (secondary == null) {
      return SizedBox(width: double.infinity, child: primary);
    }
    if (scale > 1.2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 10), secondary!],
      );
    }
    return Row(
      children: [
        Expanded(child: primary),
        const SizedBox(width: 10),
        Expanded(child: secondary!),
      ],
    );
  }
}
