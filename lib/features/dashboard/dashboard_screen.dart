import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/dashboard_provider.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/migration_mapping.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
      context.read<AppointmentProvider>().loadUpcomingAppointments();
      _checkMigrationReport();
    });
  }

  /// If a legacy-data migration ran on this launch, a report was stored under
  /// the `pending_migration_report` settings key. Show it once, then clear it.
  Future<void> _checkMigrationReport() async {
    final dao = SettingsDao();
    final raw = await dao.getSetting('pending_migration_report');
    if (raw == null || raw.isEmpty) return;
    await dao.deleteSetting('pending_migration_report');
    if (!mounted) return;
    MigrationReport report;
    try {
      report = MigrationReport.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data Migration Complete'),
        content: SingleChildScrollView(
          child: Text(report.buildSummary(),
              style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<DashboardProvider>().loadDashboard();
      context.read<AppointmentProvider>().loadUpcomingAppointments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer2<DashboardProvider, SettingsProvider>(
        builder: (context, dash, settings, _) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              await dash.loadDashboard();
              if (context.mounted) {
                await context.read<AppointmentProvider>().loadUpcomingAppointments();
              }
            },
            child: CustomScrollView(
              slivers: [
                _buildAppBar(context, settings),
                SliverToBoxAdapter(
                  child: dash.isLoading
                      ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                      : _buildContent(context, dash),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SettingsProvider settings) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    settings.parlourName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  Text(
                    AppFormatters.formatDate(DateTime.now()),
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: const Text('Dashboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DashboardProvider dash) {
    final today = dash.todayStats;
    final month = dash.monthStats;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick actions
          _QuickActions(),
          const SizedBox(height: 20),

          // Today section
          const SectionHeader(title: "Today's Summary"),
          const SizedBox(height: 12),
          _TodayStats(stats: today),
          const SizedBox(height: 20),

          // Appointments
          const SectionHeader(title: "Today's / Upcoming Appointments"),
          const SizedBox(height: 12),
          const _UpcomingAppointmentsSection(),
          const SizedBox(height: 20),

          // Sales trend chart
          _SalesTrendChart(data: dash.salesTrend),
          const SizedBox(height: 20),

          // This month summary
          const SectionHeader(title: 'This Month'),
          const SizedBox(height: 12),
          _MonthStats(stats: month),
          const SizedBox(height: 20),

          // Top services
          _TopServicesChart(data: dash.topServices),
          const SizedBox(height: 20),

          // Payment breakdown
          _PaymentMethodChart(data: dash.paymentBreakdown),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  Future<void> _openAndRefresh(BuildContext context, String route) async {
    await context.push(route);
    if (context.mounted) {
      await context.read<DashboardProvider>().loadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('New Visit', Icons.add_circle_rounded, AppColors.primary, () => _openAndRefresh(context, '/new-visit')),
      ('Customer', Icons.person_add_rounded, AppColors.secondary, () => _openAndRefresh(context, '/customer/new')),
      ('Expense', Icons.receipt_rounded, AppColors.warning, () => _openAndRefresh(context, '/expenses')),
      ('Pending', Icons.pending_actions_rounded, AppColors.error, () => _openAndRefresh(context, '/pending-payments')),
    ];

    return Row(
      children: actions.map((a) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: a.$4,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: a.$3.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: a.$3.withOpacity(0.25)),
                ),
                child: Column(
                  children: [
                    Icon(a.$2, color: a.$3, size: 24),
                    const SizedBox(height: 4),
                    Text(a.$1,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: a.$3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TodayStats extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _TodayStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    final profit = (stats['profit'] as num? ?? 0).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'Collections',
              value: AppFormatters.formatCurrency((stats['collected'] as num? ?? 0).toDouble()),
              icon: Icons.payments_rounded,
              color: AppColors.success,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Expenses',
              value: AppFormatters.formatCurrency((stats['total_expenses'] as num? ?? 0).toDouble()),
              icon: Icons.shopping_bag_rounded,
              color: AppColors.warning,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'Profit',
              value: AppFormatters.formatCurrency(profit),
              icon: profit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: profit >= 0 ? AppColors.success : AppColors.error,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Customers',
              value: '${stats['visit_count'] ?? 0}',
              icon: Icons.people_rounded,
              color: AppColors.primary,
              subtitle: 'visits today',
            )),
          ],
        ),
        const SizedBox(height: 12),
        StatCard(
          title: 'Pending Payments',
          value: AppFormatters.formatCurrency((stats['pending'] as num? ?? 0).toDouble()),
          icon: Icons.pending_actions_rounded,
          color: AppColors.error,
          onTap: () => context.push('/pending-payments'),
        ),
      ],
    );
  }
}

class _MonthStats extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _MonthStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    final profit = (stats['profit'] as num? ?? 0).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'Net Sales',
              value: AppFormatters.formatCurrency((stats['net_sales'] as num? ?? 0).toDouble()),
              icon: Icons.store_rounded,
              color: AppColors.primary,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Collections',
              value: AppFormatters.formatCurrency((stats['collected'] as num? ?? 0).toDouble()),
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.success,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'Expenses',
              value: AppFormatters.formatCurrency((stats['total_expenses'] as num? ?? 0).toDouble()),
              icon: Icons.shopping_cart_rounded,
              color: AppColors.warning,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Profit',
              value: AppFormatters.formatCurrency(profit),
              icon: profit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: profit >= 0 ? AppColors.success : AppColors.error,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'New Customers',
              value: '${stats['new_customers'] ?? 0}',
              icon: Icons.person_add_rounded,
              color: AppColors.secondary,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Returning',
              value: '${stats['returning_customers'] ?? 0}',
              icon: Icons.replay_rounded,
              color: AppColors.info,
            )),
          ],
        ),
      ],
    );
  }
}

