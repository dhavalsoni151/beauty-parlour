import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/providers/category_provider.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/visit_models.dart';
import '../../core/models/appointment_models.dart';
import '../../core/models/package_models.dart';
import '../../core/providers/package_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';
import '../packages/package_picker_sheet.dart';

class _BillItem {
  final Service service;
  double price;
  int quantity;

  /// Set when this line was auto-added as part of a package. The service's
  /// own normal/default price is kept separately in [normalPrice] so it can
  /// be shown alongside the (possibly discounted) package [price] without
  /// ever overwriting the service master's default price.
  final int? packageId;
  final double? normalPrice;
  bool get isPackageItem => packageId != null;

  _BillItem({
    required this.service,
    required this.price,
    this.quantity = 1,
    this.packageId,
    this.normalPrice,
  });

  double get total => price * quantity;
}

class NewVisitScreen extends StatefulWidget {
  final int? preselectedCustomerId;
  final int? fromAppointmentId;
  final int? editVisitId;
  const NewVisitScreen({
    super.key,
    this.preselectedCustomerId,
    this.fromAppointmentId,
    this.editVisitId,
  });

  @override
  State<NewVisitScreen> createState() => _NewVisitScreenState();
}

class _NewVisitScreenState extends State<NewVisitScreen> {
  // Step 0=customer, 1=services, 2=payment
  int _step = 0;

  // Collapse/expand state for the services picker (favorites + per-category
  // sections). Empty set = everything expanded by default.
  final Set<String> _collapsedSections = {};

  Customer? _selectedCustomer;
  final List<_BillItem> _billItems = [];

  /// The package currently applied to this visit (its bundled services are
  /// mirrored into [_billItems] with `packageId` set). Only one package can
  /// be active per visit; additional individual services can still be added
  /// alongside it.
  Package? _selectedPackage;

  DiscountType _discountType = DiscountType.fixed;
  double _discountValue = 0;
  final _discountCtrl = TextEditingController();

  PaymentMethod _paymentMethod = PaymentMethod.cash;
  double _paidAmount = 0;
  final _paidCtrl = TextEditingController();

  bool _isSaving = false;
  int? _savedVisitId;

  // Set when this screen was opened from Appointments → "Mark Completed" so
  // the completed visit can be linked back to its source appointment.
  Appointment? _sourceAppointment;

  // Set when editing an existing visit (from the visit detail screen), so
  // saving updates it in place instead of creating a new one.
  Visit? _editingVisit;
  bool get _isEditing => widget.editVisitId != null;

  // Visit date — defaults to today but any past/future date can be chosen
  DateTime _visitDate = DateTime.now();

