import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/category_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/database/daos/db_exceptions.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

/// Lists the service types within a single category. Each type can be
/// expanded to show its services. Services with no type are handled on the
/// Services screen (directly under a category).
class ServiceTypesScreen extends StatefulWidget {
  final int categoryId;
  const ServiceTypesScreen({super.key, required this.categoryId});

  @override
  State<ServiceTypesScreen> createState() => _ServiceTypesScreenState();
}

class _ServiceTypesScreenState extends State<ServiceTypesScreen> {
  Category? _category;
  List<ServiceType> _types = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final catProvider = context.read<CategoryProvider>();
    if (catProvider.categories.isEmpty) {
      await catProvider.loadCategories();
    }
    _category = catProvider.categories
        .where((c) => c.id == widget.categoryId)
        .cast<Category?>()
        .firstWhere((c) => c != null, orElse: () => null);
    _types = await catProvider.loadServiceTypes(widget.categoryId);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_category?.name ?? 'Service Types'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _types.isEmpty
              ? EmptyState(
                  title: 'No Service Types',
                  subtitle:
                      'Add service types (e.g. "Rica Wax") to group services under this category',
                  icon: Icons.account_tree_rounded,
                  actionLabel: 'Add Service Type',
                  onAction: () => _showTypeDialog(),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _TypeCard(
                    type: _types[i],
                    onEdit: () => _showTypeDialog(_types[i]),
                    onToggle: () async {
                      await context
                          .read<CategoryProvider>()
                          .toggleServiceTypeActive(_types[i]);
                      _load();
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTypeDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Type'),
      ),
    );
  }

  Future<void> _showTypeDialog([ServiceType? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final orderCtrl = TextEditingController(
        text: existing != null ? existing.displayOrder.toString() : '');
    final formKey = GlobalKey<FormState>();
    final now = DateTime.now().toIso8601String();
    final provider = context.read<CategoryProvider>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Service Type' : 'New Service Type'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Type Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: orderCtrl,
                decoration:
                    const InputDecoration(labelText: 'Display Order (Optional)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final type = ServiceType(
                id: existing?.id,
                categoryId: widget.categoryId,
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty
                    ? null
                    : descCtrl.text.trim(),
                createdDate: existing?.createdDate ?? now,
                isActive: existing?.isActive ?? true,
                displayOrder: int.tryParse(orderCtrl.text.trim()) ??
                    existing?.displayOrder ??
                    0,
              );
              try {
                if (existing != null) {
                  await provider.updateServiceType(type);
                } else {
                  await provider.addServiceType(type);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } on DuplicateException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: Text(existing != null ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatefulWidget {
  final ServiceType type;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _TypeCard(
      {required this.type, required this.onEdit, required this.onToggle});

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  List<Service>? _services;
  bool _expanded = false;

  Future<void> _loadServices() async {
    final services = await context
        .read<ServiceProvider>()
        .getServicesForCategory(widget.type.categoryId,
            serviceTypeId: widget.type.id);
    if (mounted) setState(() => _services = services);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    return Container(
      decoration: BoxDecoration(
        color: t.isActive ? Colors.white : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.isActive
                    ? AppColors.primaryContainer
                    : AppColors.divider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.account_tree_rounded,
                  color: t.isActive ? AppColors.primary : AppColors.textHint),
            ),
            title: Text(t.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.isActive ? AppColors.textPrimary : AppColors.textHint,
                )),
            subtitle: Text('${t.serviceCount} Services',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textHint),
              onSelected: (v) {
                if (v == 'edit') {
                  widget.onEdit();
                } else if (v == 'toggle') {
                  widget.onToggle();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_rounded),
                        title: Text('Edit'),
                        dense: true)),
                PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      leading: Icon(t.isActive
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      title: Text(t.isActive ? 'Deactivate' : 'Activate'),
                      dense: true,
                    )),
              ],
            ),
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded && _services == null) _loadServices();
            },
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _services == null
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    )
                  : _services!.isEmpty
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No services yet',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textHint)),
                        )
                      : Column(
                          children: _services!
                              .map((s) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.circle,
                                            size: 6,
                                            color: AppColors.textHint),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(s.name,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        AppColors.textPrimary))),
                                        Text(
                                            AppFormatters.formatCurrency(
                                                s.defaultPrice),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary)),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
            ),
        ],
      ),
    );
  }
}