class _SalesTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _SalesTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxY = data.map((d) => (d['sales'] as num? ?? 0).toDouble()).fold(0.0, (a, b) => a > b ? a : b);
    final spots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value['sales'] as num? ?? 0).toDouble());
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sales This Month',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (v, _) => Text(
                        v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: maxY * 1.2,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(show: spots.length <= 10),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [AppColors.primary.withOpacity(0.3), AppColors.primary.withOpacity(0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopServicesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _TopServicesChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Services This Month',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...data.asMap().entries.map((e) {
            final s = e.value;
            final revenue = (s['revenue'] as num? ?? 0).toDouble();
            final maxRevenue = (data.first['revenue'] as num? ?? 1).toDouble();
            final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${s['name']}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(AppFormatters.formatCurrency(revenue),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(width: 8),
                      Text('${s['visit_count']} visits',
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxRevenue > 0 ? revenue / maxRevenue : 0,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PaymentMethodChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _PaymentMethodChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final total = data.fold(0.0, (sum, d) => sum + (d['total'] as num? ?? 0).toDouble());
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Methods',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: PieChart(
                  PieChartData(
                    sections: data.asMap().entries.map((e) {
                      final d = e.value;
                      final value = (d['total'] as num? ?? 0).toDouble();
                      final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
                      return PieChartSectionData(
                        value: value,
                        color: color,
                        radius: 45,
                        title: '',
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 20,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: data.asMap().entries.map((e) {
                    final d = e.value;
                    final value = (d['total'] as num? ?? 0).toDouble();
                    final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
                    final label = _methodLabel(d['payment_method'] as String? ?? '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(label,
                            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                          Text(AppFormatters.formatCurrency(value),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'CASH': return 'Cash';
      case 'UPI': return 'UPI';
      case 'CARD': return 'Card';
      case 'BANK_TRANSFER': return 'Bank Transfer';
      default: return 'Other';
    }
  }
}


class _UpcomingAppointmentsSection extends StatelessWidget {
  const _UpcomingAppointmentsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, provider, _) {
        final items = provider.upcomingAppointments.take(5).toList();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Next reminders',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/appointments'),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No upcoming appointments.',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
                )
              else
                ...items.map((appointment) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appointment.customerName ?? 'Customer #${appointment.customerId}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${appointment.serviceNameSnapshot} • ${AppFormatters.formatDate(DateTime.parse(appointment.appointmentDate))} • ${appointment.startTime}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppointmentStatusBadge(status: appointment.status),
                        ],
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}