  // Customer search
  List<Customer> _customerSearchResults = [];
  final _customerQueryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CategoryProvider>().loadCategories();
      await context.read<ServiceProvider>().loadServices();
      await context.read<CustomerProvider>().loadCustomers();
      if (widget.editVisitId != null) {
        await _prefillForEdit(widget.editVisitId!);
      } else if (widget.fromAppointmentId != null) {
        await _prefillFromAppointment(widget.fromAppointmentId!);
      } else if (widget.preselectedCustomerId != null) {
        final c = await context.read<CustomerProvider>().getCustomer(widget.preselectedCustomerId!);
        if (c != null) {
          setState(() {
            _selectedCustomer = c;
            _step = 1;
          });
        }
      }
      // Show all customers by default so one can be picked without typing a search
      if (!mounted) return;
      final all = List<Customer>.from(context.read<CustomerProvider>().allCustomers)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() => _customerSearchResults = all);
    });
  }

  /// Loads an existing visit for editing, pre-filling the customer, services,
  /// discount and previously paid amount. Payments already on file are kept
  /// as-is; only the bill (services/discount/notes) and the pending balance
  /// they leave behind can be changed.
  Future<void> _prefillForEdit(int visitId) async {
    final visit = await context.read<VisitProvider>().getVisit(visitId);
    if (visit == null || !mounted) return;
    final customer = await context.read<CustomerProvider>().getCustomer(visit.customerId);
    if (!mounted) return;

    setState(() {
      _editingVisit = visit;
      _selectedCustomer = customer;
      _visitDate = DateTime.tryParse(visit.visitDate) ?? DateTime.now();
      _discountType = visit.discountType;
      _discountValue = visit.discountValue;
      _discountCtrl.text = visit.discountValue == 0 ? '' : _formatNumber(visit.discountValue);
      _paidAmount = visit.totalPaid;
      _paidCtrl.text = visit.totalPaid == 0 ? '' : _formatNumber(visit.totalPaid);
      _billItems
        ..clear()
        ..addAll(visit.services.map((vs) => _BillItem(
              service: Service(
                id: vs.serviceId,
                categoryId: vs.categoryId ?? 0,
                serviceTypeId: vs.serviceTypeId,
                name: vs.serviceNameSnapshot,
                defaultPrice: vs.price,
                createdDate: DateTime.now().toIso8601String(),
                categoryName: vs.categoryNameSnapshot,
                serviceTypeName: vs.serviceTypeNameSnapshot,
              ),
              price: vs.price,
              quantity: vs.quantity,
              packageId: vs.isPackageItem ? vs.packageId : null,
              normalPrice: vs.isPackageItem ? (vs.normalPriceSnapshot ?? vs.price) : null,
            )));
      _selectedPackage = _packageSnapshotFromVisit(visit);
      _step = 1;
    });
  }

  /// Reconstructs a lightweight, read-only [Package] from a visit's own
  /// historical snapshot fields (never from the live `packages` table), so
  /// editing an old visit keeps displaying/using exactly what was charged at
  /// the time — even if the package was later edited, deactivated or deleted.
  Package? _packageSnapshotFromVisit(Visit visit) {
    if (!visit.hasPackage) return null;
    final packageItems = _billItems.where((b) => b.packageId == visit.packageId);
    return Package(
      id: visit.packageId,
      name: visit.packageNameSnapshot ?? 'Package',
      packagePrice: visit.packagePrice ?? 0,
      startDate: '',
      expiryDate: '',
      createdDate: visit.createdDate,
      services: packageItems
          .map((b) => PackageService(
                packageId: visit.packageId!,
                serviceId: b.service.id,
                categoryId: b.service.categoryId,
                serviceTypeId: b.service.serviceTypeId,
                categoryNameSnapshot: b.service.categoryName ?? '',
                serviceTypeNameSnapshot: b.service.serviceTypeName,
                serviceNameSnapshot: b.service.name,
                normalPrice: b.normalPrice ?? b.price,
                packageServiceAmount: b.price,
                quantity: b.quantity,
              ))
          .toList(),
    );
  }

  String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  /// Loads the source appointment and pre-fills the customer + every service
  /// booked on it, so completing an appointment reviews/edits the same data
  /// instead of silently creating a visit behind the scenes.
  Future<void> _prefillFromAppointment(int appointmentId) async {
    final appointmentProvider = context.read<AppointmentProvider>();
    final appointment = await appointmentProvider.getAppointment(appointmentId);
    if (appointment == null || !mounted) return;

    final customer = await context.read<CustomerProvider>().getCustomer(appointment.customerId);
    final visitServices = await appointmentProvider.buildPrefillServices(appointment);
    if (!mounted) return;

    setState(() {
      _sourceAppointment = appointment;
      _selectedCustomer = customer;
      _visitDate = DateTime.tryParse(appointment.appointmentDate) ?? DateTime.now();
      _billItems
        ..clear()
        ..addAll(visitServices.map((vs) => _BillItem(
              service: Service(
                id: vs.serviceId,
                categoryId: vs.categoryId ?? 0,
                serviceTypeId: vs.serviceTypeId,
                name: vs.serviceNameSnapshot,
                defaultPrice: vs.price,
                createdDate: DateTime.now().toIso8601String(),
                categoryName: vs.categoryNameSnapshot,
                serviceTypeName: vs.serviceTypeNameSnapshot,
              ),
              price: vs.price,
              quantity: vs.quantity,
              packageId: vs.isPackageItem ? vs.packageId : null,
              normalPrice: vs.isPackageItem ? (vs.normalPriceSnapshot ?? vs.price) : null,
            )));
      _selectedPackage = appointment.hasPackage
          ? Package(
              id: appointment.packageId,
              name: appointment.packageNameSnapshot ?? 'Package',
              packagePrice: appointment.packagePrice ?? 0,
              startDate: '',
              expiryDate: '',
              createdDate: DateTime.now().toIso8601String(),
              services: _billItems
                  .where((b) => b.packageId == appointment.packageId)
                  .map((b) => PackageService(
                        packageId: appointment.packageId!,
                        serviceId: b.service.id,
                        categoryId: b.service.categoryId,
                        serviceTypeId: b.service.serviceTypeId,
                        categoryNameSnapshot: b.service.categoryName ?? '',
                        serviceTypeNameSnapshot: b.service.serviceTypeName,
                        serviceNameSnapshot: b.service.name,
                        normalPrice: b.normalPrice ?? b.price,
                        packageServiceAmount: b.price,
                        quantity: b.quantity,
                      ))
                  .toList(),
            )
          : null;
      _step = _selectedCustomer != null ? 1 : 0;
    });
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _customerQueryCtrl.dispose();
    super.dispose();
  }

  // ─── Calculations ─────────────────────────────────────────────

  double get _subtotal => _billItems.fold(0, (s, i) => s + i.total);

  double get _discountAmount {
    if (_discountValue <= 0) return 0;
    if (_discountType == DiscountType.percent) {
      return (_discountValue / 100) * _subtotal;
    }
    return _discountValue.clamp(0, _subtotal);
  }

  double get _finalTotal => (_subtotal - _discountAmount).clamp(0, double.infinity);

  double get _pendingAmount => (_finalTotal - _paidAmount).clamp(0, double.infinity);

  PaymentStatus get _paymentStatus {
    if (_paidAmount >= _finalTotal) return PaymentStatus.paid;
    if (_paidAmount > 0) return PaymentStatus.partiallyPaid;
    return PaymentStatus.pending;
  }

  // ─── Step 1: Customer Selection ───────────────────────────────

  Widget _buildCustomerStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Select Customer', Icons.person_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _customerQueryCtrl,
            onChanged: _searchCustomers,
            decoration: InputDecoration(
              hintText: 'Search by name or phone...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_customerQueryCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, color: AppColors.textHint, size: 18),
                      onPressed: () {
                        _customerQueryCtrl.clear();
                        _searchCustomers('');
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        // New customer button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: _createNewCustomer,
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('New Customer'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _customerQueryCtrl.text.isEmpty
                ? '${_customerSearchResults.length} customers · tap to select'
                : '${_customerSearchResults.length} results',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textHint),
          ),
        ),
        Expanded(
          child: _customerSearchResults.isEmpty
              ? const Center(child: Text('No customers found', style: TextStyle(color: AppColors.textHint)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: _customerSearchResults.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _customerSearchResults[i];
                    final initials = c.name.trim().split(' ')
                        .map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
                    final avatarColor = AppColors.chartColors[c.name.hashCode.abs() % AppColors.chartColors.length];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() {
                          _selectedCustomer = c;
                          _step = 1;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.divider),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: avatarColor.withOpacity(0.15),
                                child: Text(initials,
                                  style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700, fontSize: 14)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                    if (c.phone != null && c.phone!.isNotEmpty)
                                      Text(c.phone!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _searchCustomers(String q) {
    setState(() {
      final all = List<Customer>.from(context.read<CustomerProvider>().allCustomers)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (q.isEmpty) {
        _customerSearchResults = all;
      } else {
        final lower = q.toLowerCase();
        _customerSearchResults = all.where((c) =>
          c.name.toLowerCase().contains(lower) || (c.phone?.contains(q) ?? false)
        ).toList();
      }
    });
  }

  Future<void> _createNewCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Customer'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *'),
                autofocus: true,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (Optional)'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final now = DateTime.now().toIso8601String();
              final customer = Customer(
                name: nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                createdDate: now,
              );
              final id = await context.read<CustomerProvider>().addCustomer(customer);
              final saved = customer.copyWith(id: id);
              Navigator.pop(ctx, saved);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created != null) {
      setState(() {
        _selectedCustomer = created;
        _step = 1;
      });
    }
  }

  // ─── Step 2: Service Selection ────────────────────────────────

  Widget _buildServicesStep() {
    return Consumer2<CategoryProvider, ServiceProvider>(
      builder: (context, catProvider, svcProvider, _) {
        final categories = catProvider.activeCategories;
        final hasAnyService = svcProvider.allServices.any((s) => s.isActive);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHeader(
              'Add Services',
              Icons.spa_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.accent),
                    tooltip: 'Add Package',
                    onPressed: _addPackage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                    tooltip: 'Add New Service',
                    onPressed: () => _showAddServiceDialog(catProvider, svcProvider),
                  ),
                ],
              ),
            ),
            // Customer chip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(_selectedCustomer!.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() { _step = 0; _selectedCustomer = null; }),
                    child: const Text('Change', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !hasAnyService
                  ? EmptyState(
                      title: 'No Services Yet',
                      subtitle: 'Add a service to start billing this customer',
                      icon: Icons.spa_rounded,
                      actionLabel: 'Add Service',
                      onAction: () => _showAddServiceDialog(catProvider, svcProvider),
                    )
                  : CustomScrollView(
                      slivers: [
                        // Favorites first, so frequently-used services are
                        // always one tap away regardless of category.
                        _buildFavoritesSection(svcProvider),
                        // Category tabs with services
                        for (final cat in categories)
                          _buildCategorySection(cat, svcProvider),
                        // Bill summary at bottom
                        SliverToBoxAdapter(child: _buildBillSummary()),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddServiceDialog(CategoryProvider catProvider, ServiceProvider svcProvider) async {
    final cats = catProvider.activeCategories;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a service category first from Settings')));
      return;
    }

    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? selectedCategoryId = cats.first.id;
    int? selectedTypeId;
    List<ServiceType> types = selectedCategoryId != null
        ? await catProvider.getServiceTypesForCategory(selectedCategoryId)
        : [];
    final now = DateTime.now().toIso8601String();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Load service types (sub-categories) for the currently selected
          // category so the picker always reflects the latest category /
          // sub-category structure managed from Settings.
          Future<void> reloadTypes(int categoryId) async {
            final loaded = await catProvider.getServiceTypesForCategory(categoryId);
            setDialogState(() {
              types = loaded;
              if (selectedTypeId != null && !types.any((t) => t.id == selectedTypeId)) {
                selectedTypeId = null;
              }
            });
          }

          return AlertDialog(
            title: const Text('New Service'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Category *'),
                      items: cats.map((c) => DropdownMenuItem<int>(value: c.id!, child: Text(c.name))).toList(),
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
                      initialValue: selectedTypeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Service Type (Optional)'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('None (directly under category)')),
                        ...types.map((t) => DropdownMenuItem<int?>(value: t.id, child: Text(t.name))),
                      ],
                      onChanged: (v) => setDialogState(() => selectedTypeId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Service Name *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(labelText: 'Default Price (₹) *', prefixText: '₹ '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final svc = Service(
                    categoryId: selectedCategoryId!,
                    serviceTypeId: selectedTypeId,
                    name: nameCtrl.text.trim(),
                    defaultPrice: double.parse(priceCtrl.text),
                    createdDate: now,
                  );
                  await svcProvider.addService(svc);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _buildFavoritesSection(ServiceProvider svcProvider) {
    final favorites = svcProvider.allServices
        .where((s) => s.isActive && s.isFavorite)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (favorites.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    const sectionKey = '__favorites__';
    final isCollapsed = _collapsedSections.contains(sectionKey);

    Widget serviceRow(Service svc) => _ServiceSelectRow(
          service: svc,
          billItem: _billItems.firstWhere((b) => b.service.id == svc.id,
              orElse: () => _BillItem(service: svc, price: svc.defaultPrice)),
          isSelected: _billItems.any((b) => b.service.id == svc.id),
          onToggle: () => _toggleService(svc),
          onPriceChanged: (v) {
            final idx = _billItems.indexWhere((b) => b.service.id == svc.id);
            if (idx >= 0) setState(() => _billItems[idx].price = v);
          },
          onQtyChanged: (v) {
            final idx = _billItems.indexWhere((b) => b.service.id == svc.id);
            if (idx >= 0) setState(() => _billItems[idx].quantity = v);
          },
        );

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
              ...favorites.map(serviceRow),
            ],
          ],
        ),
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

  SliverToBoxAdapter _buildCategorySection(Category cat, ServiceProvider svcProvider) {
    final services = svcProvider.allServices.where((s) => s.categoryId == cat.id && s.isActive).toList();
    if (services.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final sectionKey = 'cat_${cat.id}';
    final isCollapsed = _collapsedSections.contains(sectionKey);

    // Group services by service type (null = directly under the category).
    // Preserves the DAO ordering (display_order) within each group, with
    // favorites bubbled to the top of their group.
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

    Widget serviceRow(Service svc) => _ServiceSelectRow(
          service: svc,
          billItem: _billItems.firstWhere((b) => b.service.id == svc.id,
              orElse: () => _BillItem(service: svc, price: svc.defaultPrice)),
          isSelected: _billItems.any((b) => b.service.id == svc.id),
          onToggle: () => _toggleService(svc),
          onPriceChanged: (v) {
            final idx = _billItems.indexWhere((b) => b.service.id == svc.id);
            if (idx >= 0) setState(() => _billItems[idx].price = v);
          },
          onQtyChanged: (v) {
            final idx = _billItems.indexWhere((b) => b.service.id == svc.id);
            if (idx >= 0) setState(() => _billItems[idx].quantity = v);
          },
        );

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                ...byType[typeName]!.map(serviceRow),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _toggleService(Service svc) {
    setState(() {
      final idx = _billItems.indexWhere((b) => b.service.id == svc.id);
      if (idx >= 0) {
        if (_billItems[idx].isPackageItem) {
          _removePackage();
        } else {
          _billItems.removeAt(idx);
        }
      } else {
        _billItems.add(_BillItem(service: svc, price: svc.defaultPrice));
      }
    });
  }

  /// Removes all services that belong to the currently-selected package and
  /// clears the package selection. Does NOT touch the service master data.
  void _removePackage() {
    _billItems.removeWhere((b) => b.isPackageItem);
    _selectedPackage = null;
  }

  /// Opens the package picker for the current visit date, re-validates the
  /// chosen package (business rule: validate again on every use), then
  /// replaces any previously-selected package with the newly chosen one and
  /// auto-adds its services to the bill.
  Future<void> _addPackage() async {
    final dateStr = _visitDate.toIso8601String();
    final picked = await showPackagePickerSheet(context, dateStr);
    if (picked == null || !mounted) return;

    final validation =
        await context.read<PackageProvider>().validate(picked.id!, dateStr);
    if (!validation.isValid || validation.package == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation.message ?? 'This package is not valid for the selected date.')),
      );
      return;
    }
    final validated = validation.package!;

    setState(() {
      _removePackage();
      _selectedPackage = validated;
      for (final ps in validated.services) {
        _billItems.add(_BillItem(
          service: Service(
            id: ps.serviceId,
            categoryId: ps.categoryId ?? 0,
            serviceTypeId: ps.serviceTypeId,
            name: ps.serviceNameSnapshot,
            defaultPrice: ps.normalPrice,
            createdDate: DateTime.now().toIso8601String(),
            categoryName: ps.categoryNameSnapshot,
            serviceTypeName: ps.serviceTypeNameSnapshot,
          ),
          price: ps.packageServiceAmount,
          quantity: ps.quantity,
          packageId: validated.id,
          normalPrice: ps.normalPrice,
        ));
      }
    });
  }

  Widget _buildPackageSummaryBlock() {
    final pkg = _selectedPackage!;
    final normalTotal = pkg.services.fold(0.0, (sum, ps) => sum + ps.normalPrice * ps.quantity);
    final packageAmount = _billItems
        .where((b) => b.packageId == pkg.id)
        .fold(0.0, (sum, b) => sum + b.total);
    final discount = normalTotal - packageAmount;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Expanded(child: Text(pkg.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
                tooltip: 'Remove Package',
                onPressed: () => setState(_removePackage),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _packageSummaryRow('Actual Service Amount', normalTotal, strike: true),
          _packageSummaryRow('Package Price', packageAmount, color: AppColors.primary, bold: true),
          _packageSummaryRow('Package Discount', discount, color: AppColors.success),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _packageSummaryRow(String label, double value, {bool strike = false, Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          Text(AppFormatters.formatCurrency(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? AppColors.textPrimary,
              decoration: strike ? TextDecoration.lineThrough : null,
            )),
        ],
      ),
    );
  }

  Widget _buildBillSummary() {
    if (_billItems.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bill Summary',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (_selectedPackage != null) _buildPackageSummaryBlock(),
          ..._billItems.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(child: Text(
                  item.isPackageItem ? '${item.service.name} (Package)' : item.service.name,
                  style: TextStyle(fontSize: 13,
                    color: item.isPackageItem ? AppColors.accent : AppColors.textSecondary))),
                if (item.quantity > 1) Text('×${item.quantity} ', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                Text(AppFormatters.formatCurrency(item.total),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          )),
          const Divider(height: 16),
          // Discount row
          Row(
            children: [
              const Text('Discount', style: TextStyle(fontSize: 13, color: AppColors.success)),
              const SizedBox(width: 8),
              _DiscountTypeToggle(
                type: _discountType,
                onChanged: (t) => setState(() {
                  _discountType = t;
                  _discountCtrl.clear();
                  _discountValue = 0;
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      hintText: _discountType == DiscountType.percent ? '0%' : '₹0',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0;
                      setState(() => _discountValue = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('- ${AppFormatters.formatCurrency(_discountAmount)}',
                style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Expanded(child: Text('TOTAL',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              Text(AppFormatters.formatCurrency(_finalTotal),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _billItems.isEmpty ? null : () => setState(() => _step = 2),
              child: const Text('Proceed to Payment →'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 3: Payment ──────────────────────────────────────────

  Widget _buildPaymentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Payment', Icons.payments_rounded),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildVisitDateSelector(),
                const SizedBox(height: 16),
                // Bill recap
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        const Expanded(child: Text('Customer', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                        Text(_selectedCustomer!.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Expanded(child: Text('Services', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                        Text('${_billItems.length} services',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 13)),
                      ]),
                      if (_discountAmount > 0) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Expanded(child: Text('Discount', style: TextStyle(color: AppColors.success, fontSize: 13))),
                          Text('- ${AppFormatters.formatCurrency(_discountAmount)}',
                            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ],
                      const Divider(height: 16),
                      Row(children: [
                        const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
                        Text(AppFormatters.formatCurrency(_finalTotal),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Payment method
                Align(alignment: Alignment.centerLeft,
                  child: const Text('Payment Method', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                const SizedBox(height: 10),
                _PaymentMethodSelector(
                  selected: _paymentMethod,
                  onChanged: _isEditing ? null : (m) => setState(() => _paymentMethod = m),
                ),
                const SizedBox(height: 20),

                // Scanner (QR) option — shown when the customer wants to pay
                // by scanning the parlour's UPI/payment QR code.
                if (_paymentMethod == PaymentMethod.upi) _buildScannerCard(),

                // Paid amount
                const Align(alignment: Alignment.centerLeft,
                  child: Text('Amount Paid', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                const SizedBox(height: 10),
                if (_isEditing)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Amount paid (${AppFormatters.formatCurrency(_paidAmount)}) is unchanged here — use "Receive" on the bill to record new payments.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  )
                else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _paidCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          hintText: '0',
                          labelText: 'Amount Paid',
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          setState(() => _paidAmount = val.clamp(0, _finalTotal));
                          if (val > _finalTotal) {
                            _paidCtrl.text = _finalTotal.toStringAsFixed(0);
                            _paidCtrl.selection = TextSelection.collapsed(offset: _paidCtrl.text.length);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _paidAmount = _finalTotal);
                        _paidCtrl.text = _finalTotal.toStringAsFixed(0);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: const Text('Full'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Pending info
                if (_finalTotal > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _pendingAmount > 0 ? AppColors.errorLight : AppColors.successLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _pendingAmount > 0 ? Icons.pending_actions_rounded : Icons.check_circle_rounded,
                          color: _pendingAmount > 0 ? AppColors.error : AppColors.success,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _paymentStatus.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _pendingAmount > 0 ? AppColors.error : AppColors.success,
                                ),
                              ),
                              if (_pendingAmount > 0)
                                Text('Pending: ${AppFormatters.formatCurrency(_pendingAmount)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _savedVisitId != null) ? null : _saveVisit,
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_savedVisitId != null ? 'Bill Saved' : (_isEditing ? 'Update Bill' : 'Save Bill'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickVisitDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate.isAfter(today) ? today : _visitDate,
      firstDate: DateTime(now.year - 10),
      lastDate: today,
      helpText: 'Select Visit Date',
    );
    if (picked != null) setState(() => _visitDate = picked);
  }

  /// Shows the parlour's uploaded UPI/payment scanner (QR) image, if any,
  /// so the customer can scan it to complete a UPI payment.
  Widget _buildScannerCard() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final path = settings.scannerImagePath;
        final hasImage = path != null && File(path).existsSync();
        if (!hasImage) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Scan to Pay',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(path), height: 200, fit: BoxFit.contain),
                ),
                const SizedBox(height: 8),
                const Text('Ask the customer to scan this code to complete the payment.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisitDateSelector() {
    return InkWell(
      onTap: _savedVisitId != null ? null : _pickVisitDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            const Text('Visit Date',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const Spacer(),
            Text(AppFormatters.formatDate(_visitDate),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_calendar_rounded, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVisit() async {
    // Guard against duplicate visits from repeated taps or going back after save
    if (_isSaving || _savedVisitId != null) return;
    if (!_isEditing) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedDay = DateTime(_visitDate.year, _visitDate.month, _visitDate.day);
      if (selectedDay.isAfter(today)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visit date cannot be in the future')),
        );
        return;
      }
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final visitDateTime = DateTime(
        _visitDate.year, _visitDate.month, _visitDate.day,
        now.hour, now.minute, now.second,
      );
      final dateStr = _isEditing ? _editingVisit!.visitDate : visitDateTime.toIso8601String();
      final createdStr = _isEditing ? _editingVisit!.createdDate : now.toIso8601String();
      final paid = _paidAmount.clamp(0.0, _finalTotal);
      final pending = (_finalTotal - paid).clamp(0.0, double.infinity);

      // Re-validate the package right before it is actually processed/saved —
      // it may have been selected earlier while valid, but the visit date or
      // the package itself (active flag, validity window) could have changed
      // since then. This never touches service master prices.
      double? packageNormalTotal;
      double? packagePrice;
      double? packageDiscount;
      String? packageNameSnapshot;
      if (_selectedPackage != null) {
        Package? validated = _selectedPackage;
        // Only re-validate against the *current* package master when creating
        // a brand-new visit. Editing an existing (already-historical) visit
        // must keep using the previously-selected/prefilled snapshot so that
        // later package changes (or expiry) never alter past transactions.
        if (!_isEditing) {
          final validation = await context
              .read<PackageProvider>()
              .validate(_selectedPackage!.id!, dateStr);
          if (!validation.isValid || validation.package == null) {
            setState(() => _isSaving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(validation.message ??
                    'This package is no longer valid for the selected date.'),
              ));
            }
            return;
          }
          validated = validation.package!;
        }
        packageNormalTotal = validated!.services
            .fold<double>(0.0, (sum, ps) => sum + ps.normalPrice * ps.quantity);
        packagePrice = _billItems
            .where((b) => b.packageId == validated!.id)
            .fold<double>(0.0, (sum, b) => sum + b.total);
        packageDiscount = packageNormalTotal - packagePrice;
        packageNameSnapshot = validated.name;
      }

      final visit = Visit(
        id: _isEditing ? _editingVisit!.id : null,
        customerId: _selectedCustomer!.id!,
        visitDate: dateStr,
        subtotal: _subtotal,
        discountType: _discountType,
        discountValue: _discountValue,
        discountAmount: _discountAmount,
        finalTotal: _finalTotal,
        totalPaid: paid,
        pendingAmount: pending,
        paymentStatus: _paymentStatus,
        createdDate: createdStr,
        packageId: _selectedPackage?.id,
        packageNameSnapshot: packageNameSnapshot,
        packageNormalTotal: packageNormalTotal,
        packagePrice: packagePrice,
        packageDiscount: packageDiscount,
      );

      final visitServices = _billItems.map((item) => VisitService(
        visitId: 0,
        serviceId: item.service.id,
        categoryId: item.service.categoryId,
        serviceTypeId: item.service.serviceTypeId,
        serviceNameSnapshot: item.service.name,
        categoryNameSnapshot: item.service.categoryName ?? '',
        serviceTypeNameSnapshot: item.service.serviceTypeName,
        price: item.price,
        quantity: item.quantity,
        total: item.total,
        createdAt: createdStr,
        isPackageItem: item.isPackageItem,
        packageId: item.packageId,
        normalPriceSnapshot: item.normalPrice,
      )).toList();


      int visitId;
      if (_isEditing) {
        visitId = _editingVisit!.id!;
        await context.read<VisitProvider>().updateVisit(visit, visitServices);
      } else {
        final payments = paid > 0 ? [
          Payment(
            visitId: 0,
            paymentDate: dateStr,
            amount: paid,
            paymentMethod: _paymentMethod,
          )
        ] : <Payment>[];
        visitId = await context.read<VisitProvider>().saveVisit(visit, visitServices, payments);
        if (_sourceAppointment?.id != null) {
          await context.read<AppointmentProvider>().completeWithVisit(_sourceAppointment!.id!, visitId);
        }
      }
      await context.read<DashboardProvider>().loadDashboard();

      if (!mounted) return;
      if (_isEditing) {
        setState(() { _savedVisitId = visitId; _isSaving = false; });
        context.pop(true);
        return;
      }
      setState(() { _savedVisitId = visitId; _isSaving = false; });
      _showSuccessDialog(visitId, paid, pending);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving visit: $e')));
      }
    }
  }

  void _showSuccessDialog(int visitId, double paid, double pending) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
              ),
              const SizedBox(height: 16),
              const Text('Visit Saved!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              _SummaryRow('Customer', _selectedCustomer!.name),
              _SummaryRow('Total', AppFormatters.formatCurrency(_finalTotal)),
              _SummaryRow('Paid', AppFormatters.formatCurrency(paid)),
              if (pending > 0)
                _SummaryRow('Pending', AppFormatters.formatCurrency(pending), valueColor: AppColors.error),
              const SizedBox(height: 4),
              PaymentStatusBadge(status: _paymentStatus),
              const SizedBox(height: 20),
              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pushReplacement('/new-visit');
                  },
                  child: const Text('New Visit'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _shareVisitSummary,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share on WhatsApp'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.pushReplacement('/visit/$visitId');
                      },
                      child: const Text('View Bill'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.pushReplacement('/customer/${_selectedCustomer!.id}/profile');
                      },
                      child: const Text('Customer'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _leaveToCustomers();
                },
                child: const Text('Done', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildVisitShareMessage() {
    final customerName = _selectedCustomer?.name.trim();
    final parlourName = context.read<SettingsProvider>().parlourName.trim();
    final opening = (customerName?.isNotEmpty ?? false)
        ? 'Hi $customerName, thank you for visiting ${parlourName.isNotEmpty ? parlourName : 'us'}!'
        : 'Thank you for visiting ${parlourName.isNotEmpty ? parlourName : 'us'}!';

    final lines = _billItems.map((item) {
      final quantitySuffix = item.quantity > 1 ? ' ×${item.quantity}' : '';
      return '• ${item.service.name}$quantitySuffix — ${AppFormatters.formatCurrency(item.total)}';
    });

    final buffer = StringBuffer()
      ..writeln(opening)
      ..writeln('Your visit summary:')
      ..writeln(lines.join('\n'))
      ..writeln('Total: ${AppFormatters.formatCurrency(_finalTotal)}');

    if (_pendingAmount > 0) {
      buffer.writeln('Pending: ${AppFormatters.formatCurrency(_pendingAmount)}');
    }

    buffer.write('See you again soon!');
    return buffer.toString();
  }

  Future<void> _shareVisitSummary() async {
    if (_selectedCustomer == null || _billItems.isEmpty) return;

    try {
      await Share.share(
        _buildVisitShareMessage(),
        subject: 'Visit Summary',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share visit summary: $e')),
      );
    }
  }

  Widget _buildStepHeader(String title, IconData icon, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (trailing != null) trailing,
          const Spacer(),
          // Steps indicator
          Row(
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                width: i == _step ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.primary : AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  // After a bill is saved there is nothing left to do on this screen, so leaving
  // it always lands on the customer list instead of the (already saved) bill form.
  void _leaveToCustomers() => context.go('/customers');

  void _close() {
    if (_isEditing) {
      context.pop(_savedVisitId != null);
    } else if (_savedVisitId != null) {
      _leaveToCustomers();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _savedVisitId == null || _isEditing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isEditing) _leaveToCustomers();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Visit' : 'New Visit'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _close,
          ),
          actions: [
            if (_step > 0 && _savedVisitId == null)
              TextButton(
                onPressed: () => setState(() => _step = _step - 1),
                child: const Text('Back'),
              ),
          ],
        ),
        body: IndexedStack(
          index: _step,
          children: [
            _buildCustomerStep(),
            _selectedCustomer == null ? const SizedBox.shrink() : _buildServicesStep(),
            _selectedCustomer == null ? const SizedBox.shrink() : _buildPaymentStep(),
          ],
        ),
      ),
    );
  }
}

class _ServiceSelectRow extends StatefulWidget {
  final Service service;
  final _BillItem billItem;
  final bool isSelected;
  final VoidCallback onToggle;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<int> onQtyChanged;

  const _ServiceSelectRow({
    required this.service,
    required this.billItem,
    required this.isSelected,
    required this.onToggle,
    required this.onPriceChanged,
    required this.onQtyChanged,
  });

  @override
  State<_ServiceSelectRow> createState() => _ServiceSelectRowState();
}

class _ServiceSelectRowState extends State<_ServiceSelectRow> {
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
        text: widget.isSelected ? widget.billItem.price.toStringAsFixed(0) : widget.service.defaultPrice.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _ServiceSelectRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelected) {
      _priceCtrl.text = widget.service.defaultPrice.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
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
            // Price field (editable when selected)
            if (widget.isSelected) ...[
              SizedBox(
                width: 80,
                height: 32,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => widget.onPriceChanged(double.tryParse(v) ?? 0),
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

class _DiscountTypeToggle extends StatelessWidget {
  final DiscountType type;
  final ValueChanged<DiscountType> onChanged;

  const _DiscountTypeToggle({required this.type, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton('₹', type == DiscountType.fixed, () => onChanged(DiscountType.fixed)),
          _ToggleButton('%', type == DiscountType.percent, () => onChanged(DiscountType.percent)),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            )),
        ),
      ),
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod>? onChanged;

  const _PaymentMethodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PaymentMethodX.all.map((m) {
        final isSelected = m == selected;
        return GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
            ),
            child: Text(m.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              )),
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            )),
        ],
      ),
    );
  }
}
