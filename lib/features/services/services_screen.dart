import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/category_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/database/daos/db_exceptions.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class ServicesScreen extends StatefulWidget {
  final int? initialCategoryId;
  const ServicesScreen({super.key, this.initialCategoryId});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CategoryProvider>().loadCategories();
      await context.read<ServiceProvider>().loadServices();
      if (widget.initialCategoryId != null) {
        context.read<ServiceProvider>().filterByCategory(widget.initialCategoryId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Services')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppSearchBar(
              hint: 'Search services...',
              onChanged: (q) => context.read<ServiceProvider>().search(q),
            ),
          ),
          Consumer<CategoryProvider>(
            builder: (context, catProvider, _) {
              return Consumer<ServiceProvider>(
                builder: (context, svcProvider, _) {
                  final cats = catProvider.activeCategories;
                  if (cats.isEmpty) return const SizedBox.shrink();
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        _buildChip('All', null, svcProvider),
                        ...cats.map((c) => _buildChip(c.name, c.id!, svcProvider)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          Expanded(
            child: Consumer<ServiceProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final services = provider.services;
                if (services.isEmpty) {
                  return EmptyState(
                    title: 'No Services',
                    subtitle: 'Add services to start billing customers',
                    icon: Icons.spa_rounded,
                    actionLabel: 'Add Service',
                    onAction: () => _showServiceDialog(context),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: services.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ServiceCard(
                    service: services[i],
                    onEdit: () => _showServiceDialog(context, services[i]),
                    onToggle: () =>
                        context.read<ServiceProvider>().toggleActive(services[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showServiceDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Service'),
      ),
    );
  }

  Widget _buildChip(String label, int? categoryId, ServiceProvider provider) {
    final selected = provider.selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => provider.filterByCategory(categoryId),
        backgroundColor: Colors.white,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
      ),
    );
  }

  Future<void> _showServiceDialog(BuildContext context, [Service? existing]) async {
    final catProvider = context.read<CategoryProvider>();
    final cats = catProvider.activeCategories;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a category first')),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.defaultPrice.toStringAsFixed(0) ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final orderCtrl = TextEditingController(
        text: existing != null ? existing.displayOrder.toString() : '');
    int? selectedCategoryId = existing?.categoryId ?? cats.first.id;
    int? selectedTypeId = existing?.serviceTypeId;
    List<ServiceType> types = selectedCategoryId != null
        ? await catProvider.getServiceTypesForCategory(selectedCategoryId)
        : [];
    final formKey = GlobalKey<FormState>();
    final now = DateTime.now().toIso8601String();

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Load service types for the currently selected category.
          Future<void> reloadTypes(int categoryId) async {
            final loaded =
                await catProvider.getServiceTypesForCategory(categoryId);
            setDialogState(() {
              types = loaded;
              if (selectedTypeId != null &&
                  !types.any((t) => t.id == selectedTypeId)) {
                selectedTypeId = null;
              }
            });
          }

          return AlertDialog(
            title: Text(existing != null ? 'Edit Service' : 'New Service'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Category *'),
                      items: cats
                          .map((c) => DropdownMenuItem<int>(
                              value: c.id!, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          selectedCategoryId = v;
                          selectedTypeId = null;
                          types = [];
                        });
                        if (v != null) reloadTypes(v);
                      },
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: selectedTypeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Service Type (Optional)'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('None (directly under category)')),
                        ...types.map((t) => DropdownMenuItem<int?>(
                            value: t.id, child: Text(t.name))),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedTypeId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Service Name *'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Default Price (₹) *', prefixText: '₹ '),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final parsed = double.tryParse(v);
                        if (parsed == null) return 'Invalid';
                        if (parsed < 0) return 'Must be >= 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Description (Optional)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: orderCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Display Order (Optional)'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final svc = Service(
                    id: existing?.id,
                    categoryId: selectedCategoryId!,
                    serviceTypeId: selectedTypeId,
                    name: nameCtrl.text.trim(),
                    defaultPrice: double.parse(priceCtrl.text),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    createdDate: existing?.createdDate ?? now,
                    isActive: existing?.isActive ?? true,
                    displayOrder: int.tryParse(orderCtrl.text.trim()) ??
                        existing?.displayOrder ??
                        0,
                  );
                  final provider = ctx.read<ServiceProvider>();
                  try {
                    if (existing != null) {
                      await provider.updateService(svc);
                    } else {
                      await provider.addService(svc);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
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
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Service service;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _ServiceCard(
      {required this.service, required this.onEdit, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: service.isActive ? Colors.white : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(service.categoryName ?? '',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: service.isActive
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    )),
                if (service.serviceTypeName != null &&
                    service.serviceTypeName!.isNotEmpty)
                  Text(service.serviceTypeName!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                if (!service.isActive)
                  const Text('Inactive',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Text(AppFormatters.formatCurrency(service.defaultPrice),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textHint, size: 20),
            onSelected: (v) {
              if (v == 'edit') {
                onEdit();
              } else if (v == 'toggle') {
                onToggle();
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
                    leading: Icon(service.isActive
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    title: Text(service.isActive ? 'Deactivate' : 'Activate'),
                    dense: true,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
