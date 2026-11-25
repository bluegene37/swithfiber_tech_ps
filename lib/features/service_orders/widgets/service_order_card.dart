import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Gene - Nov, 20, 2026: Added signals_flutter import for reactive unread NEW tag display on ServiceOrderCard.
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_rail_row.dart';
// Gene - Nov, 25, 2026: Added WorkTimingBar for Service Order Start/Finish lifecycle buttons on list cards.
import '../../../core/widgets/work_timing_bar.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../models/service_order_model.dart';
import '../screens/service_order_detail_screen.dart';
import '../signals/service_orders_signals.dart';

/// Inset Grouped iOS card displaying a Service Order (repair, pullout, trouble ticket).
/*
class ServiceOrderCard extends StatelessWidget {
  final ServiceOrderDto order;
  final ServiceOrdersSignals signals;
  // Gene - Nov, 23, 2026: Optional plant & jobs signals forwarded to ServiceOrderDetailScreen for NAP pole deep link.
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;

  const ServiceOrderCard({
    super.key,
    required this.order,
    required this.signals,
    this.lcpNapSignals,
    this.jobsSignals,
  });

  // @override
  // Widget build(BuildContext context) {
  // Gene - Nov, 26, 2026: Wrap card in Watch so Start/Finish reactively unlocks/re-locks card tap and footer actions.
  @override
  Widget build(BuildContext context) {
    return Watch((context) => _buildCardContent(context));
  }

  Widget _buildCardContent(BuildContext context) {
    final order = signals.allOrders.value
            .where((o) => o.id == this.order.id)
            .firstOrNull ??
        this.order;
    final isTimingLocked = order.isOpen && !order.isTimingInProgress;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrgent = order.isUrgent;

    // Calculate distance from technician if coordinates available
    String? distanceStr;
    final myPos = LocationService.instance.lastKnownPosition;
    final orderPos = order.latLng;
    if (myPos != null && orderPos != null) {
      final meters = LocationService.instance.distanceBetween(
        startLat: myPos.latitude,
        startLng: myPos.longitude,
        endLat: orderPos.latitude,
        endLng: orderPos.longitude,
      );
      distanceStr = LocationService.instance.formatDistance(meters);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUrgent
              ? AppTheme.danger
              : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
          width: isUrgent ? 1.5 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Tappable Card Body
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('service_order_card_tap_${order.id}'),
              onTap: isTimingLocked
                  ? null
                  : () {
                      signals.markOrderAsRead(order.id);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServiceOrderDetailScreen(
                            orderId: order.id,
                            signals: signals,
                            lcpNapSignals: lcpNapSignals,
                            jobsSignals: jobsSignals,
                          ),
                        ),
                      );
                    },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gene - Nov, 20, 2026: Wrap top header row in SignalBuilder to display NEW tag on unread open service orders and clear it immediately when read.
                    SignalBuilder(
                      builder: (context) {
                        final isNew =
                            order.isOpen && !signals.isOrderRead(order.id);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'SO-${order.id.toString().padLeft(4, '0')}',
                                    style: context.text.labelMedium!.copyWith(
                                      fontFamily: 'JetBrains Mono',
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: AppTheme.brandInkOf(context),
                                    ),
                                  ),
                                  if (!order.isSynced)
                                    const Icon(
                                      CupertinoIcons.cloud_upload,
                                      size: 18,
                                      color: AppTheme.warning,
                                    ),
                                  if (isNew)
                                    Container(
                                      key: ValueKey(
                                          'service_order_new_tag_${order.id}'),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF33260F)
                                            : AppTheme.warningSubtle,
                                        borderRadius: BorderRadius.circular(
                                            AppTheme.radiusStamp),
                                        border: Border.all(
                                          color: AppTheme.warningInkOf(context)
                                              .withValues(alpha: 0.45),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        'NEW',
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          color: AppTheme.warningInkOf(context),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.primarySubtleBgDark
                                          : AppTheme.primarySubtleBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark
                                            ? AppTheme.primarySubtleBorderDark
                                            : AppTheme.primarySubtleBorder,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          order.concern
                                                  .toLowerCase()
                                                  .contains('pullout')
                                              ? CupertinoIcons
                                                  .arrow_right_arrow_left
                                              : CupertinoIcons.wrench_fill,
                                          size: 20,
                                          color: AppTheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            order.concern,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.text.labelSmall!
                                                .copyWith(
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  AppTheme.brandInkOf(context),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Gene - Nov, 23, 2026: Show distance badge on Urgent repair tickets as well as High/Normal.
                                  if (distanceStr != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          CupertinoIcons.location_solid,
                                          size: 20,
                                          color:
                                              AppTheme.secondaryInkOf(context),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          distanceStr,
                                          style:
                                              context.text.labelSmall!.copyWith(
                                            color: AppTheme.secondaryInkOf(
                                                context),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (isUrgent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'URGENT',
                                  style: context.text.labelSmall!.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),

                    // Subscriber Name
                    Text(
                      order.fullName,
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 3),

                    // Account Number & Plan
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: order.accountNumber,
                            style: context.text.bodySmall!.copyWith(
                              fontFamily: 'JetBrains Mono',
                              fontWeight: FontWeight.w600,
                              color: AppTheme.brandInkOf(context),
                            ),
                          ),
                          TextSpan(
                            text:
                                ' • ${order.provider ?? order.plan ?? "Switch Fiber"}',
                            style: context.text.bodySmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Address, only when the ticket has one: a bare pin
                    // says nothing.
                    if (order.address.trim().isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            CupertinoIcons.location_solid,
                            size: 20,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                      ),

                    // Plant Specs Info Badge (LCP / NAP / Port)
                    if (order.lcp?.isNotEmpty == true ||
                        order.nap?.isNotEmpty == true ||
                        order.port?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            width: 0.5,
                          ),
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (order.lcp?.isNotEmpty == true)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'LCP: ',
                                      style: context.text.labelSmall!.copyWith(
                                        color: AppTheme.secondaryInkOf(context),
                                      ),
                                    ),
                                    TextSpan(
                                      text: order.lcp!,
                                      style: context.text.labelSmall!.copyWith(
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (order.nap?.isNotEmpty == true)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'NAP: ',
                                      style: context.text.labelSmall!.copyWith(
                                        color: AppTheme.secondaryInkOf(context),
                                      ),
                                    ),
                                    TextSpan(
                                      text: order.nap!,
                                      style: context.text.labelSmall!.copyWith(
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (order.port?.isNotEmpty == true)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'PORT: ',
                                      style: context.text.labelSmall!.copyWith(
                                        color: AppTheme.secondaryInkOf(context),
                                      ),
                                    ),
                                    TextSpan(
                                      text: order.port!,
                                      style: context.text.labelSmall!.copyWith(
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Gene - Nov, 25, 2026: Render Start/Finish work timing bar above Navigate/Call/SMS strip.
          if (order.isOpen || order.isTimingStarted) ...[
            Container(height: 1, color: AppTheme.hairlineOf(context)),
            Watch((context) {
              final isBusy =
                  signals.busyTimingOrderIds.value.contains(order.id);
              // Gene - Nov, 26, 2026: Hide Start when another Job Order or Service Order is already active.
              final activeOrder = signals.activeStartedOrder.value;
              final activeJob = jobsSignals?.activeStartedJob.value;
              final hasOtherActiveOrder =
                  (activeOrder != null && activeOrder.id != order.id) ||
                      activeJob != null;
              return WorkTimingBar(
                status: order.workTimingStatus,
                startTime: order.startTimestamp,
                endTime: order.stopTimestamp,
                isBusy: isBusy,
                hideStart: hasOtherActiveOrder,
                startButtonKey:
                    ValueKey('service_order_start_button_${order.id}'),
                finishButtonKey:
                    ValueKey('service_order_finish_button_${order.id}'),
                finishedButtonKey:
                    ValueKey('service_order_finished_button_${order.id}'),
                onStart: () async {
                  signals.markOrderAsRead(order.id);
                  final warning = await signals.startOrder(
                    order,
                    hasOtherActiveOrder: hasOtherActiveOrder,
                  );
                  if (warning != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(warning),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onFinish: () async {
                  signals.markOrderAsRead(order.id);
                  final warning = await signals.finishOrder(order);
                  if (warning != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(warning),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              );
            }),
          ],

          // 2. Action strip: the same Navigate | Call the Today cards carry,
          // in ink, 48dp each, under a hairline.
          Container(height: 1, color: AppTheme.hairlineOf(context)),
          Material(
            color: Colors.transparent,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatusRailAction(
                      key: ValueKey('so_action_navigate_${order.id}'),
                      icon: Icons.navigation_rounded,
                      label: 'Navigate',
                      // Gene - Nov, 26, 2026: Disable Navigate action until Service Order is started.
                      onTap: isTimingLocked
                          ? null
                          : () async {
                              signals.markOrderAsRead(order.id);
                              final latLng = order.latLng;
                              if (latLng != null) {
                                await MapNavigationService.navigateTo(
                                  latLng,
                                  label: order.fullName,
                                  context: context,
                                );
                              } else {
                                final fullAddr =
                                    '${order.address}${order.barangay != null ? ", ${order.barangay}" : ""}${order.city != null ? ", ${order.city}" : ""}, Philippines';
                                await MapNavigationService.navigateToAddress(
                                  fullAddr,
                                  context: context,
                                );
                              }
                            },
                    ),
                  ),
                  Container(width: 1, color: AppTheme.hairlineOf(context)),
                  Expanded(
                    child: StatusRailAction(
                      key: ValueKey('so_action_call_${order.id}'),
                      icon: Icons.call_rounded,
                      label: 'Call',
                      // Gene - Nov, 26, 2026: Disable Call action until Service Order is started.
                      onTap: (isTimingLocked || order.contactNumber.isEmpty)
                          ? null
                          : () async {
                              signals.markOrderAsRead(order.id);
                              final uri =
                                  Uri.parse('tel:${order.contactNumber}');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                    ),
                  ),
                  // Gene - Nov, 23, 2026: Added 3rd SMS action button matching Today job cards.
                  Container(width: 1, color: AppTheme.hairlineOf(context)),
                  Expanded(
                    child: StatusRailAction(
                      key: ValueKey('so_action_sms_${order.id}'),
                      icon: Icons.sms_rounded,
                      label: 'SMS',
                      // Gene - Nov, 26, 2026: Disable SMS action until Service Order is started.
                      onTap:
                          (isTimingLocked || order.contactNumber.trim().isEmpty)
                              ? null
                              : () async {
                                  signals.markOrderAsRead(order.id);
                                  final raw = order.contactNumber.trim();
                                  final clean =
                                      raw.replaceAll(RegExp(r'[^0-9+]'), '');
                                  final body =
                                      'Good day ${order.fullName}, Switch Fiber Technician is arriving shortly for repair ticket SO-${order.id.toString().padLeft(4, '0')}.';
                                  final uri = Uri(
                                    scheme: 'sms',
                                    path: clean.isNotEmpty ? clean : raw,
                                    queryParameters: {'body': body},
                                  );
                                  try {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  } catch (_) {}
                                },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
*/
// Gene - Nov, 26, 2026: Redesigned ServiceOrderCard to share Job Order's expandable StatusRailRow layout with distinct violet colorway, Start/Stop/Start Again bar, and 4-action footer.
class ServiceOrderCard extends StatefulWidget {
  final ServiceOrderDto order;
  final ServiceOrdersSignals signals;
  // Gene - Nov, 23, 2026: Optional plant & jobs signals forwarded to ServiceOrderDetailScreen for NAP pole deep link.
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;

