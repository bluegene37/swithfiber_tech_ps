import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
// Gene - Nov, 11, 2026: Imported AppTheme to style RefreshIndicator on CabinetNapsScreen for manual pull-to-refresh parity.
import '../../../core/theme/app_theme.dart';
import '../models/lcp_nap_model.dart';
import '../signals/lcp_nap_signals.dart';
import '../widgets/lcp_nap_card.dart';
// Gene - Nov, 11, 2026: Imported LcpNapLocationPickerSheet to allow adding a new NAP directly inside a cabinet view.
import '../widgets/lcp_nap_location_picker_sheet.dart';
// Gene - Nov, 12, 2026: Imported LcpNapFloatingAddButton for bottom-floating "+ Add NAP" pill button.
import '../widgets/lcp_nap_floating_add_button.dart';
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

  // Gene - Nov, 11, 2026: Open create modal pre-filled with the current cabinet name and next sequential NAP number.
  Future<void> _openAddNapSheet(
    BuildContext context,
    List<LcpNapDto> naps,
  ) async {
    int maxNum = 0;
    for (final loc in naps) {
      final match = RegExp(r'(\d+)').firstMatch(loc.nap);
      if (match != null) {
        final val = int.tryParse(match.group(1)!) ?? 0;
        if (val > maxNum) maxNum = val;
      }
    }
    final nextNap = 'NAP ${(maxNum + 1).toString().padLeft(3, '0')}';
    final initialCity = naps.isNotEmpty ? naps.first.city : null;
    final initialRegion =
        naps.isNotEmpty ? (naps.first.region ?? 'Rizal') : 'Rizal';

    LcpNapDto? createdSite;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LcpNapLocationPickerSheet.create(
        signals: signals,
        initialLcp: cabinet,
        initialNap: nextNap,
        initialCity: initialCity,
        initialRegion: initialRegion,
        onCreated: (site) => createdSite = site,
      ),
    );

    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${createdSite?.lcpNap ?? nextNap} to $cabinet.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      if (createdSite != null) {
        _openDetails(context, createdSite!);
      }
    }
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
            /*
            // Gene - Nov, 11, 2026: Added button to create a new NAP inside this cabinet.
            actions: [
              IconButton(
                key: const ValueKey('btnAddCabinetNap'),
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add NAP to Cabinet',
                onPressed: () => _openAddNapSheet(context, naps),
              ),
            ],
            */
            // Gene - Nov, 12, 2026: Moved Add NAP action from top AppBar to bottom-right floating pill button per Calm Utility ("Read at the top, act at the bottom").
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: LcpNapFloatingAddButton(
            buttonKey: const ValueKey('btnAddCabinetNap'),
            label: 'Add NAP',
            onPressed: () => _openAddNapSheet(context, naps),
          ),
          /*
          body: naps.isEmpty
              ? Center(
                  child: Text('No NAPs on this cabinet.',
                      style: context.text.bodyMedium),
                )
          */
          // Gene - Nov, 12, 2026: Added RefreshIndicator-wrapped actionable empty state and 96dp bottom scroll clearance for the floating "+ Add NAP" pill.
          body: naps.isEmpty
              ? RefreshIndicator(
                  onRefresh: signals.fetchRemote,
                  color: AppTheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(32, 64, 32, 96),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySubtleBgOf(context),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primarySubtleBorderOf(context),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.router_outlined,
                            size: 32,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No NAPs on this cabinet.',
                        textAlign: TextAlign.center,
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "+ Add NAP" below to register the first distribution box on $cabinet.',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
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
                    /*
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    */
                    // Gene - Nov, 12, 2026: Increased bottom padding to 96dp so the floating "+ Add NAP" pill never overlaps the final NAP card.
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
