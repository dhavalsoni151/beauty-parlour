import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/database/database.dart';
import 'core/providers/customer_provider.dart';
import 'core/providers/category_provider.dart';
import 'core/providers/service_provider.dart';
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
  await FirebaseService.instance.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => FirebaseStartupProvider(),
      child: const _FirebaseApplication(),
    ),
  );
}

class _FirebaseApplication extends StatelessWidget {
  const _FirebaseApplication();

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<FirebaseStartupProvider>();
    if (!startup.isReady) return const BeautyParlourApp();
    return const _AuthenticatedApplication();
  }
}

class _AuthenticatedApplication extends StatefulWidget {
  const _AuthenticatedApplication();

  @override
  State<_AuthenticatedApplication> createState() =>
      _AuthenticatedApplicationState();
}

class _AuthenticatedApplicationState extends State<_AuthenticatedApplication> {
  late final Future<void> _legacyInitialization;

  @override
  void initState() {
    super.initState();
    _legacyInitialization = _initializeExistingApplication();
  }

  Future<void> _initializeExistingApplication() async {
    await AppDatabase.instance.database;
    await NotificationService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _legacyInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ApplicationLoading();
        }
        if (snapshot.hasError) {
          return _ApplicationInitializationError(
            error: snapshot.error.toString(),
          );
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SettingsProvider()..loadSettings(),
            ),
            ChangeNotifierProvider(create: (_) => AppLockProvider()),
            ChangeNotifierProvider(
              create: (_) => CustomerProvider()..loadCustomers(),
            ),
            ChangeNotifierProvider(
              create: (_) => CategoryProvider()..loadCategories(),
            ),
            ChangeNotifierProvider(
              create: (_) => ServiceProvider()..loadServices(),
            ),
            ChangeNotifierProvider(
              create: (_) => VisitProvider()..loadVisits(),
            ),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(
              create: (_) => ExpenseProvider()..loadExpenses(),
            ),
            ChangeNotifierProvider(create: (_) => DashboardProvider()),
            ChangeNotifierProvider(
              create: (_) => PackageProvider()..loadPackages(),
            ),
            ChangeNotifierProvider(create: (_) => ReminderProvider()),
          ],
          child: const BeautyParlourApp(),
        );
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
  const _ApplicationInitializationError({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Unable to initialize the application.\n$error'),
          ),
        ),
      ),
    );
  }
}
