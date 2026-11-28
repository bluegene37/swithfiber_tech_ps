import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Gene - Nov, 23, 2026: Added flutter_map TileProvider and Repairs map/detail imports for Repairs Map toggle.
import 'package:flutter_map/flutter_map.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/loading_states.dart';
// Gene - Nov, 26, 2026: Import WorkTimingEntry, WorkTimingHistoryScreen, and TodayGlancePanel for Job Order visual parity + timing history access.
import '../../../core/database/models/work_timing_entry.dart';
import '../../diagnostics/screens/work_timing_history_screen.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../jobs/widgets/today_glance_panel.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../models/service_order_model.dart';
import '../screens/service_order_detail_screen.dart';
import '../signals/service_orders_signals.dart';
import '../widgets/service_order_card.dart';
import '../widgets/service_orders_map_view.dart';

/// Dedicated screen for Service Orders (Repairs, Equipment Swaps, Maintenance).
class ServiceOrdersScreen extends StatefulWidget {
  final ServiceOrdersSignals signals;
  // Gene - Nov, 23, 2026: Optional LcpNapSignals and JobsSignals forwarded to repair cards & detail screens, plus injectable mapTileProvider for tests.
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;
  final TileProvider? mapTileProvider;

  const ServiceOrdersScreen({
    super.key,
    required this.signals,
    this.lcpNapSignals,
    this.jobsSignals,
    this.mapTileProvider,
  });

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  // Gene - Nov, 23, 2026: List vs Map view state and open-ticket navigation helper.
  bool _showMap = false;
  // Gene - Nov, 26, 2026: Collapsible search toggle matching Today JobOrdersScreen.
  bool _showSearch = false;

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        widget.signals.searchQuery.value = '';
      }
    });
  }

  void _openOrderDetail(ServiceOrderDto order) {
    // Gene - Nov, 26, 2026: Gate opening Service Order details until technician taps Start.
    if (order.isOpen && !order.isTimingInProgress) return;
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

  static const List<String> _priorities = ['All', 'Urgent', 'High', 'Normal'];
/*
  static const List<String> _concerns = [
    'All',
    'Pullout',
    'No Connection',
    'High Loss',
    'Relocation',
  ];
*/
  // Gene - Oct 12, 2026: Updated repair concerns with 13 official AppSheet Repair Categories.
  static const List<String> _concerns = [
    'All',
    'Resplice',
    'Replace Patch Cord',
    'Fiber Relaying',
    'Replace Router',
    'Transfer LCP / NAP / PORT',
    'Relocate Router',
    'Update VLAN',
    'Reboot/Reconfig Router',
    'Migrate',
    'Pullout',
    'Others',
    'Reconfig',
    'Retain',
    'No Connection',
    'High Loss',
    'Relocation',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.signals.searchQuery.value;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signals = widget.signals;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    /*
    return Scaffold(
      appBar: AppBar(
        // Titled after its tab so the bar says what was tapped.
        title: const Text('Repairs'),
        actions: [
          // Gene - Nov, 23, 2026: Toggle between Repairs List and Map view.
          IconButton(
            key: const ValueKey('repairs_view_toggle_button'),
            tooltip: _showMap ? 'List View' : 'Map View',
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(
              _showMap ? Icons.view_list_rounded : Icons.map_outlined,
              size: 24,
            ),
          ),
          SignalBuilder(
            builder: (context) {
              final syncing = signals.isSyncing.value;

              return IconButton(
                tooltip: 'Refresh tickets',
                onPressed: syncing
                    ? null
                    : () async {
                        await signals.fetchRemote(
                          technicianEmail: signals.technicianEmail.value,
                        );
                        if (!context.mounted) return;
                        final error = signals.syncError.value;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error ?? 'Repairs queue updated from server.',
                            ),
                            backgroundColor: error != null
                                ? AppTheme.warning
                                : AppTheme.success,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                icon: syncing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      )
                    : const Icon(CupertinoIcons.arrow_2_circlepath),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search first, then the priority chips, on the page itself
          // (same header as Plant).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Search repair ticket, account, concern',
                  onChanged: (text) {
                    setState(() {});
                    signals.searchQuery.value = text;
                  },
                ),
                const SizedBox(height: 10),
    */
    // Gene - Nov, 26, 2026: Match Today JobOrdersScreen glance-panel layout with distinct violet SERVICE ORDERS badge, collapsible search, and timing history button.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SignalBuilder(
              builder: (context) {
                final total = signals.totalCount.value;
                final baseTotal = signals.baseOrdersCount.value;
                final urgent = signals.urgentCount.value;
                final syncing = signals.isSyncing.value;
                final hasActiveFilter =
                    signals.searchQuery.value.trim().isNotEmpty ||
                        signals.priorityFilter.value != 'All' ||
                        signals.concernFilter.value != 'All';
                final bannerLabel = hasActiveFilter
                    ? '$total of $baseTotal repair ticket${baseTotal == 1 ? '' : 's'}'
                    : '$total active repair ticket${total == 1 ? '' : 's'}';

                return TodayGlancePanel(
                  jobCount: total,
                  singularLabel: 'repair ticket',
                  pluralLabel: 'repair tickets',
                  countColor: AppTheme.serviceOrderInkOf(context),
                  typeBadge: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.serviceOrderSubtleBgOf(context),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusStamp),
                          border: Border.all(
                            color: AppTheme.serviceOrderSubtleBorderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.wrench_fill,
                              size: 20,
                              color: AppTheme.serviceOrderInkOf(context),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'SERVICE ORDERS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall!.copyWith(
                                  color: AppTheme.serviceOrderInkOf(context),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (urgent > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusStamp),
                          ),
                          child: Text(
                            '$urgent urgent',
                            style: context.text.labelSmall!.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  summary: bannerLabel,
                  actions: [
                    IconButton(
                      key: const ValueKey('repairs_search_toggle_button'),
                      tooltip: _showSearch ? 'Hide search' : 'Search repairs',
                      isSelected: _showSearch,
                      onPressed: _toggleSearch,
                      icon: const Icon(CupertinoIcons.search),
                    ),
                    IconButton(
                      key: const ValueKey('repairs_view_toggle_button'),
                      tooltip: _showMap ? 'Show list' : 'Show map',
                      isSelected: _showMap,
                      onPressed: () => setState(() => _showMap = !_showMap),
                      icon: Icon(_showMap
                          ? CupertinoIcons.list_bullet
                          : CupertinoIcons.map),
                    ),
                    IconButton(
                      key: const ValueKey('repairs_timing_history_button'),
                      tooltip: 'Timing history',
                      onPressed: () {
                        final dao = signals.timingHistory ??
                            widget.jobsSignals?.timingHistory;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkTimingHistoryScreen(
                              dao: dao,
                              initialOrderType:
                                  WorkTimingEntry.orderTypeServiceOrder,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded),
                    ),
                    IconButton(
                      tooltip: 'Refresh tickets',
                      onPressed: syncing
                          ? null
                          : () async {
                              await signals.fetchRemote(
                                technicianEmail: signals.technicianEmail.value,
                              );
                              if (!context.mounted) return;
                              final error = signals.syncError.value;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error ??
                                        'Repairs queue updated from server.',
                                  ),
                                  backgroundColor: error != null
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                      icon: syncing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.serviceOrderAccent,
                              ),
                            )
                          : const Icon(CupertinoIcons.arrow_2_circlepath),
                    ),
                  ],
                );
              },
            ),
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: AppSearchField(
                  controller: _searchController,
                  hintText: 'Search repair ticket, account, concern',
                  onChanged: (text) {
                    setState(() {});
                    signals.searchQuery.value = text;
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  // Priority Filter Chips
                  SignalBuilder(
                    builder: (context) {
                      final currentPriority = signals.priorityFilter.value;

                      // Intrinsic height, not a fixed box: at 200% text a
                      // ChoiceChip needs more than the 32px an 8pt scale was
                      // designed around, and a SizedBox forces it into that
                      // height instead of erroring, silently squeezing the
                      // label. SingleChildScrollView lets the row size to
                      // whatever the chips need while still scrolling
                      // horizontally, same as the ListView it replaces.
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var index = 0;
                                index < _priorities.length;
                                index++) ...[
                              if (index > 0) const SizedBox(width: 8),
                              Builder(builder: (chipContext) {
                                final p = _priorities[index];
                                final isSelected =
                                    currentPriority.toLowerCase() ==
                                        p.toLowerCase();

                                return ChoiceChip(
                                  label: Text(p),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    signals.priorityFilter.value = p;
                                    setState(() {});
                                  },
                                  labelStyle:
                                      chipContext.text.labelLarge!.copyWith(
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.secondaryInkOf(chipContext),
                                  ),
                                  selectedColor: switch (p) {
                                    'Urgent' => AppTheme.danger,
                                    'High' => AppTheme.warning,
                                    'Normal' => AppTheme.info,
                                    _ => AppTheme.primary,
                                  },
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),

                  // Concern Filter Chips
                  SignalBuilder(
                    builder: (context) {
                      final currentConcern = signals.concernFilter.value;

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var index = 0;
                                index < _concerns.length;
                                index++) ...[
                              if (index > 0) const SizedBox(width: 8),
                              Builder(builder: (chipContext) {
                                final c = _concerns[index];
                                final isSelected =
                                    currentConcern.toLowerCase() ==
                                        c.toLowerCase();

                                return ChoiceChip(
                                  label: Text(c == 'All' ? 'All Concerns' : c),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    signals.concernFilter.value = c;
                                    setState(() {});
                                  },
                                  labelStyle:
                                      chipContext.text.labelLarge!.copyWith(
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.secondaryInkOf(chipContext),
                                  ),
                                  selectedColor: AppTheme.serviceOrderAccent,
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),

                  // Gene - Nov, 23, 2026: Wrap-safe Priority / Nearest sort toggle.
                  SignalBuilder(
                    builder: (context) {
                      final mode = signals.sortMode.value;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          key: const ValueKey('repairs_sort_toggle'),
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Sort:',
                              style: context.text.labelMedium!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                              ),
                            ),
                            for (final option in const [
                              (
                                mode: ServiceOrderSort.priority,
                                label: 'Priority'
                              ),
                              (
                                mode: ServiceOrderSort.nearest,
                                label: 'Nearest'
                              ),
                            ])
                              ChoiceChip(
                                key: ValueKey(
                                    'repairs_sort_${option.mode.name}'),
                                label: Text(option.label),
                                selected: mode == option.mode,
                                onSelected: (_) =>
                                    signals.setSortMode(option.mode),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  /*
                const SizedBox(height: 10),

                // Status Banner
                SignalBuilder(
                  builder: (context) {
                    final total = signals.totalCount.value;
                    final baseTotal = signals.baseOrdersCount.value;
                    final urgent = signals.urgentCount.value;
                    final hasActiveFilter =
                        signals.searchQuery.value.trim().isNotEmpty ||
                            signals.priorityFilter.value != 'All' ||
                            signals.concernFilter.value != 'All';
                    final bannerLabel = hasActiveFilter
                        ? '$total of $baseTotal repair ticket${baseTotal == 1 ? '' : 's'}'
                        : '$total active repair ticket${total == 1 ? '' : 's'}';

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.borderDark
                              : AppTheme.borderLight,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.wrench_fill,
                            size: 20,
                            color: AppTheme.brandInkOf(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              bannerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelMedium!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (urgent > 0) const SizedBox(width: 8),
                          if (urgent > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.danger,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$urgent urgent',
                                style: context.text.labelSmall!.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                */
                ],
              ),
            ),

            // 2. Orders List or Map Body
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final orders = signals.filteredOrders.value;
                  final syncing = signals.isSyncing.value;

                  if (syncing && orders.isEmpty) {
                    return const DownloadingIndicator(
                      title: 'Loading Service Orders',
                      subtitle:
                          'Fetching maintenance tickets and equipment pullouts...',
                    );
                  }

                  // Gene - Nov, 23, 2026: Show Repairs interactive Map View when toggled in AppBar.
                  if (_showMap) {
                    return ServiceOrdersMapView(
                      signals: signals,
                      tileProvider: widget.mapTileProvider,
                      onOpenTicket: _openOrderDetail,
                    );
                  }

                  if (orders.isEmpty) {
                    final hasQuery =
                        signals.searchQuery.value.trim().isNotEmpty;
                    if (hasQuery) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: AppTheme.secondaryInkOf(context),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No repair tickets found',
                                style: context.text.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'No tickets matching "${signals.searchQuery.value.trim()}". Check account number or subscriber name.',
                                style: context.text.bodyMedium!.copyWith(
                                  color: AppTheme.secondaryInkOf(context),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () {
                                  _searchController.clear();
                                  signals.searchQuery.value = '';
                                  signals.priorityFilter.value = 'All';
                                  signals.concernFilter.value = 'All';
                                  setState(() {});
                                },
                                child: const Text('Clear search & filters'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final hasFilters = signals.priorityFilter.value != 'All' ||
                        signals.concernFilter.value != 'All';

                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF3F2327)
                                    : AppTheme.primarySubtleBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.wrench,
                                size: 36,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Active Service Orders',
                              style: context.text.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasFilters
                                  ? 'No repair or swap tickets match the current priority or concern filter.'
                                  : 'No repair or swap tickets are currently assigned.',
                              style: context.text.bodyMedium!.copyWith(
                                  color: AppTheme.secondaryInkOf(context)),
                              textAlign: TextAlign.center,
                            ),
                            if (hasFilters) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () {
                                  signals.priorityFilter.value = 'All';
                                  signals.concernFilter.value = 'All';
                                  setState(() {});
                                },
                                child: const Text('Reset filters'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => signals.fetchRemote(
                      technicianEmail: signals.technicianEmail.value,
                    ),
                    color: AppTheme.serviceOrderAccent,
                    /*
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return ServiceOrderCard(
                        order: order,
                        signals: signals,
                        lcpNapSignals: widget.lcpNapSignals,
                        jobsSignals: widget.jobsSignals,
                      );
                    },
                  ),
                  */
                    /*
                    // Gene - Nov, 26, 2026: Match JobOrdersScreen list padding and 8dp item spacing.
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return ServiceOrderCard(
                          order: order,
                          signals: signals,
                          lcpNapSignals: widget.lcpNapSignals,
                          jobsSignals: widget.jobsSignals,
                        );
                      },
                    ),
                    */
                    // Gene - Nov, 28, 2026: Group Rescheduled repair tickets under a dedicated bottom section while keeping active orders first.
                    child: () {
                      final activeOrders =
                          orders.where((o) => !o.isRescheduled).toList();
                      final rescheduledOrders =
                          orders.where((o) => o.isRescheduled).toList();
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          for (var i = 0; i < activeOrders.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            ServiceOrderCard(
                              order: activeOrders[i],
                              signals: signals,
                              lcpNapSignals: widget.lcpNapSignals,
                              jobsSignals: widget.jobsSignals,
                            ),
                          ],
                          if (rescheduledOrders.isNotEmpty) ...[
                            if (activeOrders.isNotEmpty)
                              const SizedBox(height: 12),
                            _ServiceRescheduledSectionHeader(
                              count: rescheduledOrders.length,
                            ),
                            for (var i = 0;
                                i < rescheduledOrders.length;
                                i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              ServiceOrderCard(
                                order: rescheduledOrders[i],
                                signals: signals,
                                lcpNapSignals: widget.lcpNapSignals,
                                jobsSignals: widget.jobsSignals,
                              ),
                            ],
                          ],
                        ],
                      );
                    }(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRescheduledSectionHeader extends StatelessWidget {
  final int count;

  const _ServiceRescheduledSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final warningInk = AppTheme.warningInkOf(context);
    return Container(
      key: const ValueKey('service_orders_rescheduled_group_header'),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: [
          Icon(Icons.event_repeat_rounded, size: 20, color: warningInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Rescheduled',
              style: context.text.labelLarge!.copyWith(
                fontWeight: FontWeight.w700,
                color: warningInk,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.fillOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count ${count == 1 ? 'ticket' : 'tickets'}',
              style: context.text.labelSmall!.copyWith(
                color: AppTheme.secondaryInkOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
