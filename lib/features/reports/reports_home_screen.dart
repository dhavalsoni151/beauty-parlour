import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/providers/expense_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../../core/database/database_helper.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class ReportsHomeScreen extends StatefulWidget {
  const ReportsHomeScreen({super.key});

  @override
  State<ReportsHomeScreen> createState() => _ReportsHomeScreenState();
}

class _ReportsHomeScreenState extends State<ReportsHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _startDate = DateRange.thisMonth().start.toIso8601String();
  String _endDate = DateRange.thisMonth().end.toIso8601String();

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _topServices = [];
  List<Map<String, dynamic>> _topCategories = [];
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _paymentBreakdown = [];
  List<Map<String, dynamic>> _expenseByCategory = [];
  List<Map<String, dynamic>> _birthdays = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReports());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;
    _summary = await db.getDashboardStats(_startDate, _endDate);
    _topServices = await db.getTopServices(_startDate, _endDate, limit: 10);
    _topCategories = await db.getTopCategories(_startDate, _endDate);
    _topCustomers = await db.getTopCustomers(_startDate, _endDate);
    _paymentBreakdown = await db.getPaymentMethodBreakdown(_startDate, _endDate);
    _expenseByCategory = await db.getExpenseByCategory(_startDate, _endDate);

    // Birthday this month
    final now = DateTime.now();
    final mmdd1 = '${now.month.toString().padLeft(2,'0')}-01';
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final mmdd2 = '${now.month.toString().padLeft(2,'0')}-${lastDay.toString().padLeft(2,'0')}';
    _birthdays = await db.getBirthdaysInRange(mmdd1, mmdd2);

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Financial'),
            Tab(text: 'Services'),
            Tab(text: 'Customers'),
            Tab(text: 'Expenses'),
            Tab(text: 'Birthdays'),
          ],
        ),
      ),
      body: Column(
        children: [
          DateRangeSelector(
            onRangeSelected: (s, e, _) {
              _startDate = s;
              _endDate = e;
              _loadReports();
            },
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const LinearProgressIndicator(color: AppColors.primary),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _FinancialTab(summary: _summary, paymentBreakdown: _paymentBreakdown),
                _ServicesTab(topServices: _topServices, topCategories: _topCategories),
                _CustomersTab(topCustomers: _topCustomers, summary: _summary),
                _ExpensesTab(expenseByCategory: _expenseByCategory, summary: _summary),
                _BirthdaysTab(birthdays: _birthdays),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Financial Tab ────────────────────────────────────────────────────────────

class _FinancialTab extends StatelessWidget {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> paymentBreakdown;

  const _FinancialTab({required this.summary, required this.paymentBreakdown});

  @override
  Widget build(BuildContext context) {
    final grossSales = (summary['gross_sales'] as num? ?? 0).toDouble();
    final discounts = (summary['total_discounts'] as num? ?? 0).toDouble();
    final netSales = (summary['net_sales'] as num? ?? 0).toDouble();
    final collected = (summary['collected'] as num? ?? 0).toDouble();
    final pending = (summary['pending'] as num? ?? 0).toDouble();
    final writtenOff = (summary['written_off'] as num? ?? 0).toDouble();
    final expenses = (summary['total_expenses'] as num? ?? 0).toDouble();
    final profit = collected - expenses;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // P&L Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profit & Loss', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              _PLRow('Gross Sales', grossSales, AppColors.textPrimary, isBold: true),
              _PLRow('Discounts', -discounts, AppColors.success),
              _PLRow('Net Sales', netSales, AppColors.textPrimary, isDivider: true, isBold: true),
              _PLRow('Collected', collected, AppColors.success, isBold: true),
              _PLRow('Pending', pending, AppColors.error),
              _PLRow('Written Off', writtenOff, AppColors.writtenOff, isDivider: true),
              _PLRow('Expenses', -expenses, AppColors.error, isDivider: true),
              _PLRow('Profit / Loss', profit, profit >= 0 ? AppColors.success : AppColors.error,
                isBold: true, isLarge: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Visit stats
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'Total Bills',
              value: '${summary['visit_count'] ?? 0}',
              icon: Icons.receipt_rounded,
              color: AppColors.primary,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Avg Bill',
              value: (summary['visit_count'] as num? ?? 0) > 0
                  ? AppFormatters.formatCurrency(netSales / (summary['visit_count'] as num).toDouble())
                  : '₹0',
              icon: Icons.analytics_rounded,
              color: AppColors.secondary,
            )),
          ],
        ),
        const SizedBox(height: 16),
        // Payment method breakdown
        if (paymentBreakdown.isNotEmpty) ...[
          const Text('Payment Methods', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: paymentBreakdown.asMap().entries.map((e) {
                final d = e.value;
                final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_methodLabel(d['payment_method'] as String? ?? ''),
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                      Text(AppFormatters.formatCurrency((d['total'] as num? ?? 0).toDouble()),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'CASH': return 'Cash';
      case 'UPI': return 'UPI';
      case 'CARD': return 'Card';
      case 'BANK_TRANSFER': return 'Bank Transfer';
      default: return 'Other';
    }
  }
}

class _PLRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isDivider;
  final bool isBold;
  final bool isLarge;

  const _PLRow(this.label, this.value, this.color, {
    this.isDivider = false, this.isBold = false, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isDivider) const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label,
                style: TextStyle(
                  fontSize: isLarge ? 15 : 13,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
                  color: AppColors.textPrimary,
                ))),
              Text(
                value < 0 ? '- ${AppFormatters.formatCurrency(-value)}' : AppFormatters.formatCurrency(value),
                style: TextStyle(
                  fontSize: isLarge ? 16 : 13,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Services Tab ─────────────────────────────────────────────────────────────

class _ServicesTab extends StatelessWidget {
  final List<Map<String, dynamic>> topServices;
  final List<Map<String, dynamic>> topCategories;

  const _ServicesTab({required this.topServices, required this.topCategories});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (topServices.isEmpty)
          const EmptyState(title: 'No Data', subtitle: 'No visits in this period', icon: Icons.spa_rounded)
        else ...[
          const Text('Top Services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: topServices.asMap().entries.map((e) {
                final s = e.value;
                final revenue = (s['revenue'] as num? ?? 0).toDouble();
                final maxRevenue = (topServices.first['revenue'] as num? ?? 1).toDouble();
                final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            child: Center(child: Text('${e.key + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${s['name']}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis)),
                          Text('${s['visit_count']} visits',
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                          const SizedBox(width: 8),
                          Text(AppFormatters.formatCurrency(revenue),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
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
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('By Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...topCategories.asMap().entries.map((e) {
            final c = e.value;
            final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${c['name']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                  Text('${c['visit_count']} visits',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 8),
                  Text(AppFormatters.formatCurrency((c['revenue'] as num? ?? 0).toDouble()),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─── Customers Tab ────────────────────────────────────────────────────────────

class _CustomersTab extends StatelessWidget {
  final List<Map<String, dynamic>> topCustomers;
  final Map<String, dynamic> summary;

  const _CustomersTab({required this.topCustomers, required this.summary});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: StatCard(
              title: 'New Customers',
              value: '${summary['new_customers'] ?? 0}',
              icon: Icons.person_add_rounded,
              color: AppColors.secondary,
            )),
            const SizedBox(width: 12),
            Expanded(child: StatCard(
              title: 'Returning',
              value: '${summary['returning_customers'] ?? 0}',
              icon: Icons.replay_rounded,
              color: AppColors.info,
            )),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Most Frequent Customers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        if (topCustomers.isEmpty)
          const EmptyState(title: 'No Data', subtitle: 'No visits in this period', icon: Icons.people_rounded)
        else
          ...topCustomers.asMap().entries.map((e) {
            final c = e.value;
            final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withOpacity(0.7), color]),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text('${e.key + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['name']}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text('${c['visit_count']} visits • Last: ${c['last_visit'] != null ? AppFormatters.formatDate(DateTime.parse(c['last_visit'] as String)) : 'Never'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(AppFormatters.formatCurrency((c['revenue'] as num? ?? 0).toDouble()),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                      if ((c['pending'] as num? ?? 0) > 0)
                        Text('Pending: ${AppFormatters.formatCurrency((c['pending'] as num).toDouble())}',
                          style: const TextStyle(fontSize: 10, color: AppColors.error)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// ─── Expenses Tab ─────────────────────────────────────────────────────────────

class _ExpensesTab extends StatelessWidget {
  final List<Map<String, dynamic>> expenseByCategory;
  final Map<String, dynamic> summary;

  const _ExpensesTab({required this.expenseByCategory, required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = (summary['total_expenses'] as num? ?? 0).toDouble();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatCard(
          title: 'Total Expenses',
          value: AppFormatters.formatCurrency(total),
          icon: Icons.receipt_rounded,
          color: AppColors.warning,
        ),
        const SizedBox(height: 16),
        if (expenseByCategory.isEmpty)
          const EmptyState(title: 'No Expenses', subtitle: 'No expenses in this period', icon: Icons.receipt_rounded)
        else ...[
          const Text('By Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...expenseByCategory.asMap().entries.map((e) {
            final c = e.value;
            final amount = (c['total'] as num? ?? 0).toDouble();
            final color = AppColors.chartColors[e.key % AppColors.chartColors.length];
            final pct = total > 0 ? amount / total : 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${c['name']}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                      Text(AppFormatters.formatCurrency(amount),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(width: 6),
                      Text('${(pct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct.toDouble(),
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─── Birthdays Tab ────────────────────────────────────────────────────────────

class _BirthdaysTab extends StatelessWidget {
  final List<Map<String, dynamic>> birthdays;

  const _BirthdaysTab({required this.birthdays});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMmdd = '${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (birthdays.isEmpty)
          const EmptyState(title: 'No Birthdays', subtitle: 'No customer birthdays this month', icon: Icons.cake_rounded)
        else ...[
          const Text('Birthdays This Month 🎂', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...birthdays.map((b) {
            final mmdd = b['mm_dd'] as String? ?? '';
            final isToday = mmdd == todayMmdd;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isToday ? AppColors.primaryContainer : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isToday ? AppColors.primary : AppColors.divider),
              ),
              child: Row(
                children: [
                  const Text('🎂', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['name']}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isToday ? AppColors.primary : AppColors.textPrimary,
                          )),
                        if (b['phone'] != null && b['phone'].toString().isNotEmpty)
                          Text('${b['phone']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatMmdd(mmdd),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isToday ? AppColors.primary : AppColors.textSecondary,
                        )),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _formatMmdd(String mmdd) {
    final parts = mmdd.split('-');
    if (parts.length != 2) return mmdd;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final month = int.tryParse(parts[0]) ?? 1;
    return '${parts[1]} ${months[month - 1]}';
  }
}