  const ServiceOrderCard({
    super.key,
    required this.order,
    required this.signals,
    this.lcpNapSignals,
    this.jobsSignals,
  });

  @override
  State<ServiceOrderCard> createState() => _ServiceOrderCardState();
}

class _ServiceOrderCardState extends State<ServiceOrderCard> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    widget.signals.markOrderAsRead(widget.order.id);
    setState(() => _isExpanded = !_isExpanded);
  }

  void _openDetails(ServiceOrderDto order) {
    widget.signals.markOrderAsRead(order.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceOrderDetailScreen(
          orderId: order.id,
          signals: widget.signals,
          lcpNapSignals: widget.lcpNapSignals,
          jobsSignals: widget.jobsSignals,
        ),
      ),
    );
  }

  (String, Color, Color) _statusVisuals(
    BuildContext context,
    ServiceOrderDto order,
  ) {
    if (!order.isSynced) {
      return ('Pending sync', AppTheme.warning, AppTheme.warningInkOf(context));
    }
    if (order.isUrgent) {
      return (
        order.visitStatus?.trim().isNotEmpty == true
            ? order.visitStatus!
            : order.supportStatus,
        AppTheme.danger,
        AppTheme.dangerInkOf(context),
      );
    }
    if ((order.priorityLevel ?? '').toLowerCase().contains('high')) {
      return (
        order.visitStatus?.trim().isNotEmpty == true
            ? order.visitStatus!
            : order.supportStatus,
        AppTheme.warning,
        AppTheme.warningInkOf(context),
      );
    }
    return (
      order.visitStatus?.trim().isNotEmpty == true
          ? order.visitStatus!
          : order.supportStatus,
      AppTheme.serviceOrderAccent,
      AppTheme.serviceOrderInkOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) => _buildCardContent(context));
  }

  Widget _buildCardContent(BuildContext context) {
    final signals = widget.signals;
    final order = signals.allOrders.value
            .where((o) => o.id == widget.order.id)
            .firstOrNull ??
        widget.order;
    final isTimingLocked = order.isOpen && !order.isTimingInProgress;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrgent = order.isUrgent;
    final (statusLabel, railColor, statusInk) = _statusVisuals(context, order);

    String? distanceStr;
    final myPos = LocationService.instance.lastKnownPosition;
    final orderPos = order.latLng;
    if (myPos != null && orderPos != null) {
      final meters = LocationService.instance.distanceBetween(
        startLat: myPos.latitude,
        startLng: myPos.longitude,
        endLat: orderPos.latitude,
        endLng: orderPos.longitude,
      );
      distanceStr = LocationService.instance.formatDistance(meters);
    }

    final place = [
      if (order.address.trim().isNotEmpty) order.address.trim(),
      if (order.barangay?.trim().isNotEmpty == true) order.barangay!.trim(),
      if (order.city?.trim().isNotEmpty == true) order.city!.trim(),
    ].join(', ');
    final plant = [
      if (order.lcp?.trim().isNotEmpty == true) 'LCP ${order.lcp!.trim()}',
      if (order.nap?.trim().isNotEmpty == true) 'NAP ${order.nap!.trim()}',
      if (order.port?.trim().isNotEmpty == true) 'PORT ${order.port!.trim()}',
    ].join(' · ');
    final planOrProvider = [
      if (order.provider?.trim().isNotEmpty == true) order.provider!.trim(),
      if (order.plan?.trim().isNotEmpty == true) order.plan!.trim(),
    ].join(' · ');

    final isNew = order.isOpen && !signals.isOrderRead(order.id);
    final soCode = 'SO-${order.id.toString().padLeft(4, '0')}';

    return StatusRailRow(
      leading: distanceStr,
      railColor: railColor,
      statusInk: statusInk,
      borderColor: isUrgent
          ? AppTheme.danger
          : AppTheme.serviceOrderSubtleBorderOf(context),
      borderWidth: isUrgent ? 1.5 : 1.0,
      headerBadge: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.serviceOrderSubtleBgOf(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
              border: Border.all(
                color: AppTheme.serviceOrderSubtleBorderOf(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  order.concern.toLowerCase().contains('pullout')
                      ? CupertinoIcons.arrow_right_arrow_left
                      : CupertinoIcons.wrench_fill,
                  size: 20,
                  color: AppTheme.serviceOrderInkOf(context),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    order.concern,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.serviceOrderInkOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!order.isSynced)
            const Icon(
              CupertinoIcons.cloud_upload,
              size: 20,
              color: AppTheme.warning,
            ),
          if (isUrgent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.danger,
                borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
              ),
              child: Text(
                'URGENT',
                style: context.text.labelSmall!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
      title: order.fullName,
      data: '$soCode (${order.accountNumber})',
      statusLabel: statusLabel,
      isNew: isNew,
      newTagKey: ValueKey('service_order_new_tag_${order.id}'),
      newTagBgColor: isDark ? const Color(0xFF33260F) : AppTheme.warningSubtle,
      newTagBorderColor: AppTheme.warningInkOf(context).withValues(alpha: 0.45),
      newTagInkColor: AppTheme.warningInkOf(context),
      onTap: _toggleExpanded,
      expandToggle: IconButton(
        key: ValueKey('service_order_expand_toggle_${order.id}'),
        icon: Icon(
          _isExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: AppTheme.secondaryInkOf(context),
        ),
        tooltip: _isExpanded ? 'Collapse details' : 'Expand details',
        onPressed: _toggleExpanded,
      ),
      trailing: Tooltip(
        message: isTimingLocked
            ? (order.isTimingFinished
                ? 'Work stopped (tap Start Again to open)'
                : 'Tap Start to open ticket')
            : 'Open repair ticket',
        child: InkWell(
          key: ValueKey('service_order_card_tap_${order.id}'),
          onTap: isTimingLocked ? null : () => _openDetails(order),
          child: SizedBox(
            width: 48,
            child: Center(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: isTimingLocked
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.serviceOrderAccent,
              ),
            ),
          ),
        ),
      ),
      extra: _isExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (place.isNotEmpty)
                  _ServiceDetailLine(
                    icon: Icons.location_on_outlined,
                    text: place,
                  ),
                if (plant.isNotEmpty)
                  _ServiceDetailLine(
                    icon: Icons.hub_outlined,
                    text: plant,
                    mono: true,
                  ),
                if (planOrProvider.isNotEmpty)
                  _ServiceDetailLine(
                    icon: Icons.wifi_rounded,
                    text: planOrProvider,
                  ),
                if (order.contactNumber.trim().isNotEmpty)
                  _ServiceDetailLine(
                    icon: Icons.call_outlined,
                    text: order.contactNumber.trim(),
                  ),
                if (order.emailAddress.trim().isNotEmpty)
                  _ServiceDetailLine(
                    icon: Icons.alternate_email_rounded,
                    text: order.emailAddress.trim(),
                  ),
              ],
            )
          : null,
      timingBar: (order.isOpen || order.isTimingStarted)
          ? Watch((context) {
              final isBusy =
                  signals.busyTimingOrderIds.value.contains(order.id);
              final activeOrder = signals.activeStartedOrder.value;
              final activeJob = widget.jobsSignals?.activeStartedJob.value;
              final hasOtherActiveOrder =
                  (activeOrder != null && activeOrder.id != order.id) ||
                      activeJob != null;
              return WorkTimingBar(
                status: order.workTimingStatus,
                startTime: order.startTimestamp,
                endTime: order.stopTimestamp,
                isBusy: isBusy,
                hideStart: hasOtherActiveOrder,
                finishLabel: 'Stop',
                restartLabel: 'Start Again',
                accentColor: AppTheme.serviceOrderAccent,
                startButtonKey:
                    ValueKey('service_order_start_button_${order.id}'),
                finishButtonKey:
                    ValueKey('service_order_finish_button_${order.id}'),
                finishedButtonKey:
                    ValueKey('service_order_finished_button_${order.id}'),
                onStart: () async {
                  signals.markOrderAsRead(order.id);
                  final warning = await signals.startOrder(
                    order,
                    hasOtherActiveOrder: hasOtherActiveOrder,
                  );
                  if (warning != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(warning),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onFinish: () async {
                  signals.markOrderAsRead(order.id);
                  final warning = await signals.finishOrder(order);
                  if (warning != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(warning),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              );
            })
          : null,
      actions: [
        StatusRailAction(
          key: ValueKey('so_action_navigate_${order.id}'),
          icon: Icons.navigation_rounded,
          label: 'Navigate',
          onTap: isTimingLocked
              ? null
              : () async {
                  signals.markOrderAsRead(order.id);
                  final latLng = order.latLng;
                  if (latLng != null) {
                    await MapNavigationService.navigateTo(
                      latLng,
                      label: order.fullName,
                      context: context,
                    );
                  } else {
                    final fullAddr =
                        '${order.address}${order.barangay != null ? ", ${order.barangay}" : ""}${order.city != null ? ", ${order.city}" : ""}, Philippines';
                    await MapNavigationService.navigateToAddress(
                      fullAddr,
                      context: context,
                    );
                  }
                },
        ),
        StatusRailAction(
          key: ValueKey('so_action_call_${order.id}'),
          icon: Icons.call_rounded,
          label: 'Call',
          onTap: (isTimingLocked || order.contactNumber.isEmpty)
              ? null
              : () async {
                  signals.markOrderAsRead(order.id);
                  final uri = Uri.parse('tel:${order.contactNumber}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
        ),
        StatusRailAction(
          key: ValueKey('so_action_sms_${order.id}'),
          icon: Icons.sms_rounded,
          label: 'SMS',
          onTap: (isTimingLocked || order.contactNumber.trim().isEmpty)
              ? null
              : () async {
                  signals.markOrderAsRead(order.id);
                  final raw = order.contactNumber.trim();
                  final clean = raw.replaceAll(RegExp(r'[^0-9+]'), '');
                  final body =
                      'Good day ${order.fullName}, Switch Fiber Technician is arriving shortly for repair ticket $soCode.';
                  final uri = Uri(
                    scheme: 'sms',
                    path: clean.isNotEmpty ? clean : raw,
                    queryParameters: {'body': body},
                  );
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
        ),
        StatusRailAction(
          key: ValueKey('so_action_details_${order.id}'),
          icon: Icons.assignment_outlined,
          label: 'Details',
          onTap: isTimingLocked ? null : () => _openDetails(order),
        ),
      ],
    );
  }
}

class _ServiceDetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool mono;

  const _ServiceDetailLine({
    required this.icon,
    required this.text,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryInkOf(context);
    final base = mono ? context.text.bodyLarge! : context.text.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: base.copyWith(color: muted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
