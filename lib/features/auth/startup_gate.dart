import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/firebase_startup_provider.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

class StartupGate extends StatefulWidget {
  final Widget child;
  const StartupGate({required this.child, super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final startup = context.read<FirebaseStartupProvider>();
      if (!startup.isReady) {
        startup.checkStartup();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<FirebaseStartupProvider>();
    switch (startup.state) {
      case FirebaseStartupState.unauthenticated:
        return const LoginScreen();
      case FirebaseStartupState.accessDenied:
        return _StartupMessage(
          title: 'Access denied',
          message: startup.errorMessage ?? 'Your account is not authorized.',
          actionLabel: 'Sign out',
          onAction: startup.signOut,
        );
      case FirebaseStartupState.offline:
        return _StartupMessage(
          title: 'Internet connection required',
          message:
              startup.errorMessage ?? 'Connect to the internet to continue.',
          actionLabel: 'Retry',
          onAction: startup.checkStartup,
        );
      case FirebaseStartupState.error:
        return _StartupMessage(
          title: 'Unable to connect',
          message: startup.errorMessage ?? 'Firebase is unavailable.',
          actionLabel: 'Retry',
          onAction: startup.checkStartup,
        );
      case FirebaseStartupState.initializing:
      case FirebaseStartupState.checkingMembership:
      case FirebaseStartupState.checkingConnectivity:
        return const _StartupLoading();
      case FirebaseStartupState.ready:
        return widget.child;
    }
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _StartupMessage extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _StartupMessage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: AppColors.warning,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
