import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'app_search_field.dart';

/// A bottom sheet with a search field over a list of choices, one tap to
/// pick. The NAP box and ONT model pickers on the completion report and the
/// repair form are this one widget, so a catalog that grows (more router
/// models, more NAPs) stays searchable everywhere at once.
///
/// [T] is the catalog row. [titleOf] is the line the technician reads and
/// taps; [subtitleOf] an optional second line; [matches] decides whether a
/// row survives the typed filter; [isSelected] marks the current value.
class SearchablePickerSheet<T> extends StatefulWidget {
  final String title;
  final IconData icon;
  final String searchHint;
  final List<T> items;
  final String Function(T item) titleOf;
  final String? Function(T item)? subtitleOf;
  final bool Function(T item, String query) matches;
  final bool Function(T item) isSelected;

  /// What to say when nothing matches; receives the typed query.
  final String Function(String query) emptyMessage;

  const SearchablePickerSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.searchHint,
    required this.items,
    required this.titleOf,
    required this.matches,
    required this.isSelected,
    required this.emptyMessage,
    this.subtitleOf,
  });

  /// Presents the sheet and resolves to the tapped item, or null when the
  /// technician closed it without choosing.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String searchHint,
    required List<T> items,
    required String Function(T item) titleOf,
    required bool Function(T item, String query) matches,
    required bool Function(T item) isSelected,
    required String Function(String query) emptyMessage,
    String? Function(T item)? subtitleOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchablePickerSheet<T>(
        title: title,
        icon: icon,
        searchHint: searchHint,
        items: items,
        titleOf: titleOf,
        subtitleOf: subtitleOf,
        matches: matches,
        isSelected: isSelected,
        emptyMessage: emptyMessage,
      ),
    );
  }

  @override
  State<SearchablePickerSheet<T>> createState() =>
      _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<SearchablePickerSheet<T>> {
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
    final bg = isDark ? AppTheme.darkCard : Colors.white;
    final textTheme = Theme.of(context).textTheme;

    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((item) => widget.matches(item, _query.toLowerCase()))
            .toList();

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(widget.icon, size: 22, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Filter in list input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                controller: _searchController,
                hintText: widget.searchHint,
                onChanged: (val) => setState(() => _query = val.trim()),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),

            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 40,
                              color: AppTheme.secondaryInkOf(context)),
                          const SizedBox(height: 8),
                          Text(
                            widget.emptyMessage(_query),
                            textAlign: TextAlign.center,
                            style: context.text.bodyMedium!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final item = filtered[i];
                        final selected = widget.isSelected(item);
                        final subtitle = widget.subtitleOf?.call(item);
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primarySubtleBgOf(context)
                                  : AppTheme.fillOf(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              widget.icon,
                              size: 20,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.secondaryInkOf(context),
                            ),
                          ),
                          title: Text(
                            widget.titleOf(item),
                            style: context.text.titleSmall!.copyWith(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? AppTheme.brandInkOf(context)
                                  : null,
                            ),
                          ),
                          subtitle: subtitle != null && subtitle.isNotEmpty
                              ? Text(subtitle, style: context.text.bodySmall)
                              : null,
                          trailing: selected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: AppTheme.primary, size: 20)
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
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

/// The tappable form field that opens a [SearchablePickerSheet]: looks like
/// the other inputs on the form, shows the current value, and reads as a
/// button to assistive tech.
class PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    return Semantics(
      button: true,
      label: label,
      value: hasValue ? value : placeholder,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          child: Text(
            hasValue ? value! : placeholder,
            style: context.text.bodyMedium!.copyWith(
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              color: hasValue ? null : AppTheme.secondaryInkOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
