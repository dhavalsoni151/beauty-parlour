import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/reminder_models.dart';
import '../../core/models/visit_models.dart';
import '../../core/database/daos/reminder_dao.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class CustomerProfileScreen extends StatefulWidget {
  final int customerId;
  const CustomerProfileScreen({super.key, required this.customerId});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  Customer? _customer;
  Map<String, dynamic>? _stats;
  List<Visit> _visits = [];
  List<Reminder> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _customer = await context.read<CustomerProvider>().getCustomer(widget.customerId);
    _stats = await context.read<CustomerProvider>().getCustomerStats(widget.customerId);
    _visits = await context.read<VisitProvider>().getVisitsForCustomer(widget.customerId);
    // Load services for each visit
    for (final v in _visits) {
      v.services = await context.read<VisitProvider>().getVisit(v.id!).then((full) => full?.services ?? []);
    }
    _reminders = await ReminderDao().getForCustomer(widget.customerId);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_customer == null) {
      return const Scaffold(body: Center(child: Text('Customer not found')));
    }

    final initials = _customer!.name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    final totalVisits = (_stats?['total_visits'] as num? ?? 0).toInt();
    final totalBilled = (_stats?['total_billed'] as num? ?? 0).toDouble();
    final totalPaid = (_stats?['total_paid'] as num? ?? 0).toDouble();
    final totalPending = (_stats?['total_pending'] as num? ?? 0).toDouble();
    final lastVisit = _stats?['last_visit'] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(child: Text(initials,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(height: 8),
                      Text(_customer!.name,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      if (_customer!.phone != null && _customer!.phone!.isNotEmpty)
                        Text(_customer!.phone!,
                          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => context.push('/customer/${widget.customerId}/edit').then((_) => _loadData()),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded),
                onPressed: () => context.push('/new-visit?customerId=${widget.customerId}').then((_) => _loadData()),
                tooltip: 'New Visit',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  _buildStatsRow(totalVisits, totalBilled, totalPaid, totalPending, lastVisit),
                  const SizedBox(height: 20),

                  // Reminder / marketing activity
                  if (_reminders.isNotEmpty) ...[
                    SectionHeader(title: 'Reminder History (${_reminders.length})'),
                    const SizedBox(height: 12),
                    ..._reminders.map((r) => _ReminderHistoryTile(reminder: r)),
                    const SizedBox(height: 20),
                  ],

                  // Visit history
                  SectionHeader(title: 'Visit History (${_visits.length})'),
                  const SizedBox(height: 12),
                  if (_visits.isEmpty)
                    EmptyState(
                      title: 'No Visits Yet',
                      subtitle: 'Start a new visit for this customer',
                      icon: Icons.spa_rounded,
                      actionLabel: 'New Visit',
                      onAction: () => context.push('/new-visit?customerId=${widget.customerId}'),
                    )
                  else
                    ..._visits.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _VisitHistoryCard(visit: v),
                    )),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int totalVisits, double totalBilled, double totalPaid, double totalPending, String? lastVisit) {
    return Column(
      children: [
        Row(
          children: [
            _StatTile('Total Visits', '$totalVisits', Icons.spa_rounded, AppColors.primary),
            const SizedBox(width: 12),
            _StatTile('Total Billed', AppFormatters.formatCurrency(totalBilled), Icons.receipt_rounded, AppColors.secondary),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatTile('Total Paid', AppFormatters.formatCurrency(totalPaid), Icons.payments_rounded, AppColors.success),
            const SizedBox(width: 12),
            _StatTile('Pending', AppFormatters.formatCurrency(totalPending),
              Icons.pending_actions_rounded,
              totalPending > 0 ? AppColors.error : AppColors.textHint,
            ),
          ],
        ),
        if (lastVisit != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 8),
                const Text('Last Visit', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const Spacer(),
                Text(AppFormatters.formatDate(DateTime.parse(lastVisit)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ReminderHistoryTile extends StatelessWidget {
  final Reminder reminder;
  const _ReminderHistoryTile({required this.reminder});

  Color get _color {
    switch (reminder.status) {
      case ReminderStatus.opened:
        return AppColors.success;
      case ReminderStatus.previewed:
        return AppColors.info;
      case ReminderStatus.dismissed:
        return AppColors.textHint;
      case ReminderStatus.suggested:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.notifications_active_rounded, size: 18, color: _color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.status.label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(reminder.reason ?? 'Reminder',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(AppFormatters.formatDate(DateTime.parse(reminder.reminderDate)),
              style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
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
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _VisitHistoryCard extends StatelessWidget {
  final Visit visit;
  const _VisitHistoryCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/visit/${visit.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(AppFormatters.formatDate(DateTime.parse(visit.visitDate)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const Spacer(),
                PaymentStatusBadge(status: visit.paymentStatus),
              ],
            ),
            const SizedBox(height: 10),
            // Service list
            ...visit.services.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(s.serviceNameSnapshot,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                  Text(AppFormatters.formatCurrency(s.total),
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            )),
            if (visit.discountAmount > 0) ...[
              const Divider(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('Discount',
                    style: TextStyle(fontSize: 13, color: AppColors.success))),
                  Text('- ${AppFormatters.formatCurrency(visit.discountAmount)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const Divider(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Total',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                Text(AppFormatters.formatCurrency(visit.finalTotal),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ],
            ),
            if (visit.pendingAmount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(child: Text('Pending',
                    style: TextStyle(fontSize: 12, color: AppColors.error))),
                  Text(AppFormatters.formatCurrency(visit.pendingAmount),
                    style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
