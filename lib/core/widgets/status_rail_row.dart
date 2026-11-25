import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// A plain list row from the Calm Utility system (DESIGN.md, Layout):
/// an optional mono lead (distance, time, ticket id), a 4px colour rail, the
/// title and subtitle, a mono data line, and the status as one word.
///
/// Status is never carried by colour alone: the rail sits next to the word.
/// The whole row is one 48dp+ target; there are no gestures hidden in it.
class StatusRailRow extends StatelessWidget {
  /// Short mono text in the 56dp left column, e.g. `2.4 km` or `SO-0873`.
  final String? leading;
  final Color railColor;

  /// Ink used for the status word; defaults to [railColor], which is fine
  /// for the ink tokens but should be an *Ink token for bright fills.
  final Color? statusInk;
  final String title;
  final String? subtitle;

  /// Mono line under the subtitle, e.g. `LCP 173 · NAP 008`.
  final String? data;

  /// Muted footnote under the data line, e.g. `SwitchUltra · -19.5 dBm`.
  final String? footnote;

  /// Any extra widget between the footnote and the status word, e.g. the
  /// contact line with its copy button on a job card.
  final Widget? extra;
  final String statusLabel;
  // Gene - Nov, 20, 2026: Added isNew flag to surface an unread NEW tag alongside the status label.
  final bool isNew;
  final Widget? trailing;
  // Gene - Oct 13, 2026: Added expandToggle widget placed on the card body before the partitioned trailing divider.
  final Widget? expandToggle;
  final VoidCallback? onTap;

  /// Optional strip of [StatusRailAction]s under the row, split evenly with
  /// hairlines between them: `Navigate | Call | SMS`. Actions sit at the
  /// bottom of the card (DESIGN.md: read at the top, act at the bottom).
  final List<Widget>? actions;

  // Gene - Nov, 25, 2026: Added optional timingBar slot above footer actions for Start/Finish work controls.
  final Widget? timingBar;

  // Gene - Nov, 26, 2026: Added optional card border, NEW badge styling/key, headerBadge, and rowTapKey for Service Order visual parity & distinction.
  final Color? borderColor;
  final double borderWidth;
  final Key? newTagKey;
  final Color? newTagBgColor;
  final Color? newTagBorderColor;
  final Color? newTagInkColor;
  final Widget? headerBadge;
  final Key? rowTapKey;

  /*
  const StatusRailRow({
    super.key,
    this.leading,
    required this.railColor,
    this.statusInk,
    required this.title,
    this.subtitle,
    this.data,
    this.footnote,
    this.extra,
    required this.statusLabel,
    this.trailing,
    this.onTap,
    this.actions,
  });
  */
  /*
  // Gene - Oct 13, 2026: Added expandToggle to StatusRailRow constructor.
  const StatusRailRow({
    super.key,
    this.leading,
    required this.railColor,
    this.statusInk,
    required this.title,
    this.subtitle,
    this.data,
    this.footnote,
    this.extra,
    required this.statusLabel,
    this.trailing,
    this.expandToggle,
    this.onTap,
    this.timingBar,
    this.actions,
  });
  */
  // Gene - Nov, 20, 2026: Added isNew parameter (default false) to StatusRailRow constructor.
  // Gene - Nov, 26, 2026: Added optional styling/key parameters for Service Order cards while keeping Job Order defaults intact.
  const StatusRailRow({
    super.key,
    this.leading,
    required this.railColor,
    this.statusInk,
    required this.title,
    this.subtitle,
    this.data,
    this.footnote,
    this.extra,
    required this.statusLabel,
    this.isNew = false,
    this.trailing,
    this.expandToggle,
    this.onTap,
    this.timingBar,
    this.actions,
    this.borderColor,
    this.borderWidth = 1,
    this.newTagKey,
    this.newTagBgColor,
    this.newTagBorderColor,
    this.newTagInkColor,
    this.headerBadge,
    this.rowTapKey,
  });

  static const double minHeight = 64;
  static const double leadingWidth = 56;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.hairlineOf(context);
    final wordInk = statusInk ?? railColor;

