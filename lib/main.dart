import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/database/database.dart';
import 'core/providers/customer_provider.dart';
import 'core/providers/category_provider.dart';
import 'core/providers/service_provider.dart';
import 'core/providers/visit_provider.dart';
import 'core/providers/expense_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/dashboard_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opening the database runs onCreate (fresh install) or onUpgrade (legacy
  // v1 -> v2 auto-migration incl. the Category -> ServiceType hierarchy fix).
  await AppDatabase.instance.database;
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()..loadCustomers()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()..loadCategories()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()..loadServices()),
        ChangeNotifierProvider(create: (_) => VisitProvider()..loadVisits()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()..loadExpenses()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
      ],
      child: const BeautyParlourApp(),
    ),
  );
}
