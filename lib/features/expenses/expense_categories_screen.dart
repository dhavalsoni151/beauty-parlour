import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/expense_provider.dart';
import '../../core/models/visit_models.dart';

class ExpenseCategoriesScreen extends StatelessWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F0F5),
      appBar: AppBar(title: const Text('Expense Categories')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final cats = provider.categories;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: ListTile(
                leading: const Icon(Icons.label_rounded, color: AppColors.warning),
                title: Text(cats[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _showEditDialog(context, provider, cats[i]);
                    else if (v == 'toggle') provider.updateCategory(
                      ExpenseCategory(id: cats[i].id, name: cats[i].name, isActive: !cats[i].isActive));
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'toggle', child: Text(cats[i].isActive ? 'Deactivate' : 'Activate')),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category'),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await context.read<ExpenseProvider>().addCategory(
                ExpenseCategory(name: ctrl.text.trim()));
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, ExpenseProvider provider, ExpenseCategory cat) async {
    final ctrl = TextEditingController(text: cat.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await provider.updateCategory(
                ExpenseCategory(id: cat.id, name: ctrl.text.trim(), isActive: cat.isActive));
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
