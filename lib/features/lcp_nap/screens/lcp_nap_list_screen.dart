import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/loading_states.dart';
import '../models/lcp_nap_model.dart';
import '../signals/lcp_nap_signals.dart';
import '../widgets/lcp_nap_card.dart';
// Gene - Nov, 11, 2026: Imported LcpNapLocationPickerSheet to allow creating new LCP NAP locations directly from the Plant screen.
import '../widgets/lcp_nap_location_picker_sheet.dart';
// Gene - Nov, 12, 2026: Imported searchable LCP Cabinet picker sheet and bottom floating Add pill button.
import '../widgets/lcp_cabinet_picker_sheet.dart';
import '../widgets/lcp_nap_floating_add_button.dart';
import '../widgets/lcp_nap_map_view.dart';
import 'cabinet_naps_screen.dart';
import 'lcp_nap_detail_screen.dart';

/// Scalable LCP NAP plant distribution screen supporting hierarchical cabinet grouping,
/// searchable cabinet filter, area groupings, and map views for large scale networks.
class LcpNapListScreen extends StatefulWidget {
  final LcpNapSignals signals;

  const LcpNapListScreen({
    super.key,
    required this.signals,
  });

  @override
  State<LcpNapListScreen> createState() => _LcpNapListScreenState();
}

enum _LcpNapView { list, map }

