import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/app_lock_provider.dart';
import 'features/security/pin_lock_screen.dart';
import 'features/security/pin_setup_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/customers/customers_list_screen.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/customers/customer_profile_screen.dart';
import 'features/services/categories_screen.dart';
import 'features/services/services_screen.dart';
import 'features/services/service_types_screen.dart';
import 'features/visits/new_visit_screen.dart';
import 'features/visits/visit_detail_screen.dart';
import 'features/payments/pending_payments_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/expenses/expense_form_screen.dart';
import 'features/expenses/expense_categories_screen.dart';
import 'features/reports/reports_home_screen.dart';
import 'features/appointments/appointments_screen.dart';
import 'features/appointments/appointment_form_screen.dart';
import 'features/packages/packages_screen.dart';
import 'features/packages/package_form_screen.dart';
import 'features/reminders/reminders_screen.dart';
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
        GoRoute(path: '/appointments', builder: (c, s) => const AppointmentsScreen()),
      ],
    ),
    // Full-screen routes (no bottom nav)
    GoRoute(
      path: '/new-visit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) {
        final customerId = s.uri.queryParameters['customerId'];
        final fromAppointmentId = s.uri.queryParameters['fromAppointmentId'];
        final editVisitId = s.uri.queryParameters['editVisitId'];
        return NewVisitScreen(
          preselectedCustomerId: customerId != null ? int.tryParse(customerId) : null,
          fromAppointmentId: fromAppointmentId != null ? int.tryParse(fromAppointmentId) : null,
          editVisitId: editVisitId != null ? int.tryParse(editVisitId) : null,
        );
      },
    ),
    GoRoute(
      path: '/reminders',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const RemindersScreen(),
    ),
    GoRoute(
      path: '/appointment/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) {
        final customerId = s.uri.queryParameters['customerId'];
        return AppointmentFormScreen(
          preselectedCustomerId: customerId != null ? int.tryParse(customerId) : null,
        );
      },
    ),
    GoRoute(
      path: '/appointment/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => AppointmentFormScreen(appointmentId: int.parse(s.pathParameters['id']!)),
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
      path: '/service-types',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) {
        final categoryId = int.tryParse(s.uri.queryParameters['categoryId'] ?? '');
        return ServiceTypesScreen(categoryId: categoryId ?? 0);
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
    GoRoute(
      path: '/packages',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const PackagesScreen(),
    ),
    GoRoute(
      path: '/package/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const PackageFormScreen(),
    ),
    GoRoute(
      path: '/package/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => PackageFormScreen(packageId: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/pin-setup',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (c, s) => const PinSetupScreen(),
    ),
  ],
);

class BeautyParlourApp extends StatelessWidget {
  const BeautyParlourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Priyanka Beauty Parlour',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Wraps the whole app (via [MaterialApp.builder]) and shows [PinLockScreen]
/// on top of everything whenever a PIN is configured and the session is
/// currently locked (cold start, or resumed from the background).
class _AppLockGate extends StatefulWidget {
  final Widget child;
  const _AppLockGate({required this.child});

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock whenever the app leaves the foreground so the PIN is required
    // again every time the app is (re)opened, per the product requirement.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      context.read<AppLockProvider>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, AppLockProvider>(
      builder: (context, settings, appLock, _) {
        if (!settings.isLoaded) {
          return const Material(
            color: AppColors.background,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final showLock = settings.isPinEnabled && appLock.isLocked;
        return Stack(
          children: [
            widget.child,
            if (showLock) const PinLockScreen(),
          ],
        );
      },
    );
  }
}
