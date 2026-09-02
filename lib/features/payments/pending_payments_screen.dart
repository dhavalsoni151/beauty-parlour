import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/models/visit_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({super.key});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VisitProvider>().loadPendingVisits();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pending Payments')),
      body: Consumer<VisitProvider>(
        builder: (context, provider, _) {
          final visits = provider.pendingVisits;
          final totalPending = visits.fold(0.0, (s, v) => s + v.pendingAmount);

          return Column(
            children: [
              // Total pending header
              if (visits.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFC62828), Color(0xFFE53935)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions_rounded, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Pending', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(AppFormatters.formatCurrency(totalPending),
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const Spacer(),
                      Text('${visits.length} bills', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),

              Expanded(
                child: visits.isEmpty
                    ? const EmptyState(
                        title: 'No Pending Payments',
                        subtitle: 'All payments are up to date!',
                        icon: Icons.check_circle_rounded,
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: () => provider.loadPendingVisits(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          itemCount: visits.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _PendingCard(
                            visit: visits[i],
                            onRefresh: () => provider.loadPendingVisits(),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Visit visit;
  final VoidCallback onRefresh;

  const _PendingCard({required this.visit, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/visit/${visit.id}').then((_) => onRefresh()),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(visit.customerName ?? 'Unknown',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text(AppFormatters.formatDate(DateTime.parse(visit.visitDate)),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                PaymentStatusBadge(status: visit.paymentStatus),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MiniStat('Bill', AppFormatters.formatCurrency(visit.finalTotal), AppColors.textPrimary),
                _MiniStat('Paid', AppFormatters.formatCurrency(visit.totalPaid), AppColors.success),
                _MiniStat('Pending', AppFormatters.formatCurrency(visit.pendingAmount), AppColors.error),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showPaymentDialog(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Receive'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showWriteOffDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.writtenOff,
                    side: const BorderSide(color: AppColors.writtenOff),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Write Off', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(BuildContext context) async {
    final amtCtrl = TextEditingController(text: visit.pendingAmount.toStringAsFixed(0));
    PaymentMethod method = PaymentMethod.cash;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Receive from ${visit.customerName}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pending: ${AppFormatters.formatCurrency(visit.pendingAmount)}',
                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amtCtrl,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'Payment Method'),
                  items: PaymentMethodX.all.map((m) =>
                    DropdownMenuItem(value: m, child: Text(m.label))).toList(),
                  onChanged: (m) => setState(() => method = m!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.parse(amtCtrl.text).clamp(0.0, visit.pendingAmount);
                final newPaid = visit.totalPaid + amount;
                final newPending = (visit.finalTotal - newPaid).clamp(0.0, double.infinity);
                final payment = Payment(
                  visitId: visit.id!,
                  paymentDate: DateTime.now().toIso8601String(),
                  amount: amount,
                  paymentMethod: method,
                );
                await context.read<VisitProvider>().recordPayment(visit.id!, payment, newPaid, newPending);
                Navigator.pop(ctx);
                onRefresh();
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWriteOffDialog(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Off'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Write off ${AppFormatters.formatCurrency(visit.pendingAmount)} pending from ${visit.customerName}?',
              style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason *'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              final wo = WriteOff(
                visitId: visit.id!,
                amount: visit.pendingAmount,
                writeOffDate: DateTime.now().toIso8601String(),
                reason: reasonCtrl.text.trim(),
              );
              await context.read<VisitProvider>().writeOffVisit(visit.id!, wo, 0);
              Navigator.pop(ctx);
              onRefresh();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.writtenOff),
            child: const Text('Write Off'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
