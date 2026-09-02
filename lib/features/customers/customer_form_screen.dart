import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/models/customer_models.dart';
import '../../shared/widgets/app_widgets.dart';

class CustomerFormScreen extends StatefulWidget {
  final int? customerId;
  const CustomerFormScreen({super.key, this.customerId});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _birthDate;
  bool _isSaving = false;
  Customer? _existing;

  bool get isEditing => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadCustomer();
  }

  Future<void> _loadCustomer() async {
    _existing = await context.read<CustomerProvider>().getCustomer(widget.customerId!);
    if (_existing != null) {
      _nameCtrl.text = _existing!.name;
      _phoneCtrl.text = _existing!.phone ?? '';
      _notesCtrl.text = _existing!.notes ?? '';
      if (_existing!.birthDate != null) {
        _birthDate = DateTime.tryParse(_existing!.birthDate!);
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final customer = Customer(
        id: _existing?.id,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        birthDate: _birthDate?.toIso8601String().substring(0, 10),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdDate: _existing?.createdDate ?? now,
        isActive: _existing?.isActive ?? true,
      );

      final provider = context.read<CustomerProvider>();
      if (isEditing) {
        await provider.updateCustomer(customer);
      } else {
        await provider.addCustomer(customer);
      }
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Customer' : 'New Customer'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              onPressed: _confirmDelete,
              tooltip: 'Deactivate',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCard([
              _buildField(
                controller: _nameCtrl,
                label: 'Customer Name *',
                icon: Icons.person_rounded,
                validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _phoneCtrl,
                label: 'Phone Number (Optional)',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildBirthDateField(),
              const SizedBox(height: 12),
              _buildField(
                controller: _notesCtrl,
                label: 'Notes (Optional)',
                icon: Icons.note_rounded,
                maxLines: 3,
              ),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isEditing ? 'Save Changes' : 'Add Customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildBirthDateField() {
    return GestureDetector(
      onTap: _pickBirthDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F0F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _birthDate != null
                    ? '${_birthDate!.day} ${_monthName(_birthDate!.month)} ${_birthDate!.year}'
                    : 'Birth Date (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  color: _birthDate != null ? AppColors.textPrimary : AppColors.textHint,
                ),
              ),
            ),
            if (_birthDate != null)
              GestureDetector(
                onTap: () => setState(() => _birthDate = null),
                child: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
              ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  String _monthName(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }

  Future<void> _confirmDelete() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate Customer',
      message: 'This will hide the customer from the active list. Their history will be preserved.',
      confirmLabel: 'Deactivate',
      confirmColor: AppColors.error,
    );
    if (confirmed && mounted) {
      await context.read<CustomerProvider>().deactivateCustomer(widget.customerId!);
      context.pop();
    }
  }
}
