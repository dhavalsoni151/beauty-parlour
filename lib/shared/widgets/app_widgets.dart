import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/visit_models.dart';
import '../../core/utils/formatters.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textHint),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentStatusBadge extends StatelessWidget {
  final PaymentStatus status;

  const PaymentStatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case PaymentStatus.paid: return AppColors.paid;
      case PaymentStatus.partiallyPaid: return AppColors.partiallyPaid;
      case PaymentStatus.pending: return AppColors.pending;
      case PaymentStatus.writtenOff: return AppColors.writtenOff;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _color, letterSpacing: 0.3),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 13, color: AppColors.primary)),
          ),
      ],
    );
  }
}

class AppSearchBar extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const AppSearchBar({super.key, required this.hint, required this.onChanged, this.onClear});

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _hasText = _controller.text.isNotEmpty));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
        suffixIcon: _hasText
            ? GestureDetector(
                onTap: () {
                  _controller.clear();
                  widget.onChanged('');
                  widget.onClear?.call();
                },
                child: const Icon(Icons.clear_rounded, color: AppColors.textHint, size: 18),
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color? confirmColor;
  final VoidCallback onConfirm;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.confirmColor,
    required this.onConfirm,
  });

  static Future<bool> show(BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor ?? AppColors.primary,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class AmountText extends StatelessWidget {
  final double amount;
  final TextStyle? style;
  final bool showSign;
  final bool isNegative;

  const AmountText(this.amount, {super.key, this.style, this.showSign = false, this.isNegative = false});

  @override
  Widget build(BuildContext context) {
    final sign = showSign && amount > 0 ? '+' : '';
    final color = isNegative ? AppColors.error : (showSign && amount > 0 ? AppColors.success : null);
    return Text(
      '$sign${AppFormatters.formatCurrency(amount)}',
      style: (style ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
          .copyWith(color: style?.color ?? color),
    );
  }
}

class DateRangeSelector extends StatefulWidget {
  final Function(String startDate, String endDate, String label) onRangeSelected;
  final String initialLabel;

  const DateRangeSelector({
    super.key,
    required this.onRangeSelected,
    this.initialLabel = 'This Month',
  });

  @override
  State<DateRangeSelector> createState() => _DateRangeSelectorState();
}

class _DateRangeSelectorState extends State<DateRangeSelector> {
  late String _selectedLabel;

  final _options = [
    'Today', 'Yesterday', 'This Week', 'This Month', 'Last Month', 'This Year', 'Custom'
  ];

  @override
  void initState() {
    super.initState();
    _selectedLabel = widget.initialLabel;
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectRange(_selectedLabel));
  }

  void _selectRange(String label) {
    DateRange range;
    switch (label) {
      case 'Today': range = DateRange.today(); break;
      case 'Yesterday': range = DateRange.yesterday(); break;
      case 'This Week': range = DateRange.thisWeek(); break;
      case 'Last Month': range = DateRange.lastMonth(); break;
      case 'This Year': range = DateRange.thisYear(); break;
      default: range = DateRange.thisMonth();
    }
    widget.onRangeSelected(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
      label,
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final range = DateRange.custom(picked.start, picked.end);
      widget.onRangeSelected(
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        'Custom',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _options.map((label) {
          final selected = _selectedLabel == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedLabel = label);
                if (label == 'Custom') {
                  _pickCustomRange();
                } else {
                  _selectRange(label);
                }
              },
              backgroundColor: Colors.white,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
              checkmarkColor: Colors.white,
              side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }
}