    return Material(
      color: AppTheme.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        /*
        side: BorderSide(color: hairline, width: 1),
        */
        // Gene - Nov, 26, 2026: Allow custom borderColor/borderWidth for Service Order cards.
        side: BorderSide(color: borderColor ?? hairline, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
/*
          InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                // The rail stretches to the text's height. Stretching needs a
                // bounded height, which a ListView never gives, so the row
                // measures itself first.
                child: IntrinsicHeight(
                    child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null)
                      SizedBox(
                        width: leadingWidth,
                        child: Text(
                          leading!,
                          style: context.text.bodyLarge!
                              .copyWith(fontWeight: FontWeight.w500),
                          // Three lines: a history date is `Sep 4` over `2026`,
                          // and at large text the month and day split too.
                          maxLines: 3,
                        ),
                      ),
                    Container(
                      width: 4,
                      margin: EdgeInsets.only(
                          right: 12, left: leading != null ? 0 : 0),
                      decoration: BoxDecoration(
                        color: railColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.text.titleMedium),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: context.text.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (data != null && data!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              data!,
                              style: context.text.bodyLarge!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                              ),
                              // A 21-digit ticket at large text breaks onto
                              // a second line rather than ending in "…".
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (footnote != null && footnote!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              footnote!,
                              style: context.text.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (extra != null) ...[
                            const SizedBox(height: 6),
                            extra!,
                          ],
                          const SizedBox(height: 6),
                          Text(
                            statusLabel.toUpperCase(),
                            style: context.text.labelMedium!
                                .copyWith(color: wordInk),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      Center(child: trailing),
                    ],
                  ],
                )),
              ),
            ),
          ),
*/
          // Gene - Oct 13, 2026: Positioned trailing outside the InkWell so trailing controls (e.g. expand chevron) never collide with or double-trigger the row onTap gesture.
          /*
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: minHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        12,
                        trailing != null ? 4 : 14,
                        12,
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (leading != null)
                              SizedBox(
                                width: leadingWidth,
                                child: Text(
                                  leading!,
                                  style: context.text.bodyLarge!
                                      .copyWith(fontWeight: FontWeight.w500),
                                  maxLines: 3,
                                ),
                              ),
                            Container(
                              width: 4,
                              margin: EdgeInsets.only(
                                  right: 12, left: leading != null ? 0 : 0),
                              decoration: BoxDecoration(
                                color: railColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: context.text.titleMedium),
                                  if (subtitle != null &&
                                      subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle!,
                                      style: context.text.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (data != null && data!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      data!,
                                      style: context.text.bodyLarge!.copyWith(
                                        color: AppTheme.secondaryInkOf(context),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (footnote != null &&
                                      footnote!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      footnote!,
                                      style: context.text.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (extra != null) ...[
                                    const SizedBox(height: 6),
                                    extra!,
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    statusLabel.toUpperCase(),
                                    style: context.text.labelMedium!
                                        .copyWith(color: wordInk),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(child: trailing),
                ),
            ],
          ),
          */
          // Gene - Oct 13, 2026: Partitioned trailing button with vertical hairline divider from the card body, and placed expandToggle inside card body.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    key: rowTapKey,
                    onTap: onTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: minHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (leading != null)
                                SizedBox(
                                  width: leadingWidth,
                                  child: Text(
                                    leading!,
                                    style: context.text.bodyLarge!
                                        .copyWith(fontWeight: FontWeight.w500),
                                    maxLines: 3,
                                  ),
                                ),
                              Container(
                                width: 4,
                                margin: EdgeInsets.only(
                                    right: 12, left: leading != null ? 0 : 0),
                                decoration: BoxDecoration(
                                  color: railColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (headerBadge != null) ...[
                                            headerBadge!,
                                            const SizedBox(height: 6),
                                          ],
                                          Text(title,
                                              style: context.text.titleMedium),
                                          if (subtitle != null &&
                                              subtitle!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              subtitle!,
                                              style: context.text.bodySmall,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (data != null &&
                                              data!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              data!,
                                              style: context.text.bodyLarge!
                                                  .copyWith(
                                                color: AppTheme.secondaryInkOf(
                                                    context),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (footnote != null &&
                                              footnote!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              footnote!,
                                              style: context.text.bodySmall,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (extra != null) ...[
                                            const SizedBox(height: 6),
                                            extra!,
                                          ],
                                          const SizedBox(height: 6),
                                          /*
                                          Text(
                                            statusLabel.toUpperCase(),
                                            style: context.text.labelMedium!
                                                .copyWith(color: wordInk),
                                          ),
                                          */
                                          // Gene - Nov, 20, 2026: Show NEW tag beside the status word for unread items and wrap cleanly at large text scales.
                                          Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                statusLabel.toUpperCase(),
                                                style: context.text.labelMedium!
                                                    .copyWith(color: wordInk),
                                              ),
                                              if (isNew)
                                                Container(
                                                  key: newTagKey,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: newTagBgColor ??
                                                        AppTheme
                                                            .primarySubtleBgOf(
                                                                context),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            AppTheme
                                                                .radiusStamp),
                                                    border: Border.all(
                                                      color: newTagBorderColor ??
                                                          AppTheme
                                                              .primarySubtleBorderOf(
                                                                  context),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'NEW',
                                                    style: context
                                                        .text.labelSmall!
                                                        .copyWith(
                                                      color: newTagInkColor ??
                                                          AppTheme.brandInkOf(
                                                              context),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: 0.6,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (expandToggle != null) ...[
                                      const SizedBox(width: 4),
                                      expandToggle!,
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  Container(width: 1, color: hairline),
                  trailing!,
                ],
              ],
            ),
          ),
          // Gene - Nov, 25, 2026: Render optional WorkTimingBar separated by hairlines above footer action buttons.
          if (timingBar != null) ...[
            Container(height: 1, color: hairline),
            timingBar!,
          ],
          if (actions != null && actions!.isNotEmpty) ...[
            Container(height: 1, color: hairline),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions!.length; i++) ...[
                    if (i > 0) Container(width: 1, color: hairline),
                    Expanded(child: actions![i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One action in a [StatusRailRow]'s bottom strip: an icon and an uppercase
/// 13px label in ink, a 48dp target. Icon beside the label at ordinary text
/// sizes; above it past a 1.2 scale so three actions still share one row at
/// 200%. A null [onTap] renders in muted ink.
class StatusRailAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const StatusRailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.2;
    final ink = onTap == null
        ? AppTheme.secondaryInkOf(context)
        : AppTheme.inkOf(context);
    final text = Text(
      label.toUpperCase(),
      style: context.text.labelMedium!.copyWith(color: ink),
      textAlign: TextAlign.center,
      maxLines: 2,
    );
    final glyph = Icon(icon, size: 20, color: ink);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: stacked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [glyph, const SizedBox(height: 4), text],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      glyph,
                      const SizedBox(width: 6),
                      Flexible(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
