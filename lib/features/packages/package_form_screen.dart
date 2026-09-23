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

  /// Collapse/expand state for the service picker sections (favorites + per
  /// category), keyed the same way as the New Visit service picker.
  final Set<String> _collapsedSections = {};

  bool get _isEditing => widget.packageId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<CategoryProvider>().loadCategories();
    await context.read<ServiceProvider>().loadServices();
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
            const Text('Package Services',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Tap a service below to add it to this package.',
              style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 12),
            _buildServicePicker(),
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

  Widget _buildServicePicker() {
    return Consumer2<CategoryProvider, ServiceProvider>(
      builder: (context, catProvider, svcProvider, _) {
        final categories = catProvider.activeCategories;
        final hasAnyService = svcProvider.allServices.any((s) => s.isActive);
        if (categories.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Please add a service category first from Settings.',
              style: TextStyle(color: AppColors.textHint)),
          );
        }
        if (!hasAnyService) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No services available yet.', style: TextStyle(color: AppColors.textHint)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFavoritesSection(svcProvider),
            for (final cat in categories) _buildCategorySection(cat, svcProvider),
          ],
        );
      },
    );
  }

  Widget _buildFavoritesSection(ServiceProvider svcProvider) {
    final favorites = svcProvider.allServices
        .where((s) => s.isActive && s.isFavorite)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (favorites.isEmpty) return const SizedBox.shrink();

    const sectionKey = '__favorites__';
    final isCollapsed = _collapsedSections.contains(sectionKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            label: 'Favorites',
            icon: Icons.star_rounded,
            color: AppColors.warning,
            background: AppColors.warningLight,
            isCollapsed: isCollapsed,
            onTap: () => _toggleSectionCollapsed(sectionKey),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 8),
            ...favorites.map(_buildServiceSelectRow),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySection(Category cat, ServiceProvider svcProvider) {
    final services = svcProvider.allServices.where((s) => s.categoryId == cat.id && s.isActive).toList();
    if (services.isEmpty) return const SizedBox.shrink();

    final sectionKey = 'cat_${cat.id}';
    final isCollapsed = _collapsedSections.contains(sectionKey);

    // Group services by service type (null = directly under the category).
    final Map<String?, List<Service>> byType = {};
    final List<String?> typeOrder = [];
    for (final s in services) {
      final key = s.serviceTypeName;
      if (!byType.containsKey(key)) {
        byType[key] = [];
        typeOrder.add(key);
      }
      byType[key]!.add(s);
    }
    for (final list in byType.values) {
      list.sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return 0;
      });
    }
    // Show untyped services first, then each named service type.
    typeOrder.sort((a, b) {
      if (a == null) return -1;
      if (b == null) return 1;
      return a.compareTo(b);
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            label: cat.name,
            icon: Icons.category_rounded,
            color: AppColors.secondary,
            background: AppColors.secondaryContainer,
            isCollapsed: isCollapsed,
            onTap: () => _toggleSectionCollapsed(sectionKey),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 8),
            for (final typeName in typeOrder) ...[
              if (typeName != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.account_tree_rounded,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(typeName,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ...byType[typeName]!.map(_buildServiceSelectRow),
            ],
          ],
        ],
      ),
    );
  }

  void _toggleSectionCollapsed(String key) {
    setState(() {
      if (!_collapsedSections.add(key)) _collapsedSections.remove(key);
    });
  }

  Widget _buildSectionHeader({
    required String label,
    required IconData icon,
    required Color color,
    required Color background,
    required bool isCollapsed,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 6),
            Icon(
              isCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSelectRow(Service svc) {
    final idx = _services.indexWhere((s) => s.serviceId == svc.id);
    final isSelected = idx >= 0;
    return _PackageServiceSelectRow(
      key: ValueKey(svc.id),
      service: svc,
      packageServiceAmount: isSelected ? _services[idx].packageServiceAmount : svc.defaultPrice,
      isSelected: isSelected,
      onToggle: () => _toggleServiceSelection(svc),
      onAmountChanged: (amount) => _updatePackageAmount(svc.id!, amount),
    );
  }

  void _toggleServiceSelection(Service svc) {
    setState(() {
      final idx = _services.indexWhere((s) => s.serviceId == svc.id);
      if (idx >= 0) {
        _services.removeAt(idx);
      } else {
        _services.add(PackageService(
          packageId: _existing?.id ?? 0,
          serviceId: svc.id,
          categoryId: svc.categoryId,
          serviceTypeId: svc.serviceTypeId,
          categoryNameSnapshot: svc.categoryName ?? '',
          serviceTypeNameSnapshot: svc.serviceTypeName,
          serviceNameSnapshot: svc.name,
          normalPrice: svc.defaultPrice,
          packageServiceAmount: svc.defaultPrice,
        ));
      }
    });
  }

  void _updatePackageAmount(int serviceId, double amount) {
    final idx = _services.indexWhere((s) => s.serviceId == serviceId);
    if (idx < 0) return;
    final s = _services[idx];
    setState(() {
      _services[idx] = PackageService(
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

/// Tap-to-select service row for the package builder, styled the same way
/// as the New Visit "Add Services" picker: an unselected row shows the
/// service's default price; tapping it adds the service to the package with
/// an editable package amount field (defaulting to the service's normal
/// price), and tapping again removes it.
class _PackageServiceSelectRow extends StatefulWidget {
  final Service service;
  final double packageServiceAmount;
  final bool isSelected;
  final VoidCallback onToggle;
  final ValueChanged<double> onAmountChanged;

  const _PackageServiceSelectRow({
    super.key,
    required this.service,
    required this.packageServiceAmount,
    required this.isSelected,
    required this.onToggle,
    required this.onAmountChanged,
  });

  @override
  State<_PackageServiceSelectRow> createState() => _PackageServiceSelectRowState();
}

class _PackageServiceSelectRowState extends State<_PackageServiceSelectRow> {
  late TextEditingController _amountCtrl;

  String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.isSelected
            ? _formatNumber(widget.packageServiceAmount)
            : _formatNumber(widget.service.defaultPrice));
  }

  @override
  void didUpdateWidget(covariant _PackageServiceSelectRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelected) {
      _amountCtrl.text = _formatNumber(widget.service.defaultPrice);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected ? AppColors.primaryContainer : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isSelected ? AppColors.primary : AppColors.divider,
            width: widget.isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.isSelected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isSelected ? AppColors.primary : AppColors.textHint,
                  width: 2,
                ),
              ),
              child: widget.isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.service.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.normal,
                  color: widget.isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                )),
            ),
            if (widget.isSelected) ...[
              SizedBox(
                width: 90,
                height: 32,
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => widget.onAmountChanged(double.tryParse(v) ?? 0),
                  onTap: () {},
                ),
              ),
            ] else
              Text(AppFormatters.formatCurrency(widget.service.defaultPrice),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
