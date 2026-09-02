import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/expense_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../../core/models/visit_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String? _startDate;
  String? _endDate;
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    final range = DateRange.thisMonth();
    _startDate = range.start.toIso8601String();
    _endDate = range.end.toIso8601String();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ExpenseProvider>().loadCategories();
      await context.read<ExpenseProvider>().loadExpenses(
        startDate: _startDate,
        endDate: _endDate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_rounded),
            onPressed: () => context.push('/expense-categories').then((_) =>
              context.read<ExpenseProvider>().loadCategories()),
            tooltip: 'Manage Categories',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range filter
          _buildFilters(),
          // Expenses list
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) return const Center(child: CircularProgressIndicator());
                final expenses = provider.expenses;
                final total = provider.totalExpenses;

                return Column(
                  children: [
                    if (expenses.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_rounded, color: AppColors.warning, size: 18),
                            const SizedBox(width: 8),
                            Text('Total: ${AppFormatters.formatCurrency(total)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.warning)),
                            const Spacer(),
                            Text('${expenses.length} expenses',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: expenses.isEmpty
                          ? EmptyState(
                              title: 'No Expenses',
                              subtitle: 'Record your first expense',
                              icon: Icons.receipt_rounded,
                              actionLabel: 'Add Expense',
                              onAction: () => context.push('/expense/new').then((_) => _reload()),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                              itemCount: expenses.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) => _ExpenseCard(
                                expense: expenses[i],
                                onEdit: () => context.push('/expense/${expenses[i].id}/edit').then((_) => _reload()),
                                onDelete: () => _deleteExpense(expenses[i].id!),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expense/new').then((_) => _reload()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        DateRangeSelector(
          onRangeSelected: (s, e, _) {
            setState(() { _startDate = s; _endDate = e; });
            _reload();
          },
        ),
        Consumer<ExpenseProvider>(
          builder: (context, provider, _) {
            if (provider.categories.isEmpty) return const SizedBox.shrink();
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  _filterChip('All', null, provider),
                  ...provider.categories.map((c) => _filterChip(c.name, c.id, provider)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _filterChip(String label, int? id, ExpenseProvider provider) {
    final selected = _selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedCategoryId = id);
          _reload();
        },
        backgroundColor: Colors.white,
        selectedColor: AppColors.warning,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.warning : AppColors.divider),
      ),
    );
  }

  void _reload() {
    context.read<ExpenseProvider>().loadExpenses(
      startDate: _startDate,
      endDate: _endDate,
      categoryId: _selectedCategoryId,
    );
  }

  Future<void> _deleteExpense(int id) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Expense',
      message: 'Are you sure you want to delete this expense?',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
    );
    if (confirmed && mounted) {
      await context.read<ExpenseProvider>().deleteExpense(id);
      if (mounted) await context.read<DashboardProvider>().loadDashboard();
    }
  }
}

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExpenseCard({required this.expense, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_rounded, color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.description,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(expense.categoryName ?? '',
                        style: const TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Text(AppFormatters.formatDate(DateTime.parse(expense.expenseDate)),
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    const SizedBox(width: 6),
                    Text(expense.paymentMethod.label,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(AppFormatters.formatCurrency(expense.amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.warning)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 18),
            onSelected: (v) { if (v == 'edit') onEdit(); else onDelete(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(
                leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true)),
              const PopupMenuItem(value: 'delete', child: ListTile(
                leading: Icon(Icons.delete_rounded, color: Colors.red), title: Text('Delete'), dense: true)),
            ],
          ),
        ],
      ),
    );
  }
}
