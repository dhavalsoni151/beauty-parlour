import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/expense_provider.dart';
import '../../core/models/visit_models.dart';

class ExpenseFormScreen extends StatefulWidget {
  final int? expenseId;
  const ExpenseFormScreen({super.key, this.expenseId});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int? _categoryId;
  DateTime _date = DateTime.now();
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _isSaving = false;
  Expense? _existing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ExpenseProvider>().loadCategories();
      if (widget.expenseId != null) _loadExpense();
    });
  }

  Future<void> _loadExpense() async {
    // Load from list
    final list = context.read<ExpenseProvider>().expenses;
    _existing = list.firstWhere((e) => e.id == widget.expenseId, orElse: () => throw Exception('not found'));
    if (_existing != null) {
      _descCtrl.text = _existing!.description;
      _amountCtrl.text = _existing!.amount.toStringAsFixed(0);
      _notesCtrl.text = _existing!.notes ?? '';
      _categoryId = _existing!.expenseCategoryId;
      _date = DateTime.parse(_existing!.expenseDate);
      _paymentMethod = _existing!.paymentMethod;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F0F5),
      appBar: AppBar(title: Text(widget.expenseId != null ? 'Edit Expense' : 'Add Expense')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final cats = provider.categories;
          if (_categoryId == null && cats.isNotEmpty) {
            _categoryId = cats.first.id;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard([
                  // Date
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F0F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF6B6B8A)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(
                            '${_date.day}/${_date.month}/${_date.year}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
                          )),
                          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9EBB), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Category
                  DropdownButtonFormField<int>(
                    value: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  // Description
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description *',
                      prefixIcon: Icon(Icons.description_rounded, size: 20),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  // Amount
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount *',
                      prefixText: '₹ ',
                      prefixIcon: Icon(Icons.currency_rupee_rounded, size: 20),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val <= 0) return 'Enter valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  // Payment Method
                  DropdownButtonFormField<PaymentMethod>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method'),
                    items: PaymentMethodX.all.map((m) =>
                      DropdownMenuItem(value: m, child: Text(m.label))).toList(),
                    onChanged: (m) => setState(() => _paymentMethod = m!),
                  ),
                  const SizedBox(height: 12),
                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      prefixIcon: Icon(Icons.note_rounded, size: 20),
                    ),
                    maxLines: 2,
                  ),
                ]),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(widget.expenseId != null ? 'Save Changes' : 'Add Expense'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(children: children),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final expense = Expense(
        id: _existing?.id,
        expenseCategoryId: _categoryId!,
        expenseDate: _date.toIso8601String().substring(0, 10),
        description: _descCtrl.text.trim(),
        amount: double.parse(_amountCtrl.text),
        paymentMethod: _paymentMethod,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdDate: _existing?.createdDate ?? now,
      );
      final provider = context.read<ExpenseProvider>();
      if (_existing != null) {
        await provider.updateExpense(expense);
      } else {
        await provider.addExpense(expense);
      }
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
