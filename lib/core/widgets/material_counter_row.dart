import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// One material on the completion report or repair form: its name and unit,
/// a minus button, a typeable quantity, and a plus button.
///
/// The quantity is a real numeric field, not a read-only count, so a
/// technician who used 45 metres of drop cable types `45` instead of
/// tapping plus forty-five times. The buttons stay for one-off nudges.
///
/// The field only ever holds digits. An empty field means zero while it is
/// being edited (so clearing it to retype does not fight the technician);
/// on blur the text is normalised to the value that was recorded.
class MaterialCounterRow extends StatefulWidget {
  final String name;
  final String unit;
  final int count;
  final ValueChanged<int> onChanged;

  /// Widget keys for tests: the minus button, the field, the plus button.
  final Key? minusKey;
  final Key? fieldKey;
  final Key? plusKey;

  /// Largest quantity the field accepts; more digits are refused.
  static const int maxDigits = 5;

  const MaterialCounterRow({
    super.key,
    required this.name,
    required this.unit,
    required this.count,
    required this.onChanged,
    this.minusKey,
    this.fieldKey,
    this.plusKey,
  });

  @override
  State<MaterialCounterRow> createState() => _MaterialCounterRowState();
}

class _MaterialCounterRowState extends State<MaterialCounterRow> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.count}');
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(MaterialCounterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A plus or minus tap (or a value restored from the job) changes the
    // count from outside. Reflect it unless the field already reads that
    // number, so typing is never interrupted by its own echo.
    if (widget.count != oldWidget.count && _parsed != widget.count) {
      _setText('${widget.count}');
    }
  }

  int get _parsed => int.tryParse(_controller.text) ?? 0;

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      // Select everything so the first keystroke replaces the old number.
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else if (_controller.text != '${widget.count}') {
      // Leaving the field: '' becomes 0, '007' becomes 7.
      _setText('${widget.count}');
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.name, style: context.text.titleSmall),
              Text(widget.unit, style: context.text.labelSmall),
            ],
          ),
        ),
        IconButton(
          key: widget.minusKey,
          tooltip: 'Less ${widget.name}',
          constraints: const BoxConstraints(
              minWidth: AppTheme.minTarget, minHeight: AppTheme.minTarget),
          onPressed: count > 0 ? () => widget.onChanged(count - 1) : null,
          icon: const Icon(CupertinoIcons.minus_circle, size: 24),
        ),
        SizedBox(
          width: 72,
          child: Semantics(
            label: '${widget.name} quantity',
            child: TextField(
              key: widget.fieldKey,
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(MaterialCounterRow.maxDigits),
              ],
              style: context.text.titleSmall!.copyWith(
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w700,
              ),
              // Vertical padding chosen so the field itself is a 48dp
              // target at normal text and grows with the type above it.
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
              onChanged: (text) {
                final value = int.tryParse(text) ?? 0;
                if (value != count) widget.onChanged(value);
              },
              onSubmitted: (_) => _focus.unfocus(),
            ),
          ),
        ),
        IconButton(
          key: widget.plusKey,
          tooltip: 'More ${widget.name}',
          constraints: const BoxConstraints(
              minWidth: AppTheme.minTarget, minHeight: AppTheme.minTarget),
          onPressed: () => widget.onChanged(count + 1),
          icon: const Icon(CupertinoIcons.plus_circle_fill,
              size: 24, color: AppTheme.primary),
        ),
      ],
    );
  }
}
