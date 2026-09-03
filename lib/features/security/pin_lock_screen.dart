import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/app_lock_provider.dart';
import 'pin_pad.dart';

/// Full-screen PIN gate shown on cold start (and whenever the app resumes
/// from the background) while a PIN is configured. Blocks access to the rest
/// of the app until the correct PIN is entered.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _value = '';
  String? _error;

  void _onChanged(String v) {
    setState(() {
      _value = v;
      _error = null;
    });
    if (v.length != kPinLength) return;

    final settings = context.read<SettingsProvider>();
    if (settings.verifyPin(v)) {
      context.read<AppLockProvider>().unlock();
    } else {
      setState(() {
        _error = 'Incorrect PIN. Try again.';
        _value = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 56, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text('Enter PIN',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Consumer<SettingsProvider>(
                  builder: (context, s, _) => Text(
                    s.parlourName,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
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
      ),
    );
  }
}
