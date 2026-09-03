import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/settings_provider.dart';
import 'pin_pad.dart';

/// Two-step "enter PIN" → "confirm PIN" flow, used both to set a new PIN and
/// to change an existing one. Pops `true` on success.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _firstPin = '';
  String _value = '';
  bool _isConfirming = false;
  String? _error;

  Future<void> _onChanged(String v) async {
    setState(() {
      _value = v;
      _error = null;
    });
    if (v.length != kPinLength) return;

    if (!_isConfirming) {
      setState(() {
        _firstPin = v;
        _isConfirming = true;
        _value = '';
      });
      return;
    }

    if (v == _firstPin) {
      await context.read<SettingsProvider>().setPin(v);
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() {
        _error = 'PINs did not match. Try again.';
        _isConfirming = false;
        _firstPin = '';
        _value = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Set App PIN')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                _isConfirming ? 'Confirm your PIN' : 'Create a $kPinLength-digit PIN',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'You will be asked for this PIN every time you open the app.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ],
              const SizedBox(height: 24),
              PinPad(value: _value, onChanged: _onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
