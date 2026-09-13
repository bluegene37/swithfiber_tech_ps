import 'package:flutter/material.dart';
import '../../../core/widgets/searchable_picker_sheet.dart';
import '../models/catalog_model.dart';

/// The ONT / router model picker shared by the completion report and the
/// repair form: a searchable bottom sheet over the approved catalog, the
/// same control as the NAP box picker.
///
/// The catalog is expected to grow, so the sheet filters on brand, model
/// and description as the technician types ("zte", "6486", "dual band").
class RouterModelPicker {
  RouterModelPicker._();

  static const String title = 'Select ONT Model';
  static const String searchHint = 'Filter models (e.g. Huawei, ZTE)...';

  /// The catalog with the current value listed first when the catalog does
  /// not carry it (a legacy or renamed model), so what is on file stays
  /// visible and selectable instead of vanishing from the form.
  static List<RouterDto> options(List<RouterDto> routers, String? current) {
    final value = current?.trim() ?? '';
    if (value.isEmpty || routers.any((r) => r.compactName == value)) {
      return routers;
    }
    return [
      RouterDto(id: -1, name: value, description: '', brand: '', model: ''),
      ...routers,
    ];
  }

  /// Opens the sheet and resolves to the chosen compact name (`ZTE F670L`),
  /// or null when dismissed.
  static Future<String?> show(
    BuildContext context, {
    required List<RouterDto> routers,
    required String? selected,
  }) async {
    final picked = await SearchablePickerSheet.show<RouterDto>(
      context,
      title: title,
      icon: Icons.router_rounded,
      searchHint: searchHint,
      items: options(routers, selected),
      titleOf: (r) => r.compactName,
      subtitleOf: (r) => r.brand,
      matches: (r, q) => r.displayName.toLowerCase().contains(q),
      isSelected: (r) => r.compactName == selected?.trim(),
      emptyMessage: (q) => 'No model matching "$q"',
    );
    return picked?.compactName;
  }
}
