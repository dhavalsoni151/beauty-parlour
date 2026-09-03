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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opening the database runs onCreate (fresh install) or onUpgrade (legacy
  // v1 -> v2 auto-migration incl. the Category -> ServiceType hierarchy fix).
  await AppDatabase.instance.database;
  await NotificationService.instance.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()..loadCustomers()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()..loadCategories()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()..loadServices()),
        ChangeNotifierProvider(create: (_) => VisitProvider()..loadVisits()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()..loadExpenses()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => PackageProvider()..loadPackages()),
        ChangeNotifierProvider(create: (_) => ReminderProvider()),
      ],
      child: const BeautyParlourApp(),
    ),
  );
}
