import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

const int kPinLength = 4;

/// Shared numeric keypad used for PIN entry, confirmation and unlock.
class PinPad extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final int length;

  const PinPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.length = kPinLength,
  });

  void _append(String digit) {
    if (value.length >= length) return;
    onChanged(value + digit);
  }

  void _backspace() {
    if (value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(length, (i) {
            final filled = i < value.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.primary : Colors.transparent,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: 280,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.4,
            children: keys.map((k) {
              if (k.isEmpty) return const SizedBox.shrink();
              return _PinKey(
                label: k,
                onTap: () => k == '⌫' ? _backspace() : _append(k),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
