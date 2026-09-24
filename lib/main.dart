import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/database/database.dart';
import 'core/providers/customer_provider.dart';
import 'core/providers/category_provider.dart';
import 'core/providers/visit_provider.dart';
import 'core/providers/expense_provider.dart';
import 'core/providers/appointment_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/app_lock_provider.dart';
import 'core/providers/dashboard_provider.dart';
import 'core/providers/package_provider.dart';
import 'core/providers/reminder_provider.dart';
import 'core/services/notification_service.dart';
import 'core/firebase/firebase_service.dart';
import 'core/providers/firebase_startup_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never let Firebase initialization hang the process on the native
  // launch splash: capture the failure and start the Flutter UI anyway so
  // StartupGate can show a retryable error instead of a stuck screen.
  String? firebaseInitError;
  try {
    await FirebaseService.instance
        .initialize()
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    firebaseInitError = error.toString();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => FirebaseStartupProvider(
            firebaseInitError: firebaseInitError,
          ),
        ),
        // App-wide providers live above the router exactly once, so neither
        // the startup gate nor the splash screen ever rebuilds MaterialApp
        // or runs without the providers it consumes.
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
        ChangeNotifierProvider(create: (_) => VisitProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => PackageProvider()),
        ChangeNotifierProvider(create: (_) => ReminderProvider()),
      ],
      child: const _StartupRoot(),
    ),
  );
}

/// Gates the single [BeautyParlourApp] instance: local database +
/// notifications initialize (once) only after Firebase startup is ready,
/// and business data loads right after — without ever swapping MaterialApp.
class _StartupRoot extends StatefulWidget {
  const _StartupRoot();

  @override
  State<_StartupRoot> createState() => _StartupRootState();
}

class _StartupRootState extends State<_StartupRoot> {
  Future<void>? _localInitialization;

  Future<void> _initializeLocal(BuildContext context) async {
    await AppDatabase.instance.database;
    await NotificationService.instance.initialize();
    if (!context.mounted) return;
    await context.read<SettingsProvider>().loadSettings();
    if (!context.mounted) return;
    await Future.wait([
      context.read<CustomerProvider>().loadCustomers(),
      context.read<CategoryProvider>().loadCategories(),
      context.read<ServiceProvider>().loadServices(),
      context.read<VisitProvider>().loadVisits(),
      context.read<ExpenseProvider>().loadExpenses(),
      context.read<PackageProvider>().loadPackages(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<FirebaseStartupProvider>();
    if (!startup.isReady) {
      // Firebase gate (login / access-denied / offline / error) renders
      // inside the normal app shell; providers above are already present.
      return const BeautyParlourApp();
    }
    _localInitialization ??= _initializeLocal(context);
    return FutureBuilder<void>(
      future: _localInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ApplicationLoading();
        }
        if (snapshot.hasError) {
          return _ApplicationInitializationError(
            error: snapshot.error.toString(),
            onRetry: () => setState(() {
              _localInitialization = _initializeLocal(context);
            }),
          );
        }
        return const BeautyParlourApp();
      },
    );
  }
}

class _ApplicationLoading extends StatelessWidget {
  const _ApplicationLoading();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _ApplicationInitializationError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ApplicationInitializationError({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Unable to initialize the application.\n$error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
