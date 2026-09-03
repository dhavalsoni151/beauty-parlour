import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/category_provider.dart';
import '../../core/providers/package_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/package_models.dart';
import '../../core/utils/formatters.dart';

class PackageFormScreen extends StatefulWidget {
  final int? packageId;
  const PackageFormScreen({super.key, this.packageId});

  @override
  State<PackageFormScreen> createState() => _PackageFormScreenState();
}

class _PackageFormScreenState extends State<PackageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 30));
  bool _isActive = true;
  bool _isSaving = false;
  bool _isLoading = true;
  Package? _existing;

  final List<PackageService> _services = [];

  bool get _isEditing => widget.packageId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<CategoryProvider>().loadCategories();
    if (widget.packageId != null) {
      final pkg = await context.read<PackageProvider>().getPackage(widget.packageId!);
      if (pkg != null) {
        _existing = pkg;
        _nameCtrl.text = pkg.name;
        _descCtrl.text = pkg.description ?? '';
        _priceCtrl.text = _formatNumber(pkg.packagePrice);
        _startDate = DateTime.tryParse(pkg.startDate) ?? DateTime.now();
        _expiryDate = DateTime.tryParse(pkg.expiryDate) ?? DateTime.now();
        _isActive = pkg.isActive;
        _services.addAll(pkg.services);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double get _normalTotal =>
      _services.fold(0.0, (s, x) => s + x.normalPrice * x.quantity);
  double get _packagePrice => double.tryParse(_priceCtrl.text) ?? 0;
  double get _discount => _normalTotal - _packagePrice;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_isEditing ? 'Edit Package' : 'New Package')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Package Name *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Package Price (₹) *', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDateTile('Start Date', _startDate, (d) => setState(() => _startDate = d))),
                const SizedBox(width: 12),
                Expanded(child: _buildDateTile('Expiry Date', _expiryDate, (d) => setState(() => _expiryDate = d))),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('Package Services',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                TextButton.icon(
                  onPressed: _addService,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Service'),
                ),
              ],
            ),
            if (_services.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No services added yet.', style: TextStyle(color: AppColors.textHint)),
              )
            else
              ..._services.asMap().entries.map((e) => _buildServiceRow(e.key, e.value)),
            const SizedBox(height: 16),
            _buildSummary(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Package'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTile(String label, DateTime date, ValueChanged<DateTime> onPicked) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(AppFormatters.formatDate(date)),
      ),
    );
  }

  Widget _buildServiceRow(int index, PackageService s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.pathLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Normal: ${AppFormatters.formatCurrency(s.normalPrice)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: _formatNumber(s.packageServiceAmount),
              decoration: const InputDecoration(labelText: 'Pkg amt', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (v) {
                final amount = double.tryParse(v) ?? 0;
                setState(() {
                  _services[index] = PackageService(
                    id: s.id,
                    packageId: s.packageId,
                    serviceId: s.serviceId,
                    categoryId: s.categoryId,
                    serviceTypeId: s.serviceTypeId,
                    categoryNameSnapshot: s.categoryNameSnapshot,
                    serviceTypeNameSnapshot: s.serviceTypeNameSnapshot,
                    serviceNameSnapshot: s.serviceNameSnapshot,
                    normalPrice: s.normalPrice,
                    packageServiceAmount: amount,
                    quantity: s.quantity,
                    createdDate: s.createdDate,
                  );
                });
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
            onPressed: () => setState(() => _services.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow('Actual Total', _normalTotal),
          _summaryRow('Package Price', _packagePrice),
          _summaryRow('Package Discount', _discount, color: AppColors.success),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Text(AppFormatters.formatCurrency(value),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }

  Future<void> _addService() async {
    final catProvider = context.read<CategoryProvider>();
    final svcProvider = context.read<ServiceProvider>();
    final cats = catProvider.activeCategories;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a service category first')));
      return;
    }
    int? selectedCategoryId = cats.first.id;
    int? selectedTypeId;
    Service? selectedService;
    List<ServiceType> types = [];
    List<Service> services = [];
    final amountCtrl = TextEditingController();

    Future<void> reload(void Function(void Function()) setDialogState, int categoryId) async {
      types = await catProvider.getServiceTypesForCategory(categoryId);
      services = await svcProvider.getServicesForCategory(categoryId, onlyDirect: true);
      setDialogState(() {});
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (services.isEmpty && types.isEmpty && selectedCategoryId != null) {
            reload(setDialogState, selectedCategoryId!);
          }
          return AlertDialog(
            title: const Text('Add Service to Package'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: cats.map((c) => DropdownMenuItem(value: c.id!, child: Text(c.name))).toList(),
                    onChanged: (v) {
                      selectedCategoryId = v;
                      selectedTypeId = null;
                      selectedService = null;
                      types = [];
                      services = [];
                      if (v != null) reload(setDialogState, v);
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  if (types.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      initialValue: selectedTypeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Service Type'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('None')),
                        ...types.map((t) => DropdownMenuItem<int?>(value: t.id, child: Text(t.name))),
                      ],
                      onChanged: (v) async {
                        selectedTypeId = v;
                        selectedService = null;
                        services = await svcProvider.getServicesForCategory(
                          selectedCategoryId!,
                          serviceTypeId: v,
                          onlyDirect: v == null,
                        );
                        setDialogState(() {});
                      },
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Service>(
                    initialValue: selectedService,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Service *'),
                    items: services
                        .map((s) => DropdownMenuItem(value: s, child: Text('${s.name} (${AppFormatters.formatCurrency(s.defaultPrice)})')))
                        .toList(),
                    onChanged: (v) {
                      selectedService = v;
                      amountCtrl.text = v != null ? _formatNumber(v.defaultPrice) : '';
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Package Service Amount (₹) *', prefixText: '₹ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final svc = selectedService;
                  if (svc == null) return;
                  final amount = double.tryParse(amountCtrl.text) ?? svc.defaultPrice;
                  setState(() {
                    _services.add(PackageService(
                      packageId: _existing?.id ?? 0,
                      serviceId: svc.id,
                      categoryId: svc.categoryId,
                      serviceTypeId: svc.serviceTypeId,
                      categoryNameSnapshot: svc.categoryName ?? '',
                      serviceTypeNameSnapshot: svc.serviceTypeName,
                      serviceNameSnapshot: svc.name,
                      normalPrice: svc.defaultPrice,
                      packageServiceAmount: amount,
                    ));
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one service to the package')));
      return;
    }
    if (_expiryDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expiry date must be on/after the start date')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final package = Package(
        id: _existing?.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        packagePrice: double.parse(_priceCtrl.text),
        startDate: _dateOnly(_startDate),
        expiryDate: _dateOnly(_expiryDate),
        isActive: _isActive,
        createdDate: _existing?.createdDate ?? now,
        services: _services,
      );
      if (_isEditing) {
        await context.read<PackageProvider>().updatePackage(package);
      } else {
        await context.read<PackageProvider>().addPackage(package);
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save package: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
