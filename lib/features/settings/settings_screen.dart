import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../security/pin_pad.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _parlourNameCtrl;
  late TextEditingController _ownerNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _parlourNameCtrl = TextEditingController(text: s.parlourName);
    _ownerNameCtrl = TextEditingController(text: s.ownerName);
    _phoneCtrl = TextEditingController(text: s.phone);
    _addressCtrl = TextEditingController(text: s.address);
  }

  @override
  void dispose() {
    _parlourNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Parlour Info
            _buildSectionTitle('Parlour Information'),
            const SizedBox(height: 10),
            _buildCard([
              _buildField(_parlourNameCtrl, 'Parlour Name', Icons.store_rounded),
              const SizedBox(height: 12),
              _buildField(_ownerNameCtrl, 'Owner Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _buildField(_phoneCtrl, 'Phone Number', Icons.phone_rounded,
                keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildField(_addressCtrl, 'Address', Icons.location_on_rounded, maxLines: 3),
            ]),
            const SizedBox(height: 16),

            // Save button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Settings'),
              ),
            ),
            const SizedBox(height: 24),

            // Data Management
            _buildSectionTitle('Data Management'),
            const SizedBox(height: 10),
            _buildCard([
              _buildMenuTile(
                Icons.cloud_upload_rounded, 'Backup & Restore',
                'Backup or restore your data',
                AppColors.info, () => context.push('/backup-restore')),
            ]),
            const SizedBox(height: 16),

            // Security
            _buildSectionTitle('Security'),
            const SizedBox(height: 10),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) => _buildCard([
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.isPinEnabled,
                  activeColor: AppColors.primary,
                  title: const Text('App PIN Lock',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  subtitle: const Text('Require a PIN every time the app is opened',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onChanged: (enable) => _onPinToggle(context, settings, enable),
                ),
                if (settings.isPinEnabled) ...[
                  const Divider(height: 20),
                  _buildMenuTile(
                    Icons.password_rounded, 'Change PIN',
                    'Set a new app-unlock PIN',
                    AppColors.primary, () => context.push('/pin-setup')),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // About
            _buildSectionTitle('About'),
            const SizedBox(height: 10),
            _buildCard([
              _buildInfoTile('App Version', '1.0.0'),
              _buildInfoTile('Currency', '₹ Indian Rupee'),
              _buildInfoTile('Database', 'Local SQLite (Offline)'),
            ]),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        color: AppColors.textSecondary, letterSpacing: 0.5));
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

  Widget _buildField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          )),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await context.read<SettingsProvider>().updateAll(
        parlourName: _parlourNameCtrl.text.trim().isEmpty ? 'Priyanka Beauty Parlour' : _parlourNameCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onPinToggle(BuildContext context, SettingsProvider settings, bool enable) async {
    if (enable) {
      final created = await context.push<bool>('/pin-setup');
      if (created == true && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('App PIN lock enabled')));
      }
      return;
    }

    // Require the current PIN before disabling the lock.
    final confirmedPin = await _promptCurrentPin(context, settings);
    if (confirmedPin != true) return;
    await settings.disablePin();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('App PIN lock disabled')));
    }
  }

  Future<bool?> _promptCurrentPin(BuildContext context, SettingsProvider settings) async {
    String value = '';
    String? error;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Enter Current PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              PinPad(
                value: value,
                onChanged: (v) {
                  setDialogState(() {
                    value = v;
                    error = null;
                  });
                  if (v.length == kPinLength) {
                    if (settings.verifyPin(v)) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() {
                        error = 'Incorrect PIN';
                        value = '';
                      });
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
