import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/models/appointment_models.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/package_models.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/providers/category_provider.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/providers/package_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../packages/package_picker_sheet.dart';

class AppointmentFormScreen extends StatefulWidget {
  final int? appointmentId;

  const AppointmentFormScreen({super.key, this.appointmentId});

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  static const int _directServiceTypeValue = -1;

  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  final _serviceDao = ServiceDao();
  final _categoryDao = CategoryDao();
  final _serviceTypeDao = ServiceTypeDao();

  List<Customer> _customers = [];
  List<Category> _categories = [];
  List<ServiceType> _serviceTypes = [];
  List<Service> _services = [];

  Customer? _selectedCustomer;
  Category? _selectedCategory;
  int _selectedServiceTypeValue = _directServiceTypeValue;
  Service? _selectedService;
  final List<_AppointmentServiceEntry> _selectedServices = [];

  /// The package currently applied to this appointment (its services are
  /// mirrored into [_selectedServices] with `packageId` set). Only one
  /// package can be active per appointment; additional individual services
  /// can still be added alongside it.
  Package? _selectedPackage;
  DateTime _appointmentDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  TimeOfDay _startTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(minutes: 30)),
  );
  int? _reminderMinutesBefore = 30;
  bool _isLoading = true;
  bool _isSaving = false;
  Appointment? _existingAppointment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final customerProvider = context.read<CustomerProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    await customerProvider.loadCustomers(activeOnly: false);
    await categoryProvider.loadCategories();

    _customers = List<Customer>.from(customerProvider.allCustomers);
    _categories = List<Category>.from(categoryProvider.categories);

    if (widget.appointmentId != null) {
      final appointment =
          await context.read<AppointmentProvider>().getAppointment(widget.appointmentId!);
      if (appointment != null) {
        _existingAppointment = appointment;
        _selectedCustomer = await customerProvider.getCustomer(appointment.customerId);
        if (_selectedCustomer != null &&
            !_customers.any((c) => c.id == _selectedCustomer!.id)) {
          _customers = [..._customers, _selectedCustomer!];
        }

        if (appointment.categoryId != null) {
          _selectedCategory = await _categoryDao.get(appointment.categoryId!);
          if (_selectedCategory != null &&
              !_categories.any((c) => c.id == _selectedCategory!.id)) {
            _categories = [..._categories, _selectedCategory!];
          }
        }

        _notesController.text = appointment.notes ?? '';
        _appointmentDate = DateTime.parse(appointment.appointmentDate);
        _startTime = _parseTimeOfDay(appointment.startTime);
        _reminderMinutesBefore = appointment.reminderMinutesBefore;
      }
    }

    if (_selectedCategory != null) {
      await _loadCategoryData(_selectedCategory!.id!);
    }

    if (_existingAppointment != null) {
      final services = _existingAppointment!.services.isNotEmpty
          ? _existingAppointment!.services
          : await _legacyServiceAsList(_existingAppointment!);
      for (final s in services) {
        _selectedServices.add(_AppointmentServiceEntry(
          serviceId: s.serviceId,
          categoryId: s.categoryId,
          serviceTypeId: s.serviceTypeId,
          categoryName: s.categoryNameSnapshot,
          serviceTypeName: s.serviceTypeNameSnapshot,
          serviceName: s.serviceNameSnapshot,
          price: s.price,
          quantity: s.quantity,
          packageId: s.isPackageItem ? s.packageId : null,
          normalPrice: s.isPackageItem ? (s.normalPriceSnapshot ?? s.price) : null,
        ));
      }
      if (_existingAppointment!.hasPackage) {
        _selectedPackage = Package(
          id: _existingAppointment!.packageId,
          name: _existingAppointment!.packageNameSnapshot ?? 'Package',
          packagePrice: _existingAppointment!.packagePrice ?? 0,
          startDate: '',
          expiryDate: '',
          createdDate: _existingAppointment!.createdDate,
          services: _selectedServices
              .where((e) => e.packageId == _existingAppointment!.packageId)
              .map((e) => PackageService(
                    packageId: _existingAppointment!.packageId!,
                    serviceId: e.serviceId,
                    categoryId: e.categoryId,
                    serviceTypeId: e.serviceTypeId,
                    categoryNameSnapshot: e.categoryName,
                    serviceTypeNameSnapshot: e.serviceTypeName,
                    serviceNameSnapshot: e.serviceName,
                    normalPrice: e.normalPrice ?? e.price,
                    packageServiceAmount: e.price,
                    quantity: e.quantity,
                  ))
              .toList(),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Converts a pre-multi-service appointment's legacy single-service columns
  /// into the same shape as [AppointmentService] so old data still displays.
  Future<List<AppointmentService>> _legacyServiceAsList(Appointment appointment) async {
    if (appointment.serviceId == null && appointment.serviceNameSnapshot.isEmpty) {
      return const [];
    }
    final service =
        appointment.serviceId != null ? await _serviceDao.get(appointment.serviceId!) : null;
    return [
      AppointmentService(
        appointmentId: appointment.id ?? 0,
        serviceId: appointment.serviceId,
        categoryId: appointment.categoryId,
        serviceTypeId: appointment.serviceTypeId,
        categoryNameSnapshot: service?.categoryName ?? '',
        serviceTypeNameSnapshot: service?.serviceTypeName,
        serviceNameSnapshot: appointment.serviceNameSnapshot,
        price: service?.defaultPrice ?? 0.0,
        total: service?.defaultPrice ?? 0.0,
      ),
    ];
  }

  Future<void> _loadCategoryData(int categoryId) async {
    final categoryProvider = context.read<CategoryProvider>();
    final serviceProvider = context.read<ServiceProvider>();
    _serviceTypes = await categoryProvider.getServiceTypesForCategory(categoryId);
    _services = await serviceProvider.getServicesForCategory(
      categoryId,
      onlyDirect: _selectedServiceTypeValue == _directServiceTypeValue,
      serviceTypeId:
          _selectedServiceTypeValue == _directServiceTypeValue ? null : _selectedServiceTypeValue,
    );
    if (_selectedService != null &&
        !_services.any((service) => service.id == _selectedService!.id)) {
      _services = [..._services, _selectedService!];
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _appointmentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _appointmentDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      _showMessage('Please select a customer.');
      return;
    }
    if (_selectedServices.isEmpty) {
      _showMessage('Please add at least one service.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final appointmentDate = _dateOnly(_appointmentDate);
      final startTime = _timeOnly(_startTime);
      final slotTaken = await context.read<AppointmentProvider>().isSlotTaken(
            _appointmentDate,
            startTime,
            excludeId: _existingAppointment?.id,
          );
      if (slotTaken && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Warning: another pending appointment already exists for this slot.'),
          ),
        );
      }

      final firstService = _selectedServices.first;
      double? packageNormalTotal;
      double? packagePrice;
      double? packageDiscount;
      String? packageNameSnapshot;
      if (_selectedPackage != null) {
        packageNormalTotal = _selectedPackage!.services
            .fold(0.0, (sum, ps) => sum + ps.normalPrice * ps.quantity);
        packagePrice = _selectedServices
            .where((e) => e.packageId == _selectedPackage!.id)
            .fold(0.0, (sum, e) => sum + e.total);
        packageDiscount = packageNormalTotal - packagePrice;
        packageNameSnapshot = _selectedPackage!.name;
      }
      final appointment = Appointment(
        id: _existingAppointment?.id,
        customerId: _selectedCustomer!.id!,
        serviceId: firstService.serviceId,
        categoryId: firstService.categoryId,
        serviceTypeId: firstService.serviceTypeId,
        serviceNameSnapshot: firstService.serviceName,
        appointmentDate: appointmentDate,
        startTime: startTime,
        endTime: _existingAppointment?.endTime,
        status: _existingAppointment?.status ?? AppointmentStatus.pending,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        visitId: _existingAppointment?.visitId,
        reminderMinutesBefore: _reminderMinutesBefore,
        createdDate:
            _existingAppointment?.createdDate ?? DateTime.now().toIso8601String(),
        updatedDate: _existingAppointment == null
            ? null
            : DateTime.now().toIso8601String(),
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        packageId: _selectedPackage?.id,
        packageNameSnapshot: packageNameSnapshot,
        packageNormalTotal: packageNormalTotal,
        packagePrice: packagePrice,
        packageDiscount: packageDiscount,
      );

      final serviceRows = _selectedServices
          .map((s) => AppointmentService(
                appointmentId: _existingAppointment?.id ?? 0,
                serviceId: s.serviceId,
                categoryId: s.categoryId,
                serviceTypeId: s.serviceTypeId,
                categoryNameSnapshot: s.categoryName,
                serviceTypeNameSnapshot: s.serviceTypeName,
                serviceNameSnapshot: s.serviceName,
                price: s.price,
                quantity: s.quantity,
                total: s.total,
                createdAt: DateTime.now().toIso8601String(),
                isPackageItem: s.isPackageItem,
                packageId: s.packageId,
                normalPriceSnapshot: s.normalPrice,
              ))
          .toList();

      final provider = context.read<AppointmentProvider>();
      if (_existingAppointment == null) {
        await provider.addAppointment(appointment, services: serviceRows);
      } else {
        await provider.updateAppointment(appointment, services: serviceRows);
      }

      if (mounted) context.pop(true);
    } catch (e) {
      _showMessage('Unable to save appointment: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double get _selectedServicesTotal =>
      _selectedServices.fold(0, (sum, item) => sum + item.total);

  void _addSelectedService() {
    final service = _selectedService;
    if (service == null) return;
    setState(() {
      final existingIndex = _selectedServices.indexWhere((s) => s.serviceId == service.id);
      if (existingIndex != -1) {
        _selectedServices[existingIndex].quantity++;
      } else {
        _selectedServices.add(_AppointmentServiceEntry(
          serviceId: service.id,
          categoryId: service.categoryId,
          serviceTypeId: service.serviceTypeId,
          categoryName: service.categoryName ?? _selectedCategory?.name ?? '',
          serviceTypeName: service.serviceTypeName,
          serviceName: service.name,
          price: service.defaultPrice,
        ));
      }
    });
  }

  void _removeSelectedService(int index) {
    setState(() {
      if (_selectedServices[index].isPackageItem) {
        _removePackage();
      } else {
        _selectedServices.removeAt(index);
      }
    });
  }

  void _changeSelectedServiceQuantity(int index, int delta) {
    setState(() {
      final item = _selectedServices[index];
      if (item.isPackageItem) return; // package quantities are fixed at selection time
      final next = item.quantity + delta;
      if (next <= 0) {
        _selectedServices.removeAt(index);
      } else {
        item.quantity = next;
      }
    });
  }

  /// Removes all services that belong to the currently-selected package and
  /// clears the package selection. Does NOT touch the service master data.
  void _removePackage() {
    _selectedServices.removeWhere((e) => e.isPackageItem);
    _selectedPackage = null;
  }

  /// Opens the package picker for the current appointment date, re-validates
  /// the chosen package, then replaces any previously-selected package with
  /// the newly chosen one and auto-adds its services.
  Future<void> _addPackage() async {
    final dateStr = _dateOnly(_appointmentDate);
    final picked = await showPackagePickerSheet(context, dateStr);
    if (picked == null || !mounted) return;

    final validation =
        await context.read<PackageProvider>().validate(picked.id!, dateStr);
    if (!validation.isValid || validation.package == null) {
      if (!mounted) return;
      _showMessage(validation.message ?? 'This package is not valid for the selected date.');
      return;
    }
    final validated = validation.package!;

    setState(() {
      _removePackage();
      _selectedPackage = validated;
      for (final ps in validated.services) {
        _selectedServices.add(_AppointmentServiceEntry(
          serviceId: ps.serviceId,
          categoryId: ps.categoryId,
          serviceTypeId: ps.serviceTypeId,
          categoryName: ps.categoryNameSnapshot,
          serviceTypeName: ps.serviceTypeNameSnapshot,
          serviceName: ps.serviceNameSnapshot,
          price: ps.packageServiceAmount,
          quantity: ps.quantity,
          packageId: validated.id,
          normalPrice: ps.normalPrice,
        ));
      }
    });
  }

  Widget _buildSelectedServiceRow(int index) {
    final item = _selectedServices[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.isPackageItem ? '${item.serviceName} (Package)' : item.serviceName,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                      color: item.isPackageItem ? AppColors.accent : AppColors.textPrimary)),
                Text(
                  AppFormatters.formatCurrency(item.price),
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
              ],
            ),
          ),
          if (item.isPackageItem)
            Text('×${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w600))
          else ...[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              onPressed: () => _changeSelectedServiceQuantity(index, -1),
            ),
            Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              onPressed: () => _changeSelectedServiceQuantity(index, 1),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
            onPressed: () => _removeSelectedService(index),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageSummaryBlock() {
    final pkg = _selectedPackage!;
    final normalTotal = pkg.services.fold(0.0, (sum, ps) => sum + ps.normalPrice * ps.quantity);
    final packageAmount = _selectedServices
        .where((e) => e.packageId == pkg.id)
        .fold(0.0, (sum, e) => sum + e.total);
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
            ],
          ),
          const SizedBox(height: 8),
          _packageSummaryRow('Actual Service Amount', normalTotal, strike: true),
          _packageSummaryRow('Package Price', packageAmount, color: AppColors.primary, bold: true),
          _packageSummaryRow('Package Discount', discount, color: AppColors.success),
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.appointmentId == null ? 'New Appointment' : 'Edit Appointment'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _buildSection(
                    title: 'Customer',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Autocomplete<Customer>(
                          key: ValueKey(_selectedCustomer?.id),
                          initialValue: TextEditingValue(
                            text: _selectedCustomer == null
                                ? ''
                                : _customerLabel(_selectedCustomer!),
                          ),
                          displayStringForOption: _customerLabel,
                          optionsBuilder: (value) {
                            final query = value.text.trim().toLowerCase();
                            if (query.isEmpty) return _customers.take(8);
                            return _customers.where((customer) {
                              return customer.name.toLowerCase().contains(query) ||
                                  (customer.phone ?? '').contains(query);
                            }).take(8);
                          },
                          onSelected: (customer) => setState(() => _selectedCustomer = customer),
                          fieldViewBuilder:
                              (context, controller, focusNode, onFieldSubmitted) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Search customer *',
                                hintText: 'Type name or phone',
                                prefixIcon: Icon(Icons.person_search_rounded),
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty && _selectedCustomer == null) {
                                  return 'Please select a customer';
                                }
                                return null;
                              },
                              onChanged: (value) {
                                if (_selectedCustomer != null &&
                                    _customerLabel(_selectedCustomer!) != value) {
                                  _selectedCustomer = null;
                                }
                              },
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(12),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 240),
                                  child: SizedBox(
                                    width: MediaQuery.of(context).size.width - 32,
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                      final customer = options.elementAt(index);
                                        return ListTile(
                                          title: Text(customer.name),
                                          subtitle: (customer.phone ?? '').isEmpty
                                              ? null
                                              : Text(customer.phone!),
                                          onTap: () => onSelected(customer),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _createNewCustomer,
                            icon: const Icon(Icons.person_add_rounded, size: 18),
                            label: const Text('Add Customer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Service',
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addPackage,
                            icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.accent),
                            label: const Text('Add Package'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedCategory?.id,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            prefixIcon: Icon(Icons.category_rounded),
                          ),
                          items: _categories
                              .map((category) => DropdownMenuItem<int>(
                                    value: category.id,
                                    child: Text(category.name),
                                  ))
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() {
                              _selectedCategory =
                                  _categories.firstWhere((category) => category.id == value);
                              _selectedServiceTypeValue = _directServiceTypeValue;
                              _selectedService = null;
                              _serviceTypes = [];
                              _services = [];
                            });
                            await _loadCategoryData(value);
                          },
                          validator: (value) => value == null ? 'Please choose a category' : null,
                        ),
                        const SizedBox(height: 12),
                        if (_selectedCategory != null)
                          DropdownButtonFormField<int>(
                            initialValue: _selectedServiceTypeValue,
                            decoration: const InputDecoration(
                              labelText: 'Service Type',
                              prefixIcon: Icon(Icons.account_tree_rounded),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: _directServiceTypeValue,
                                child: Text('Direct Services / No Type'),
                              ),
                              ..._serviceTypes.map((type) => DropdownMenuItem<int>(
                                    value: type.id,
                                    child: Text(type.name),
                                  )),
                            ],
                            onChanged: (value) async {
                              if (value == null || _selectedCategory == null) return;
                              setState(() {
                                _selectedServiceTypeValue = value;
                                _selectedService = null;
                              });
                              await _loadCategoryData(_selectedCategory!.id!);
                            },
                          ),
                        if (_selectedCategory != null) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedService?.id,
                            decoration: const InputDecoration(
                              labelText: 'Service',
                              prefixIcon: Icon(Icons.spa_rounded),
                            ),
                            items: _services
                                .map((service) => DropdownMenuItem<int>(
                                      value: service.id,
                                      child: Text(
                                        '${service.name} • ${AppFormatters.formatCurrency(service.defaultPrice)}',
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedService = value == null
                                    ? null
                                    : _services.firstWhere((service) => service.id == value);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _selectedService == null ? null : _addSelectedService,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add Service'),
                            ),
                          ),
                        ],
                        if (_selectedServices.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          if (_selectedPackage != null) _buildPackageSummaryBlock(),
                          Column(
                            children: [
                              for (int i = 0; i < _selectedServices.length; i++)
                                _buildSelectedServiceRow(i),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total: ${AppFormatters.formatCurrency(_selectedServicesTotal)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          const Text(
                            'No services added yet. Choose a category and service above, then tap "Add Service". You can add multiple services, just like on a visit.',
                            style: TextStyle(fontSize: 12, color: AppColors.textHint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Schedule',
                    child: Column(
                      children: [
                        _PickerTile(
                          icon: Icons.calendar_today_rounded,
                          label: 'Appointment Date',
                          value: AppFormatters.formatDate(_appointmentDate),
                          onTap: _pickDate,
                        ),
                        const SizedBox(height: 12),
                        _PickerTile(
                          icon: Icons.access_time_rounded,
                          label: 'Start Time',
                          value: _timeOnly(_startTime),
                          onTap: _pickTime,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: _reminderMinutesBefore,
                          decoration: const InputDecoration(
                            labelText: 'Reminder',
                            prefixIcon: Icon(Icons.notifications_active_rounded),
                          ),
                          items: const [
                            DropdownMenuItem<int?>(value: null, child: Text('No reminder')),
                            DropdownMenuItem<int?>(value: 15, child: Text('15 minutes before')),
                            DropdownMenuItem<int?>(value: 30, child: Text('30 minutes before')),
                            DropdownMenuItem<int?>(value: 60, child: Text('1 hour before')),
                          ],
                          onChanged: (value) => setState(() => _reminderMinutesBefore = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Notes',
                    child: TextFormField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Optional notes about the appointment',
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Save Appointment'),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _customerLabel(Customer customer) {
    if ((customer.phone ?? '').isEmpty) return customer.name;
    return '${customer.name} • ${customer.phone}';
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

    if (created != null && mounted) {
      setState(() {
        if (!_customers.any((c) => c.id == created.id)) {
          _customers = [..._customers, created];
        }
        _selectedCustomer = created;
      });
    }
  }

  TimeOfDay _parseTimeOfDay(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _timeOnly(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F0F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

/// One service the user has added to the appointment being booked. Mirrors
/// the `_BillItem` used on the New Visit screen so the same service becomes
/// the same visit-service line item once the appointment is completed.
class _AppointmentServiceEntry {
  final int? serviceId;
  final int? categoryId;
  final int? serviceTypeId;
  final String categoryName;
  final String? serviceTypeName;
  final String serviceName;
  final double price;
  int quantity;

  /// Set when this entry was auto-added as part of a package; [normalPrice]
  /// preserves the service's own default price alongside the (possibly
  /// discounted) package [price] without ever touching the service master.
  final int? packageId;
  final double? normalPrice;
  bool get isPackageItem => packageId != null;

  _AppointmentServiceEntry({
    this.serviceId,
    this.categoryId,
    this.serviceTypeId,
    required this.categoryName,
    this.serviceTypeName,
    required this.serviceName,
    required this.price,
    this.quantity = 1,
    this.packageId,
    this.normalPrice,
  });

  double get total => price * quantity;
}
