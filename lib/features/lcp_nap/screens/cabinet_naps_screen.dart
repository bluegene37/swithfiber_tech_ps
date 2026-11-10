import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
// Gene - Nov, 11, 2026: Imported AppTheme to style RefreshIndicator on CabinetNapsScreen for manual pull-to-refresh parity.
import '../../../core/theme/app_theme.dart';
import '../models/lcp_nap_model.dart';
import '../signals/lcp_nap_signals.dart';
import '../widgets/lcp_nap_card.dart';
import 'lcp_nap_detail_screen.dart';

/// The NAPs of one cabinet, opened from a flat cabinet row on the Plant
/// screen (DESIGN.md: no nested cards; groups open a child list).
class CabinetNapsScreen extends StatelessWidget {
  final String cabinet;
  final LcpNapSignals signals;

  const CabinetNapsScreen({
    super.key,
    required this.cabinet,
    required this.signals,
  });

  void _openDetails(BuildContext context, LcpNapDto location) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LcpNapDetailScreen(
          locationId: location.id,
          signals: signals,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final naps = signals.groupedByLcp.value[cabinet] ?? const [];
        final ports = naps.fold<int>(0, (sum, n) => sum + n.portTotal);
        return Scaffold(
          appBar: AppBar(
            title: Text(cabinet, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          body: naps.isEmpty
              ? Center(
                  child: Text('No NAPs on this cabinet.',
                      style: context.text.bodyMedium),
                )
          /*
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: naps.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${naps.length} ${naps.length == 1 ? 'NAP' : 'NAPs'} · $ports ports',
                          style: context.text.bodySmall,
                        ),
                      );
                    }
                    final nap = naps[index - 1];
                    return LcpNapCard(
                      location: nap,
                      onTap: () => _openDetails(context, nap),
                    );
                  },
                ),
          */
              // Gene - Nov, 11, 2026: Wrapped CabinetNapsScreen list in RefreshIndicator with AlwaysScrollableScrollPhysics so technicians can pull-to-refresh NAP GPS & photo state inside any cabinet view.
              : RefreshIndicator(
                  onRefresh: signals.fetchRemote,
                  color: AppTheme.primary,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: naps.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${naps.length} ${naps.length == 1 ? 'NAP' : 'NAPs'} · $ports ports',
                            style: context.text.bodySmall,
                          ),
                        );
                      }
                      final nap = naps[index - 1];
                      return LcpNapCard(
                        location: nap,
                        onTap: () => _openDetails(context, nap),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