class _LcpNapListScreenState extends State<LcpNapListScreen> {
  final TextEditingController _searchController = TextEditingController();
  _LcpNapView _view = _LcpNapView.list;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(LcpNapDto location) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LcpNapDetailScreen(
          locationId: location.id,
          signals: widget.signals,
        ),
      ),
    );
  }

  void _openCabinet(String cabinet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CabinetNapsScreen(
          cabinet: cabinet,
          signals: widget.signals,
        ),
      ),
    );
  }

  // Gene - Nov, 11, 2026: Open modal sheet to create a new LCP NAP location and navigate to its detail screen once created.
  Future<void> _openCreateSheet() async {
    final activeLcp = widget.signals.selectedLcpFilter.value;
    final initialLcp = activeLcp != 'All' ? activeLcp : '';
    String initialNap = 'NAP 001';
    String? initialCity;
    String? initialRegion = 'Rizal';

    if (initialLcp.isNotEmpty) {
      final existing = widget.signals.allLocations.value
          .where((e) => e.lcp == initialLcp)
          .toList();
      int maxNum = 0;
      for (final loc in existing) {
        final match = RegExp(r'(\d+)').firstMatch(loc.nap);
        if (match != null) {
          final val = int.tryParse(match.group(1)!) ?? 0;
          if (val > maxNum) maxNum = val;
        }
      }
      initialNap = 'NAP ${(maxNum + 1).toString().padLeft(3, '0')}';
      if (existing.isNotEmpty) {
        initialCity = existing.first.city;
        initialRegion = existing.first.region ?? initialRegion;
      }
    }

    LcpNapDto? createdSite;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LcpNapLocationPickerSheet.create(
        signals: widget.signals,
        initialLcp: initialLcp,
        initialNap: initialNap,
        initialCity: initialCity,
        initialRegion: initialRegion,
        onCreated: (site) => createdSite = site,
      ),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${createdSite?.lcpNap ?? "LCP NAP location"} successfully.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      if (createdSite != null) {
        _openDetails(createdSite!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final signals = widget.signals;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant'),
        actions: [
          /*
          // Gene - Nov, 11, 2026: Added Create LCP NAP Location action button in the Plant AppBar.
          IconButton(
            key: const ValueKey('btnCreateLcpNap'),
            icon: const Icon(CupertinoIcons.add_circled),
            tooltip: 'Create LCP NAP Location',
            onPressed: _openCreateSheet,
          ),
          */
          // Gene - Nov, 12, 2026: Moved Create LCP NAP action from top AppBar to bottom-right floating pill button per Calm Utility ("Read at the top, act at the bottom").
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_2_circlepath),
            tooltip: 'Sync Plant Records',
            onPressed: () {
              signals.fetchRemote();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing LCP NAP records with the server...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      // Gene - Nov, 12, 2026: Floating extended "+ Add LCP NAP" pill at bottom-right on List view (Map view renders its own bottom-left pill to avoid zoom control overlap).
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _view == _LcpNapView.list
          ? LcpNapFloatingAddButton(
              buttonKey: const ValueKey('btnCreateLcpNap'),
              label: 'Add LCP NAP',
              onPressed: _openCreateSheet,
            )
          : null,
      body: Column(
        children: [
          // Search first, then one line of counts, then the view switch and
          // the cabinet filter (DESIGN.md, Plant).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Search LCP, NAP, Barangay, City',
                  onChanged: (val) {
                    setState(() {});
                    signals.setSearch(val);
                  },
                ),
                const SizedBox(height: 8),
                SignalBuilder(
                  builder: (context) {
                    final cabinets = signals.lcpCabinetList.value.length - 1;
                    final sites = signals.totalSitesCount.value;
                    final ports = signals.totalPortsCount.value;
                    return _PlantSummaryLine(
                      cabinets: cabinets < 0 ? 0 : cabinets,
                      naps: sites,
                      ports: ports,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _LcpNapToolbar(
                  viewSwitch: SegmentedButton<_LcpNapView>(
                    segments: const [
                      ButtonSegment(
                          value: _LcpNapView.list, label: Text('List')),
                      ButtonSegment(value: _LcpNapView.map, label: Text('Map')),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    onSelectionChanged: (selection) =>
                        setState(() => _view = selection.first),
                  ),
                  filterButton: _buildCabinetFilterButton(signals, isDark),
                ),
              ],
            ),
          ),

          // Active cabinet filter, with the way out next to it.
          SignalBuilder(
            builder: (context) {
              final activeLcp = signals.selectedLcpFilter.value;
              if (activeLcp == 'All') return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: AppTheme.primarySubtleBgOf(context),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt_rounded,
                        size: 20, color: AppTheme.brandInkOf(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Filtered by Cabinet: $activeLcp',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelLarge!.copyWith(
                          color: AppTheme.brandInkOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => signals.setLcpFilter('All'),
                      child: const Text('Show All'),
                    ),
                  ],
                ),
              );
            },
          ),

          Expanded(child: _buildBody(context, signals)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, LcpNapSignals signals) {
    if (_view == _LcpNapView.map) {
      /*
      return LcpNapMapView(
        signals: signals,
        onOpenDetails: _openDetails,
      );
      */
      // Gene - Nov, 12, 2026: Pass _openCreateSheet so Map view renders its bottom-left "+ Add LCP NAP" pill when no pin popup is active.
      return LcpNapMapView(
        signals: signals,
        onOpenDetails: _openDetails,
        onCreateSite: _openCreateSheet,
      );
    }

    return SignalBuilder(
      builder: (context) {
        final grouped = signals.groupedByLcp.value;
        final isLoading = signals.isLoading.value;
        final phase = signals.loadPhase.value;

        if (phase == DataLoadPhase.downloading) {
          return const DownloadingIndicator(
            title: 'Downloading Plant Records',
            subtitle: 'Fetching LCP NAP cabinets and sites from the server...',
          );
        }
        if (phase == DataLoadPhase.skeleton || (isLoading && grouped.isEmpty)) {
          return const SkeletonCardList();
        }

        final locations = signals.filteredLocations.value;
        if (locations.isEmpty) return _buildEmptyState(context, signals);

        final searching = signals.searchQuery.value.trim().isNotEmpty;
        final filtered = signals.selectedLcpFilter.value != 'All';

        // A search or a cabinet filter answers with the NAPs themselves.
        if (searching || filtered) {
          return RefreshIndicator(
            onRefresh: signals.fetchRemote,
            color: AppTheme.primary,
            child: ListView.builder(
              /*
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              */
              // Gene - Nov, 12, 2026: Added 96dp bottom scroll clearance so the floating "+ Add LCP NAP" pill never obscures the final NAP card.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: locations.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${locations.length} ${locations.length == 1 ? 'NAP' : 'NAPs'}',
                      style: context.text.bodySmall,
                    ),
                  );
                }
                final nap = locations[index - 1];
                return LcpNapCard(
                  location: nap,
                  onTap: () => _openDetails(nap),
                );
              },
            ),
          );
        }

        // Otherwise flat cabinet rows; a cabinet opens its NAPs.
        final cabinets = grouped.keys.toList()..sort();
        return RefreshIndicator(
          onRefresh: signals.fetchRemote,
          color: AppTheme.primary,
          child: ListView.separated(
            /*
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            */
            // Gene - Nov, 12, 2026: Added 96dp bottom scroll clearance so the floating "+ Add LCP NAP" pill never obscures the final cabinet row.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: cabinets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final name = cabinets[index];
              final naps = grouped[name] ?? const <LcpNapDto>[];
              return _CabinetRow(
                name: name,
                naps: naps,
                onTap: () => _openCabinet(name),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCabinetFilterButton(LcpNapSignals signals, bool isDark) {
    return SignalBuilder(
      builder: (context) {
        final cabinets = signals.lcpCabinetList.value;
        final selected = signals.selectedLcpFilter.value;

        return OutlinedButton.icon(
          onPressed: () => _showCabinetSelectionModal(
              context, signals, cabinets, selected, isDark),
          icon: const Icon(Icons.filter_list_rounded, size: 24),
          label: Text(
            selected == 'All' ? 'Filter LCP' : selected,
            style: context.text.labelLarge!.copyWith(
              fontWeight: selected != 'All' ? FontWeight.w800 : null,
              color: selected != 'All' ? AppTheme.brandInkOf(context) : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(
              color: selected != 'All'
                  ? AppTheme.primary
                  : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            ),
          ),
        );
      },
    );
  }

  /*
  void _showCabinetSelectionModal(
    BuildContext context,
    LcpNapSignals signals,
    List<String> cabinets,
    String currentSelected,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            // Clear the system navigation bar, which otherwise covers the
            // last row of the sheet.
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 24 + MediaQuery.of(context).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // iOS Grabber Pill
                Center(
                  child: Container(
                    width: 36,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF38383A)
                          : const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.tray_2_fill,
                            color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Filter by LCP Cabinet',
                          style: context.text.titleMedium,
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppTheme.darkInput : AppTheme.fillLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 24,
                          color: isDark ? Colors.white : AppTheme.darkSlate,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Select an LCP Cabinet to isolate its NAP plant locations:',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: cabinets.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color:
                          isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    ),
                    itemBuilder: (context, index) {
                      final cabinet = cabinets[index];
                      final isSelected = cabinet == currentSelected;

                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        title: Text(
                          cabinet == 'All'
                              ? 'All Cabinets (Show Everything)'
                              : cabinet,
                          style: context.text.titleSmall!.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppTheme.brandInkOf(context)
                                : null,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(CupertinoIcons.checkmark_alt,
                                color: AppTheme.primary, size: 18)
                            : null,
                        onTap: () {
                          signals.setLcpFilter(cabinet);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  */
  // Gene - Nov, 12, 2026: Replaced dense unsearchable modal list with shared searchable 52dp-row LCP Cabinet bottom-sheet picker.
  Future<void> _showCabinetSelectionModal(
    BuildContext context,
    LcpNapSignals signals,
    List<String> cabinets,
    String currentSelected,
    bool isDark,
  ) async {
    final grouped = signals.groupedByLcp.value;
    final napCounts = <String, int>{
      for (final entry in grouped.entries) entry.key: entry.value.length,
    };
    final selected = await showLcpCabinetPickerSheet(
      context: context,
      cabinets: cabinets,
      napCounts: napCounts,
      currentSelected: currentSelected,
      includeAllOption: true,
      title: 'Filter by LCP Cabinet',
      subtitle: 'Select an LCP Cabinet to isolate its NAP plant locations:',
    );
    if (selected != null) {
      signals.setLcpFilter(selected);
    }
  }

  Widget _buildEmptyState(BuildContext context, LcpNapSignals signals) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primarySubtleBgOf(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primarySubtleBorderOf(context),
                  width: 0.5,
                ),
              ),
              child: const Icon(
                CupertinoIcons.map_pin_ellipse,
                size: 32,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No LCP NAP sites match',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Try adjusting your search query or reset the LCP cabinet filter.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                signals.setLcpFilter('All');
                signals.setSearch('');
                _searchController.clear();
              },
              icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 24),
              label: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The view switch and the cabinet filter share one row until a large text
/// setting makes them fight for width. Each segment of the switch gets half
/// of whatever the filter button leaves, and the button grows with the text
/// (its label is the cabinet name), so at large scales the switch was scaled
/// down to unreadable. From [stackAboveScale] the filter drops to its own
/// full-width line and both controls keep their real size.
class _LcpNapToolbar extends StatelessWidget {
  final Widget viewSwitch;
  final Widget filterButton;

  const _LcpNapToolbar({
    required this.viewSwitch,
    required this.filterButton,
  });

  /// Text scale factor above which the two controls are stacked.
  static const double stackAboveScale = 1.2;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale > stackAboveScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          viewSwitch,
          const SizedBox(height: 8),
          filterButton,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: viewSwitch),
        const SizedBox(width: 8),
        filterButton,
      ],
    );
  }
}

