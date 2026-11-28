// Gene - Nov, 28, 2026: On-demand Completed / History view for Service Orders subscribing to PowerSync v12 assigned_service_orders_history (15m TTL) on mount and unsubscribing on dispose.
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
  SyncStreamSubscription? _historySub;
  bool _isSyncingHistory = false;

  @override
  void initState() {
    super.initState();
    _subscribeHistory();
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
    } catch (_) {
      // Offline or transient sync failure: show locally cached completed tickets.
    } finally {
      if (mounted) setState(() => _isSyncingHistory = false);
    }
  }

  @override
  void dispose() {
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
              final orders = widget.signals.completedOrders.value;
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
                onRefresh: () => widget.signals.fetchRemote(
                  technicianEmail: widget.signals.technicianEmail.value,
                ),
                color: AppTheme.serviceOrderAccent,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => ServiceOrderCard(
                    order: orders[index],
                    signals: widget.signals,
                    lcpNapSignals: widget.lcpNapSignals,
                    jobsSignals: widget.jobsSignals,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
