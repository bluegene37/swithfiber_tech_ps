// Gene - Nov, 28, 2026: On-demand Completed / History view for Service Orders subscribing to PowerSync v13 assigned_service_orders_history (15m TTL) with paginated LIMIT 50 OFFSET ? queries.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' show SyncStreamSubscription;
import 'package:signals_flutter/signals_flutter.dart';

import '../../../core/sync/powersync_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../models/service_order_model.dart';
import '../signals/service_orders_signals.dart';
import '../widgets/service_order_card.dart';

class ServiceOrderHistoryView extends StatefulWidget {
  final ServiceOrdersSignals signals;
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;

  const ServiceOrderHistoryView({
    super.key,
    required this.signals,
    this.lcpNapSignals,
    this.jobsSignals,
  });

  @override
  State<ServiceOrderHistoryView> createState() =>
      _ServiceOrderHistoryViewState();
}

class _ServiceOrderHistoryViewState extends State<ServiceOrderHistoryView> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  SyncStreamSubscription? _historySub;
  VoidCallback? _disposeOrdersWatcher;
  bool _isSyncingHistory = false;
  bool _loadingMore = false;
  bool _hasMoreSqlPages = false;
  int _loadedPages = 1;
  List<ServiceOrderDto> _pagedSqlOrders = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _disposeOrdersWatcher = effect(() {
      widget.signals.allOrders.value;
      widget.signals.technicianEmail.value;
      unawaited(_reloadFirstPage());
    });
    _subscribeHistory();
    unawaited(_reloadFirstPage());
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _reloadFirstPage() async {
    if (widget.signals.dao == null) return;
    try {
      final rows = await widget.signals.getHistoryOrdersPage(
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _loadedPages = 1;
        _pagedSqlOrders = rows;
        _hasMoreSqlPages = rows.length == _pageSize;
      });
    } catch (_) {}
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore) return;
    if (widget.signals.dao != null && _pagedSqlOrders.isNotEmpty) {
      if (!_hasMoreSqlPages) return;
      setState(() => _loadingMore = true);
      try {
        final next = await widget.signals.getHistoryOrdersPage(
          limit: _pageSize,
          offset: _pagedSqlOrders.length,
        );
        if (!mounted) return;
        setState(() {
          _pagedSqlOrders = [..._pagedSqlOrders, ...next];
          _hasMoreSqlPages = next.length == _pageSize;
        });
      } finally {
        if (mounted) setState(() => _loadingMore = false);
      }
      return;
    }

    final totalInMemory = widget.signals.completedOrders.value.length;
    if (_loadedPages * _pageSize < totalInMemory) {
      setState(() => _loadedPages += 1);
    }
  }

  Future<void> _subscribeHistory() async {
    if (!PowerSyncService.instance.isInitialized ||
        !PowerSyncService.instance.isReplicatedMode) {
      return;
    }
    if (mounted) setState(() => _isSyncingHistory = true);
    try {
      final sub = await PowerSyncService.instance.subscribeHistoryStream(
        'assigned_service_orders_history',
        ttl: const Duration(minutes: 15),
      );
      if (!mounted) {
        sub?.unsubscribe();
        return;
      }
      _historySub = sub;
      await sub?.waitForFirstSync();
      await _reloadFirstPage();
    } catch (_) {
      // Offline or transient sync failure: show locally cached completed tickets.
    } finally {
      if (mounted) setState(() => _isSyncingHistory = false);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _disposeOrdersWatcher?.call();
    _historySub?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isSyncingHistory) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: SignalBuilder(
            builder: (context) {
              final inMemoryOrders = widget.signals.completedOrders.value;
              final useSqlRows =
                  widget.signals.dao != null && _pagedSqlOrders.isNotEmpty;
              final orders = useSqlRows
                  ? _pagedSqlOrders
                  : inMemoryOrders.take(_loadedPages * _pageSize).toList();
              final hasMore = useSqlRows
                  ? _hasMoreSqlPages
                  : inMemoryOrders.length > orders.length;

              if (orders.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_seal,
                          size: 36,
                          color: AppTheme.secondaryInkOf(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Completed Service Orders Yet',
                          style: context.text.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completed, resolved, and closed repair tickets appear here.',
                          style: context.text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await widget.signals.fetchRemote(
                    technicianEmail: widget.signals.technicianEmail.value,
                  );
                  await _reloadFirstPage();
                },
                color: AppTheme.serviceOrderAccent,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: orders.length + (hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index >= orders.length) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: OutlinedButton(
                            key: const ValueKey(
                                'service_order_history_load_more'),
                            onPressed: _loadingMore ? null : _loadNextPage,
                            child: Text(
                              _loadingMore ? 'Loading...' : 'Load more',
                            ),
                          ),
                        ),
                      );
                    }
                    return ServiceOrderCard(
                      order: orders[index],
                      signals: widget.signals,
                      lcpNapSignals: widget.lcpNapSignals,
                      jobsSignals: widget.jobsSignals,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