/// `241 cabinets · 1573 NAPs · 23184 ports`, counts in mono.
class _PlantSummaryLine extends StatelessWidget {
  final int cabinets;
  final int naps;
  final int ports;

  const _PlantSummaryLine({
    required this.cabinets,
    required this.naps,
    required this.ports,
  });

  @override
  Widget build(BuildContext context) {
    final mono = context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w500);
    final unit = context.text.bodyMedium!
        .copyWith(color: AppTheme.secondaryInkOf(context));
    TextSpan pair(int n, String u) => TextSpan(children: [
          TextSpan(text: '$n', style: mono),
          TextSpan(text: ' $u', style: unit),
        ]);
    final dot = TextSpan(text: '  ·  ', style: unit);
    return Text.rich(
      TextSpan(children: [
        pair(cabinets, cabinets == 1 ? 'cabinet' : 'cabinets'),
        dot,
        pair(naps, naps == 1 ? 'NAP' : 'NAPs'),
        dot,
        pair(ports, ports == 1 ? 'port' : 'ports'),
      ]),
    );
  }
}

/// One cabinet as a flat row: name, where it stands, and `NAPs · ports` in
/// mono on the right. No nested cards (DESIGN.md).
class _CabinetRow extends StatelessWidget {
  final String name;
  final List<LcpNapDto> naps;
  final VoidCallback onTap;

  const _CabinetRow({
    required this.name,
    required this.naps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = naps.isEmpty ? null : naps.first;
    final place = [
      if (first?.barangay?.isNotEmpty == true) first!.barangay!,
      if (first?.city?.isNotEmpty == true) first!.city!,
    ].join(', ');
    final ports = naps.fold<int>(0, (sum, n) => sum + n.portTotal);
    final secondary = AppTheme.secondaryInkOf(context);

    return Material(
      color: AppTheme.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        side: BorderSide(color: AppTheme.hairlineOf(context), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: context.text.titleMedium),
                      if (place.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(place,
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${naps.length} · $ports',
                  style: context.text.bodyLarge!.copyWith(color: secondary),
                  semanticsLabel: '${naps.length} NAPs, $ports ports',
                ),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_forward,
                    size: 20, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
