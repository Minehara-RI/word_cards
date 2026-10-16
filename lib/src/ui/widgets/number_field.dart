import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 数字输入框：失焦、回车或点空白处提交，提交时自动夹到 [min]–[max]。
///
/// 全应用统一用这一个：作答页的每题限时、演示页的停留时间与提示音参数
/// 都不再提供「档位」按钮，只留输入框，避免界面上两套口径打架。
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.helper,
    this.suffix,
    this.width = 200,
    this.fieldKey,
  });

  final Key? fieldKey;
  final String label;
  final String? helper;
  final String? suffix;
  final int value;
  final int min;
  final int max;
  final double width;
  final ValueChanged<int> onCommit;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toString());
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 正在输入时不要被外部值打断，其它情况跟着设置走。
    if (!_focus.hasFocus && _controller.text != widget.value.toString()) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final int parsed = int.tryParse(_controller.text.trim()) ?? widget.value;
    final int next = parsed.clamp(widget.min, widget.max);
    _controller.text = next.toString();
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          suffixText: widget.suffix,
          isDense: true,
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}
