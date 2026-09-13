import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Dialogs and action sheets that take the platform's own shape (DESIGN.md,
/// Platform adaptivity): a Cupertino alert or action sheet on iOS, a
/// Material dialog or bottom sheet on Android. Every screen that needs a
/// confirmation goes through here so the two platforms never drift.

bool _isCupertino(BuildContext context) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// One dialog action rendered as a [CupertinoDialogAction] on iOS and a
/// [TextButton] on Android.
Widget adaptiveDialogAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool isDefault = false,
  bool isDestructive = false,
}) {
  if (_isCupertino(context)) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDefaultAction: isDefault,
      isDestructiveAction: isDestructive,
      child: Text(label),
    );
  }
  final scheme = Theme.of(context).colorScheme;
  return TextButton(
    onPressed: onPressed,
    style: isDestructive
        ? TextButton.styleFrom(foregroundColor: scheme.error)
        : null,
    child: Text(label),
  );
}

/// A yes / no question. Resolves true when the technician confirms, false
/// or null when they cancel or dismiss.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) {
  return showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: Padding(
        padding: EdgeInsets.only(top: _isCupertino(ctx) ? 6 : 0),
        child: Text(message),
      ),
      actions: [
        adaptiveDialogAction(
          ctx,
          label: cancelLabel,
          isDefault: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        adaptiveDialogAction(
          ctx,
          label: confirmLabel,
          isDestructive: destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
}

/// A single-line text field that matches the dialog it sits in.
Widget adaptiveDialogTextField(
  BuildContext context, {
  required TextEditingController controller,
  required String placeholder,
  bool obscureText = false,
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
}) {
  if (_isCupertino(context)) {
    return CupertinoTextField(
      controller: controller,
      obscureText: obscureText,
      autofocus: autofocus,
      placeholder: placeholder,
      onSubmitted: onSubmitted,
    );
  }
  return TextField(
    controller: controller,
    obscureText: obscureText,
    autofocus: autofocus,
    decoration: InputDecoration(hintText: placeholder),
    onSubmitted: onSubmitted,
  );
}

/// One row of an [showAdaptiveActionSheet].
class AdaptiveSheetAction {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isDefault;
  final bool isDestructive;

  const AdaptiveSheetAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDefault = false,
    this.isDestructive = false,
  });
}

/// A short list of choices about one thing, e.g. "Dial now / Copy number".
/// Cupertino action sheet on iOS; Material bottom sheet of 56dp rows on
/// Android. Each action closes the sheet before it runs.
Future<void> showAdaptiveActionSheet(
  BuildContext context, {
  required String title,
  String? message,
  required List<AdaptiveSheetAction> actions,
  String cancelLabel = 'Cancel',
}) {
  if (_isCupertino(context)) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: message == null ? null : Text(message),
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                a.onPressed();
              },
              isDefaultAction: a.isDefault,
              isDestructiveAction: a.isDestructive,
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(cancelLabel),
        ),
      ),
    );
  }
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (message != null) ...[
                  const SizedBox(height: 4),
                  Text(message, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          for (final a in actions)
            ListTile(
              minTileHeight: 56,
              leading: a.icon == null ? null : Icon(a.icon),
              title: Text(
                a.label,
                style: a.isDestructive
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                a.onPressed();
              },
            ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.close_rounded),
            title: Text(cancelLabel),
            onTap: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
