import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/database/database.dart';
import '../../core/providers/appointment_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

/// All figures on this screen come from SQL aggregation in [ReportDao]
/// (COUNT/SUM/GROUP BY) — rows are never loaded into Dart and summed by hand.
class ReportsHomeScreen extends StatefulWidget {
  const ReportsHomeScreen({super.key});

  @override
  State<ReportsHomeScreen> createState() => _ReportsHomeScreenState();
}

class _ReportsHomeScreenState extends State<ReportsHomeScreen>
    with SingleTickerProviderStateMixin {
  final _reportDao = ReportDao();
  late TabController _tabController;

  DateRange _currentRange = DateRange.thisMonth();
  String _startDate = DateRange.thisMonth().start.toIso8601String();
  String _endDate = DateRange.thisMonth().endExclusive.toIso8601String();

  // Sort selections (kept distinct: Most Popular vs Highest Revenue vs Avg).
  String _serviceSort = 'revenue';
  String _customerSort = 'revenue';

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _topServices = [];
  List<Map<String, dynamic>> _topCategories = [];
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _paymentBreakdown = [];
  List<Map<String, dynamic>> _expenseByCategory = [];
  List<Map<String, dynamic>> _birthdays = [];
  Map<String, dynamic> _appointmentStats = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReports());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    _summary = await _reportDao.getDashboardStats(_startDate, _endDate);
    _topServices = await _reportDao.getTopServices(_startDate, _endDate,
        sort: _serviceSort, limit: 15);
    _topCategories = await _reportDao.getTopCategories(_startDate, _endDate,
        sort: _serviceSort);
    _topCustomers = await _reportDao.getTopCustomers(_startDate, _endDate,
        orderBy: _customerSort);
    _paymentBreakdown =
        await _reportDao.getPaymentMethodBreakdown(_startDate, _endDate);
    _expenseByCategory =
        await _reportDao.getExpenseByCategory(_startDate, _endDate);

    final now = DateTime.now();
    final mmdd1 = '${now.month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final mmdd2 =
        '${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    _birthdays = await _reportDao.getBirthdaysInRange(mmdd1, mmdd2);
    _appointmentStats =
        await context.read<AppointmentProvider>().getAppointmentStats(_currentRange);

    if (mounted) setState(() => _isLoading = false);
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
            Tab(text: 'Appointments'),
          ],
        ),
      ),
      body: Column(
        children: [
          DateRangeSelector(
            onRangeSelected: (s, e, label) {
              _currentRange = DateRange(
                start: DateTime.parse(s),
                end: DateTime.parse(e).subtract(const Duration(days: 1)),
                label: label,
              );
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
                _FinancialTab(
                    summary: _summary, paymentBreakdown: _paymentBreakdown),
                _ServicesTab(
                  topServices: _topServices,
                  topCategories: _topCategories,
                  sort: _serviceSort,
                  onSortChanged: (s) {
                    setState(() => _serviceSort = s);
                    _loadReports();
                  },
                  startDate: _startDate,
                  endDate: _endDate,
                ),
                _CustomersTab(
                  topCustomers: _topCustomers,
                  summary: _summary,
                  sort: _customerSort,
                  onSortChanged: (s) {
                    setState(() => _customerSort = s);
                    _loadReports();
                  },
                ),
                _ExpensesTab(
                    expenseByCategory: _expenseByCategory, summary: _summary),
                _BirthdaysTab(birthdays: _birthdays),
                _AppointmentsTab(stats: _appointmentStats),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared sort selector ──────────────────────────────────────────────────

class _SortChips extends StatelessWidget {
  final String value;
  final Map<String, String> options; // key -> label
  final ValueChanged<String> onChanged;

  const _SortChips(
      {required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.entries.map((e) {
          final selected = e.key == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: selected,
              onSelected: (_) => onChanged(e.key),
              backgroundColor: Colors.white,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
              side: BorderSide(
                  color: selected ? AppColors.primary : AppColors.divider),
            ),
          );
        }).toList(),
      ),
    );
  }
}

const _serviceSortOptions = {
  'revenue': 'Highest Revenue',
  'quantity': 'Most Popular',
  'avg': 'Highest Avg',
};

// ─── Financial Tab ─────────────────────────────────────────────────────────

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
    final profit = (summary['profit'] as num? ?? (collected - expenses)).toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
              const Text('Profit & Loss',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              _PLRow('Gross Billed', grossSales, AppColors.textPrimary,
                  isBold: true),
              _PLRow('Discounts', -discounts, AppColors.success),
              _PLRow('Net Sales', netSales, AppColors.textPrimary,
                  isDivider: true, isBold: true),
              _PLRow('Collected (cash in)', collected, AppColors.success,
                  isBold: true),
              _PLRow('Pending Receivable', pending, AppColors.error),
              _PLRow('Written Off', writtenOff, AppColors.writtenOff,
                  isDivider: true),
              _PLRow('Expenses', -expenses, AppColors.error, isDivider: true),
              _PLRow('Profit (collected − expenses)', profit,
                  profit >= 0 ? AppColors.success : AppColors.error,
                  isBold: true, isLarge: true),
              const SizedBox(height: 6),
              const Text(
                'Pending and written-off amounts are NOT counted as collected cash.',
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: StatCard(
              title: 'Total Bills',
              value: '${summary['visit_count'] ?? 0}',
              icon: Icons.receipt_rounded,
              color: AppColors.primary,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: StatCard(
              title: 'Avg Bill',
              value: (summary['visit_count'] as num? ?? 0) > 0
                  ? AppFormatters.formatCurrency(
                      netSales / (summary['visit_count'] as num).toDouble())
                  : '₹0',
              icon: Icons.analytics_rounded,
              color: AppColors.secondary,
            )),
          ],
        ),
        const SizedBox(height: 16),
        if (paymentBreakdown.isNotEmpty) ...[
          const Text('Payment Methods',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
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
                final color = AppColors
                    .chartColors[e.key % AppColors.chartColors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              _methodLabel(
                                  d['payment_method'] as String? ?? ''),
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary))),
                      Text(
                          AppFormatters.formatCurrency(
                              (d['total'] as num? ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color)),
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
      case 'CASH':
        return 'Cash';
      case 'UPI':
        return 'UPI';
      case 'CARD':
        return 'Card';
      case 'BANK_TRANSFER':
        return 'Bank Transfer';
      default:
        return 'Other';
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

  const _PLRow(this.label, this.value, this.color,
      {this.isDivider = false, this.isBold = false, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isDivider) const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: isLarge ? 15 : 13,
                        fontWeight:
                            isBold ? FontWeight.w700 : FontWeight.normal,
                        color: AppColors.textPrimary,
                      ))),
              Text(
                  value < 0
                      ? '- ${AppFormatters.formatCurrency(-value)}'
                      : AppFormatters.formatCurrency(value),
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

// ─── Services Tab (with drill-down) ────────────────────────────────────────

class _ServicesTab extends StatelessWidget {
  final List<Map<String, dynamic>> topServices;
  final List<Map<String, dynamic>> topCategories;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final String startDate;
  final String endDate;

  const _ServicesTab({
    required this.topServices,
    required this.topCategories,
    required this.sort,
    required this.onSortChanged,
    required this.startDate,
    required this.endDate,
  });

  double _metric(Map<String, dynamic> m) {
    switch (sort) {
      case 'quantity':
        return (m['quantity'] as num? ?? 0).toDouble();
      case 'avg':
        return (m['avg_price'] as num? ?? 0).toDouble();
      default:
        return (m['revenue'] as num? ?? 0).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SortChips(
            value: sort,
            options: _serviceSortOptions,
            onChanged: onSortChanged),
        const SizedBox(height: 14),
        if (topCategories.isEmpty)
          const EmptyState(
              title: 'No Data',
              subtitle: 'No visits in this period',
              icon: Icons.spa_rounded)
        else ...[
          const Text('Top Categories (tap to drill down)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...topCategories.asMap().entries.map((e) {
            final c = e.value;
            final color =
                AppColors.chartColors[e.key % AppColors.chartColors.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: ListTile(
                leading: Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                title: Text('${c['name']}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                subtitle: Text(
                    '${c['visits']} visits • ${c['quantity']} qty',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppFormatters.formatCurrency(_metric(c)),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color)),
                    const Icon(Icons.chevron_right, color: AppColors.textHint),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ServiceTypeDrillScreen(
                      categoryName: '${c['name']}',
                      startDate: startDate,
                      endDate: endDate,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text('Top Services (overall)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...topServices.asMap().entries.map((e) =>
              _ServiceRow(rank: e.key, data: e.value, metricSort: sort)),
        ],
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> data;
  final String metricSort;

  const _ServiceRow(
      {required this.rank, required this.data, required this.metricSort});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.chartColors[rank % AppColors.chartColors.length];
    final revenue = (data['revenue'] as num? ?? 0).toDouble();
    final qty = (data['quantity'] as num? ?? 0).toInt();
    final visits = (data['visits'] as num? ?? 0).toInt();
    final avg = (data['avg_price'] as num? ?? 0).toDouble();
    final path = [
      if ((data['category'] as String?)?.isNotEmpty ?? false) data['category'],
      if ((data['service_type'] as String?)?.isNotEmpty ?? false)
        data['service_type'],
      data['name'],
    ].join(' → ');
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
              Container(
                width: 22,
                height: 22,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(
                    child: Text('${rank + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(path,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary))),
              Text(AppFormatters.formatCurrency(revenue),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              '$visits visits • $qty qty • avg ${AppFormatters.formatCurrency(avg)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drill-down: service types within a category, then services within a type.
class _ServiceTypeDrillScreen extends StatefulWidget {
  final String categoryName;
  final String startDate;
  final String endDate;

  const _ServiceTypeDrillScreen({
    required this.categoryName,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<_ServiceTypeDrillScreen> createState() =>
      _ServiceTypeDrillScreenState();
}

class _ServiceTypeDrillScreenState extends State<_ServiceTypeDrillScreen> {
  final _reportDao = ReportDao();
  String _sort = 'revenue';
  List<Map<String, dynamic>> _types = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _types = await _reportDao.getTopServiceTypes(
      widget.startDate,
      widget.endDate,
      categoryName: widget.categoryName,
      sort: _sort,
    );
    if (mounted) setState(() => _loading = false);
  }

  double _metric(Map<String, dynamic> m) {
    switch (_sort) {
      case 'quantity':
        return (m['quantity'] as num? ?? 0).toDouble();
      case 'avg':
        return (m['avg_price'] as num? ?? 0).toDouble();
      default:
        return (m['revenue'] as num? ?? 0).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.categoryName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SortChips(
                    value: _sort,
                    options: _serviceSortOptions,
                    onChanged: (s) {
                      setState(() => _sort = s);
                      _load();
                    }),
                const SizedBox(height: 14),
                const Text('Service Types',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                if (_types.isEmpty)
                  const EmptyState(
                      title: 'No Data',
                      subtitle: 'No services billed in this period',
                      icon: Icons.spa_rounded)
                else
                  ..._types.asMap().entries.map((e) {
                    final t = e.value;
                    final isNoType = (t['is_no_type'] as num? ?? 0) == 1;
                    final color = AppColors
                        .chartColors[e.key % AppColors.chartColors.length];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        title: Text('${t['name']}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        subtitle: Text(
                            '${t['visits']} visits • ${t['quantity']} qty',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textHint)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(AppFormatters.formatCurrency(_metric(t)),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textHint),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ServiceListDrillScreen(
                              categoryName: widget.categoryName,
                              serviceTypeName:
                                  isNoType ? null : '${t['name']}',
                              serviceTypeIsNull: isNoType,
                              startDate: widget.startDate,
                              endDate: widget.endDate,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

/// Deepest drill level: services within (category [+ service type]).
class _ServiceListDrillScreen extends StatefulWidget {
  final String categoryName;
  final String? serviceTypeName;
  final bool serviceTypeIsNull;
  final String startDate;
  final String endDate;

  const _ServiceListDrillScreen({
    required this.categoryName,
    required this.serviceTypeName,
    required this.serviceTypeIsNull,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<_ServiceListDrillScreen> createState() =>
      _ServiceListDrillScreenState();
}

class _ServiceListDrillScreenState extends State<_ServiceListDrillScreen> {
  final _reportDao = ReportDao();
  String _sort = 'revenue';
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _services = await _reportDao.getTopServices(
      widget.startDate,
      widget.endDate,
      categoryName: widget.categoryName,
      serviceTypeName: widget.serviceTypeName,
      serviceTypeIsNull: widget.serviceTypeIsNull,
      sort: _sort,
      limit: 100,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.serviceTypeIsNull
        ? '${widget.categoryName} (No Type)'
        : '${widget.categoryName} → ${widget.serviceTypeName}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SortChips(
                    value: _sort,
                    options: _serviceSortOptions,
                    onChanged: (s) {
                      setState(() => _sort = s);
                      _load();
                    }),
                const SizedBox(height: 14),
                if (_services.isEmpty)
                  const EmptyState(
                      title: 'No Data',
                      subtitle: 'No services billed in this period',
                      icon: Icons.spa_rounded)
                else
                  ..._services.asMap().entries.map((e) =>
                      _ServiceRow(rank: e.key, data: e.value, metricSort: _sort)),
              ],
            ),
    );
  }
}

// ─── Customers Tab ─────────────────────────────────────────────────────────

class _CustomersTab extends StatelessWidget {
  final List<Map<String, dynamic>> topCustomers;
  final Map<String, dynamic> summary;
  final String sort;
  final ValueChanged<String> onSortChanged;

  const _CustomersTab({
    required this.topCustomers,
    required this.summary,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
                child: StatCard(
              title: 'New Customers',
              value: '${summary['new_customers'] ?? 0}',
              icon: Icons.person_add_rounded,
              color: AppColors.secondary,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: StatCard(
              title: 'Returning',
              value: '${summary['returning_customers'] ?? 0}',
              icon: Icons.replay_rounded,
              color: AppColors.info,
            )),
          ],
        ),
        const SizedBox(height: 16),
        _SortChips(
          value: sort,
          options: const {
            'revenue': 'Highest Spending',
            'visits': 'Most Frequent',
            'pending': 'Pending Balance',
            'written_off': 'Written Off',
          },
          onChanged: onSortChanged,
        ),
        const SizedBox(height: 14),
        if (topCustomers.isEmpty)
          const EmptyState(
              title: 'No Data',
              subtitle: 'No visits in this period',
              icon: Icons.people_rounded)
        else
          ...topCustomers.asMap().entries.map((e) {
            final c = e.value;
            final color =
                AppColors.chartColors[e.key % AppColors.chartColors.length];
            final pending = (c['pending'] as num? ?? 0).toDouble();
            final writtenOff = (c['written_off'] as num? ?? 0).toDouble();
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [color.withOpacity(0.7), color]),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                        child: Text('${e.key + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['name']}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        Text(
                            '${c['visit_count']} visits • Last: ${c['last_visit'] != null ? AppFormatters.formatDate(DateTime.parse(c['last_visit'] as String)) : 'Never'}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textHint)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                          AppFormatters.formatCurrency(
                              (c['collected'] as num? ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      if (pending > 0)
                        Text(
                            'Pending: ${AppFormatters.formatCurrency(pending)}',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.error)),
                      if (writtenOff > 0)
                        Text(
                            'W/off: ${AppFormatters.formatCurrency(writtenOff)}',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.writtenOff)),
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

// ─── Expenses Tab ──────────────────────────────────────────────────────────

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
          const EmptyState(
              title: 'No Expenses',
              subtitle: 'No expenses in this period',
              icon: Icons.receipt_rounded)
        else ...[
          const Text('By Category',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...expenseByCategory.asMap().entries.map((e) {
            final c = e.value;
            final amount = (c['total'] as num? ?? 0).toDouble();
            final color =
                AppColors.chartColors[e.key % AppColors.chartColors.length];
            final pct = total > 0 ? amount / total : 0.0;
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
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('${c['name']}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary))),
                      Text(AppFormatters.formatCurrency(amount),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      const SizedBox(width: 6),
                      Text('${(pct * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
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

// ─── Birthdays Tab ─────────────────────────────────────────────────────────

class _BirthdaysTab extends StatelessWidget {
  final List<Map<String, dynamic>> birthdays;

  const _BirthdaysTab({required this.birthdays});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMmdd =
        '${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (birthdays.isEmpty)
          const EmptyState(
              title: 'No Birthdays',
              subtitle: 'No customer birthdays this month',
              icon: Icons.cake_rounded)
        else ...[
          const Text('Birthdays This Month 🎂',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
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
                border: Border.all(
                    color: isToday ? AppColors.primary : AppColors.divider),
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
                              color: isToday
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            )),
                        if (b['phone'] != null &&
                            b['phone'].toString().isNotEmpty)
                          Text('${b['phone']}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
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
                            color: isToday
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          )),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('TODAY',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = int.tryParse(parts[0]) ?? 1;
    return '${parts[1]} ${months[month - 1]}';
  }
}


class _AppointmentsTab extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _AppointmentsTab({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = (stats['total_appointments'] as num? ?? 0).toInt();
    final pending = (stats['pending_count'] as num? ?? 0).toInt();
    final completed = (stats['completed_count'] as num? ?? 0).toInt();
    final notAttended = (stats['not_attended_count'] as num? ?? 0).toInt();
    final cancelled = (stats['cancelled_count'] as num? ?? 0).toInt();
    final completionRate = ((stats['completion_rate'] as num? ?? 0).toDouble() * 100);
    final resolvedRate = ((stats['resolved_completion_rate'] as num? ?? 0).toDouble() * 100);
    final cancellationRate = ((stats['cancellation_rate'] as num? ?? 0).toDouble() * 100);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Total Appointments',
                value: '$total',
                icon: Icons.event_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Pending',
                value: '$pending',
                icon: Icons.schedule_rounded,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Completed',
                value: '$completed',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Cancelled',
                value: '$cancelled',
                icon: Icons.event_busy_rounded,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatCard(
          title: 'Not Attended',
          value: '$notAttended',
          icon: Icons.person_off_rounded,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
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
              const Text(
                'Appointment Summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _SummaryLine('Completion rate', '${completionRate.toStringAsFixed(1)}%'),
              _SummaryLine('Resolved completion rate', '${resolvedRate.toStringAsFixed(1)}%'),
              _SummaryLine('Cancellation rate', '${cancellationRate.toStringAsFixed(1)}%'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
