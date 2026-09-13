import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// NAP ports as a grid of 48dp mono tiles instead of a dropdown (DESIGN.md,
/// completion report). One tap picks a port, and the whole set is visible,
/// which is what a technician facing a 16-port box actually needs.
class PortTileGrid extends StatelessWidget {
  /// Port names as the catalog sends them, e.g. `PORT 001`.
  final List<String> ports;
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Ports already in use, drawn struck through and not selectable.
  final Set<String> unavailable;
  final int columns;

  const PortTileGrid({
    super.key,
    required this.ports,
    required this.selected,
    required this.onSelected,
    this.unavailable = const {},
    this.columns = 4,
  });

  /// `PORT 001` reads `01` on the tile; anything without digits keeps its
  /// name.
  static String tileLabel(String port) {
    final digits = RegExp(r'\d+').firstMatch(port)?.group(0);
    if (digits == null) return port;
    final n = int.parse(digits);
    return n < 10 ? '0$n' : '$n';
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(' ', '');

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.inkOf(context);
    final page = AppTheme.pageOf(context);
    final card = AppTheme.cardOf(context);
    final hairline = AppTheme.hairlineOf(context);
    final sel = selected == null ? null : _norm(selected!);

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        for (final port in ports)
          Builder(builder: (context) {
            final isSelected = sel != null && _norm(port) == sel;
            final isUsed = unavailable.contains(port);
            return Semantics(
              button: true,
              selected: isSelected,
              label: 'Port ${tileLabel(port)}${isUsed ? ', in use' : ''}',
              child: Material(
                color: isSelected ? ink : card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                  side:
                      BorderSide(color: isSelected ? ink : hairline, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: isUsed ? null : () => onSelected(port),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: AppTheme.minTarget),
                    child: Center(
                      child: Text(
                        tileLabel(port),
                        style: context.text.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? page
                              : (isUsed
                                  ? AppTheme.secondaryInkOf(context)
                                  : ink),
                          decoration:
                              isUsed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
