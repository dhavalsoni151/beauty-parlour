import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/customers/customers_list_screen.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/customers/customer_profile_screen.dart';
import 'features/services/categories_screen.dart';
import 'features/services/services_screen.dart';
import 'features/visits/new_visit_screen.dart';
import 'features/visits/visit_detail_screen.dart';
import 'features/payments/pending_payments_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/expenses/expense_form_screen.dart';
import 'features/expenses/expense_categories_screen.dart';
import 'features/reports/reports_home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/backup_restore_screen.dart';
import 'shared/widgets/main_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const DashboardScreen()),
        GoRoute(path: '/customers', builder: (c, s) => const CustomersListScreen()),
        GoRoute(path: '/reports', builder: (c, s) => const ReportsHomeScreen()),
      ],
    ),
    // Full-screen routes (no bottom nav)
    GoRoute(
      path: '/new-visit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) {
        final customerId = s.uri.queryParameters['customerId'];
        return NewVisitScreen(preselectedCustomerId: customerId != null ? int.tryParse(customerId) : null);
      },
    ),
    GoRoute(
      path: '/customer/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const CustomerFormScreen(),
    ),
    GoRoute(
      path: '/customer/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => CustomerFormScreen(customerId: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/customer/:id/profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => CustomerProfileScreen(customerId: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/categories',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const CategoriesScreen(),
    ),
    GoRoute(
      path: '/services',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) {
        final categoryId = s.uri.queryParameters['categoryId'];
        return ServicesScreen(initialCategoryId: categoryId != null ? int.tryParse(categoryId) : null);
      },
    ),
    GoRoute(
      path: '/visit/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => VisitDetailScreen(visitId: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/pending-payments',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const PendingPaymentsScreen(),
    ),
    GoRoute(
      path: '/expenses',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const ExpensesScreen(),
    ),
    GoRoute(
      path: '/expense/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const ExpenseFormScreen(),
    ),
    GoRoute(
      path: '/expense/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => ExpenseFormScreen(expenseId: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/expense-categories',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const ExpenseCategoriesScreen(),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/backup-restore',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const BackupRestoreScreen(),
    ),
  ],
);

class BeautyParlourApp extends StatelessWidget {
  const BeautyParlourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Beauty Parlour',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
