import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/category_provider.dart';
import '../../core/models/customer_models.dart';
import '../../shared/widgets/app_widgets.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Service Categories')),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          final cats = provider.categories;
          if (cats.isEmpty) {
            return EmptyState(
              title: 'No Categories',
              subtitle: 'Add categories to organize your services',
              icon: Icons.category_rounded,
              actionLabel: 'Add Category',
              onAction: () => _showCategoryDialog(context, provider),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CategoryCard(
              category: cats[i],
              onEdit: () => _showCategoryDialog(context, provider, cats[i]),
              onToggle: () => provider.toggleActive(cats[i]),
              onViewServices: () => context.push('/services?categoryId=${cats[i].id}'),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(context, context.read<CategoryProvider>()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category'),
      ),
    );
  }

  Future<void> _showCategoryDialog(BuildContext context, CategoryProvider provider, [Category? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final now = DateTime.now().toIso8601String();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Category' : 'New Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Category Name *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final cat = Category(
                id: existing?.id,
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                createdDate: existing?.createdDate ?? now,
                isActive: existing?.isActive ?? true,
              );
              if (existing != null) {
                await provider.updateCategory(cat);
              } else {
                await provider.addCategory(cat);
              }
              Navigator.pop(ctx);
            },
            child: Text(existing != null ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onViewServices;

  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onToggle,
    required this.onViewServices,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: category.isActive ? Colors.white : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: category.isActive ? AppColors.primaryContainer : AppColors.divider,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.spa_rounded,
              color: category.isActive ? AppColors.primary : AppColors.textHint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: category.isActive ? AppColors.textPrimary : AppColors.textHint,
                  )),
                Text('${category.serviceCount} services',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              else if (v == 'toggle') onToggle();
              else if (v == 'services') onViewServices();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'services', child: ListTile(
                leading: Icon(Icons.list_rounded), title: Text('View Services'), dense: true)),
              const PopupMenuItem(value: 'edit', child: ListTile(
                leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true)),
              PopupMenuItem(value: 'toggle', child: ListTile(
                leading: Icon(category.isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                title: Text(category.isActive ? 'Deactivate' : 'Activate'),
                dense: true,
              )),
            ],
          ),
        ],
      ),
    );
  }
}
