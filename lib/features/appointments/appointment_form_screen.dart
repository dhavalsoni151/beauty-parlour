import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/models/appointment_models.dart';
import '../../core/models/customer_models.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/providers/category_provider.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

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

    if (_existingAppointment?.serviceId != null) {
      final service = await _serviceDao.get(_existingAppointment!.serviceId!);
      if (service != null) {
        _selectedService = service;
        _selectedCategory ??= _categories.firstWhere(
          (c) => c.id == service.categoryId,
          orElse: () => Category(
            id: service.categoryId,
            name: service.categoryName ?? 'Category',
            createdDate: DateTime.now().toIso8601String(),
          ),
        );
        _selectedServiceTypeValue = service.serviceTypeId ?? _directServiceTypeValue;
        await _loadCategoryData(_selectedCategory!.id!);
        if (service.serviceTypeId != null &&
            !_serviceTypes.any((type) => type.id == service.serviceTypeId)) {
          final currentType = await _serviceTypeDao.get(service.serviceTypeId!);
          if (currentType != null) {
            _serviceTypes = [..._serviceTypes, currentType];
          }
        }
        if (!_services.any((s) => s.id == service.id)) {
          _services = [..._services, service];
        }
      }
    }

    if (mounted) setState(() => _isLoading = false);
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
    if (_selectedService == null) {
      _showMessage('Please select a service.');
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

      final appointment = Appointment(
        id: _existingAppointment?.id,
        customerId: _selectedCustomer!.id!,
        serviceId: _selectedService!.id,
        categoryId: _selectedService!.categoryId,
        serviceTypeId: _selectedService!.serviceTypeId,
        serviceNameSnapshot: _selectedService!.name,
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
      );

      final provider = context.read<AppointmentProvider>();
      if (_existingAppointment == null) {
        await provider.addAppointment(appointment);
      } else {
        await provider.updateAppointment(appointment);
      }

      if (mounted) context.pop(true);
    } catch (e) {
      _showMessage('Unable to save appointment: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Service',
                    child: Column(
                      children: [
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
                              labelText: 'Service *',
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
                            validator: (value) => value == null ? 'Please choose a service' : null,
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
