// Gene - Nov, 12, 2026: Created reusable searchable LCP Cabinet bottom-sheet picker with 52dp touch targets for 241+ cabinets.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_search_field.dart';

/// Opens a searchable bottom-sheet picker for selecting an LCP Cabinet.
///
/// Supports both the Plant screen's cabinet filter (`includeAllOption: true`,
/// returning `'All'` for "All Cabinets") and the Create/Edit sheet
/// (`allowCustomCabinet: true`, letting technicians either pick an existing
/// cabinet or confirm a newly typed cabinet name).
Future<String?> showLcpCabinetPickerSheet({
  required BuildContext context,
  required List<String> cabinets,
  Map<String, int> napCounts = const {},
  String? currentSelected,
  bool includeAllOption = false,
  bool allowCustomCabinet = false,
  String title = 'Select LCP Cabinet',
  String? subtitle,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => LcpCabinetPickerSheet(
      cabinets: cabinets,
      napCounts: napCounts,
      currentSelected: currentSelected,
      includeAllOption: includeAllOption,
      allowCustomCabinet: allowCustomCabinet,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class LcpCabinetPickerSheet extends StatefulWidget {
  final List<String> cabinets;
  final Map<String, int> napCounts;
  final String? currentSelected;
  final bool includeAllOption;
  final bool allowCustomCabinet;
  final String title;
  final String? subtitle;

  const LcpCabinetPickerSheet({
    super.key,
    required this.cabinets,
    this.napCounts = const {},
    this.currentSelected,
    this.includeAllOption = false,
    this.allowCustomCabinet = false,
    this.title = 'Select LCP Cabinet',
    this.subtitle,
  });

  @override
  State<LcpCabinetPickerSheet> createState() => _LcpCabinetPickerSheetState();
}

class _LcpCabinetPickerSheetState extends State<LcpCabinetPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomInset = viewInsetsBottom > 0 ? viewInsetsBottom : safeBottom;

    final normalizedQuery = _query.trim().toLowerCase();
    final realCabinets = widget.cabinets
        .where((c) => c != 'All' && c.trim().isNotEmpty)
        .toList();

    final filteredCabinets = normalizedQuery.isEmpty
        ? realCabinets
        : realCabinets
            .where((c) => c.toLowerCase().contains(normalizedQuery))
            .toList();

    final hasExactMatch = realCabinets.any(
      (c) => c.trim().toLowerCase() == normalizedQuery,
    );
    final showCustomEntry =
        widget.allowCustomCabinet && normalizedQuery.isNotEmpty && !hasExactMatch;
    final customValue = _query.trim().toUpperCase();
    final showAllRow = widget.includeAllOption && normalizedQuery.isEmpty;

    final totalRows = (showAllRow ? 1 : 0) +
        (showCustomEntry ? 1 : 0) +
        filteredCabinets.length;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber pill
            Center(
              child: Container(
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTheme.hairlineOf(context),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.tray_2_fill,
                  color: AppTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: context.text.titleLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('btnCloseCabinetPicker'),
                  tooltip: 'Close',
                  constraints: const BoxConstraints(
                    minWidth: AppTheme.minTarget,
                    minHeight: AppTheme.minTarget,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppTheme.inkOf(context),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              Text(
                widget.subtitle!,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 6),
            AppSearchField(
              key: const ValueKey('inputSearchCabinetPicker'),
              controller: _searchController,
              hintText: 'Search LCP cabinet...',
              onChanged: (val) => setState(() => _query = val),
            ),
            const SizedBox(height: 12),
            if (totalRows == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 28,
                      color: AppTheme.secondaryInkOf(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No LCP cabinets match "$_query"',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: totalRows,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                  itemBuilder: (context, index) {
                    var cursor = index;

                    if (showAllRow) {
                      if (cursor == 0) {
                        final isSelected = widget.currentSelected == null ||
                            widget.currentSelected == 'All';
                        return _CabinetOptionRow(
                          rowKey: const ValueKey('cabinetOption_All'),
                          label: 'All Cabinets (Show Everything)',
                          countLabel: '${realCabinets.length} LCPs',
                          isSelected: isSelected,
                          onTap: () => Navigator.of(context).pop('All'),
                        );
                      }
                      cursor -= 1;
                    }

                    if (showCustomEntry) {
                      if (cursor == 0) {
                        return _CabinetOptionRow(
                          rowKey: const ValueKey('cabinetOption_Custom'),
                          label: 'Use "$customValue"',
                          subtitle: 'Create new LCP cabinet group',
                          leadingIcon: Icons.add_circle_outline_rounded,
                          isSelected: false,
                          highlightBrand: true,
                          onTap: () => Navigator.of(context).pop(customValue),
                        );
                      }
                      cursor -= 1;
                    }

                    final cabinet = filteredCabinets[cursor];
                    final isSelected = cabinet == widget.currentSelected;
                    final napsCount = widget.napCounts[cabinet];
                    return _CabinetOptionRow(
                      rowKey: ValueKey('cabinetOption_$cabinet'),
                      label: cabinet,
                      countLabel: napsCount != null
                          ? '$napsCount ${napsCount == 1 ? 'NAP' : 'NAPs'}'
                          : null,
                      isSelected: isSelected,
                      onTap: () => Navigator.of(context).pop(cabinet),
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

class _CabinetOptionRow extends StatelessWidget {
  final Key? rowKey;
  final String label;
  final String? subtitle;
  final String? countLabel;
  final IconData? leadingIcon;
  final bool isSelected;
  final bool highlightBrand;
  final VoidCallback onTap;

  const _CabinetOptionRow({
    this.rowKey,
    required this.label,
    this.subtitle,
    this.countLabel,
    this.leadingIcon,
    required this.isSelected,
    this.highlightBrand = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.brandInkOf(context);
    return InkWell(
      key: rowKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        // DESIGN.md: Sheets keep every option at least a 52dp target.
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 22, color: accent),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.text.titleSmall!.copyWith(
                        fontWeight: (isSelected || highlightBrand)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: (isSelected || highlightBrand) ? accent : null,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (countLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  countLabel!,
                  style: context.text.bodyLarge!.copyWith(
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ),
              ],
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.checkmark_alt,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
