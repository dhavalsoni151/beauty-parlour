import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/visit_provider.dart';
import '../../core/models/visit_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class VisitDetailScreen extends StatefulWidget {
  final int visitId;
  const VisitDetailScreen({super.key, required this.visitId});

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  Visit? _visit;
  List<WriteOff> _writeOffs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVisit();
  }

  Future<void> _loadVisit() async {
    setState(() => _isLoading = true);
    _visit = await context.read<VisitProvider>().getVisit(widget.visitId);
    if (_visit != null) {
      // load write-offs
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_visit == null) return const Scaffold(body: Center(child: Text('Visit not found')));
    final v = _visit!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Bill #${v.id}'),
        actions: [
          IconButton(
            onPressed: () async {
              final updated = await context.push<bool>('/new-visit?editVisitId=${v.id}');
              if (updated == true) _loadVisit();
            },
            icon: const Icon(Icons.edit_rounded, size: 20),
            tooltip: 'Edit visit',
          ),
          if (v.pendingAmount > 0)
            TextButton.icon(
              onPressed: () => _showPaymentDialog(v),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Receive'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Customer & date header
          _buildHeader(v),
          const SizedBox(height: 16),
          // Services
          _buildServicesCard(v),
          const SizedBox(height: 12),
          // Payment summary
          _buildPaymentSummary(v),
          const SizedBox(height: 12),
          // Payment history
          if (v.payments.isNotEmpty) _buildPaymentHistory(v),
          const SizedBox(height: 12),
          // Actions for pending
          if (v.paymentStatus == PaymentStatus.pending || v.paymentStatus == PaymentStatus.partiallyPaid)
            _buildPendingActions(v),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildHeader(Visit v) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.customerName ?? 'Unknown',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                if (v.customerPhone != null && v.customerPhone!.isNotEmpty)
                  Text(v.customerPhone!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 4),
                Text(AppFormatters.formatDateTime(DateTime.parse(v.visitDate)),
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ],
            ),
          ),
          PaymentStatusBadge(status: v.paymentStatus),
        ],
      ),
    );
  }

  Widget _buildServicesCard(Visit v) {
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
          const Text('Services', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...v.services.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(s.categoryNameSnapshot,
                    style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.serviceTypeNameSnapshot != null &&
                          s.serviceTypeNameSnapshot!.isNotEmpty)
                        Text(s.serviceTypeNameSnapshot!,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textHint)),
                      Text(s.serviceNameSnapshot,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                if (s.quantity > 1) Text('×${s.quantity} ', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                Text(AppFormatters.formatCurrency(s.total),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          )),
          const Divider(height: 12),
          Row(children: [
            const Expanded(child: Text('Subtotal', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            Text(AppFormatters.formatCurrency(v.subtotal),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
          if (v.discountAmount > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text('Discount (${v.discountType == DiscountType.percent ? "${v.discountValue.toInt()}%" : "fixed"})',
                style: const TextStyle(color: AppColors.success, fontSize: 13))),
              Text('- ${AppFormatters.formatCurrency(v.discountAmount)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ]),
          ],
          const Divider(height: 12),
          Row(children: [
            const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary))),
            Text(AppFormatters.formatCurrency(v.finalTotal),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary(Visit v) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _InfoRow('Bill Total', AppFormatters.formatCurrency(v.finalTotal)),
          const SizedBox(height: 6),
          _InfoRow('Paid', AppFormatters.formatCurrency(v.totalPaid),
            valueColor: v.totalPaid > 0 ? AppColors.success : AppColors.textSecondary),
          const SizedBox(height: 6),
          _InfoRow('Pending', AppFormatters.formatCurrency(v.pendingAmount),
            valueColor: v.pendingAmount > 0 ? AppColors.error : AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildPaymentHistory(Visit v) {
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
          const Text('Payment History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...v.payments.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.paymentMethod.label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(AppFormatters.formatDateTime(DateTime.parse(p.paymentDate)),
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ],
                )),
                Text(AppFormatters.formatCurrency(p.amount),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildPendingActions(Visit v) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showPaymentDialog(v),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Receive Payment'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showWriteOffDialog(v),
            icon: const Icon(Icons.money_off_rounded),
            label: const Text('Write Off'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.writtenOff,
              side: const BorderSide(color: AppColors.writtenOff),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPaymentDialog(Visit v) async {
    final amtCtrl = TextEditingController(text: v.pendingAmount.toStringAsFixed(0));
    PaymentMethod method = PaymentMethod.cash;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Receive Payment'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pending: ${AppFormatters.formatCurrency(v.pendingAmount)}',
                  style: const TextStyle(fontSize: 14, color: AppColors.error, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amtCtrl,
                  decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val <= 0) return 'Enter valid amount';
                    return null;
                  },
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
                final amount = double.parse(amtCtrl.text).clamp(0.0, v.pendingAmount);
                final newTotalPaid = v.totalPaid + amount;
                final newPending = (v.finalTotal - newTotalPaid).clamp(0.0, double.infinity);
                final payment = Payment(
                  visitId: v.id!,
                  paymentDate: DateTime.now().toIso8601String(),
                  amount: amount,
                  paymentMethod: method,
                );
                await context.read<VisitProvider>().recordPayment(v.id!, payment, newTotalPaid, newPending);
                Navigator.pop(ctx);
                _loadVisit();
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWriteOffDialog(Visit v) async {
    final reasonCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Off'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pending amount of ${AppFormatters.formatCurrency(v.pendingAmount)} will be written off.',
              style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason *'),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason')));
                return;
              }
              final wo = WriteOff(
                visitId: v.id!,
                amount: v.pendingAmount,
                writeOffDate: DateTime.now().toIso8601String(),
                reason: reasonCtrl.text.trim(),
              );
              await context.read<VisitProvider>().writeOffVisit(v.id!, wo, 0);
              Navigator.pop(ctx);
              _loadVisit();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.writtenOff),
            child: const Text('Write Off'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
          color: valueColor ?? AppColors.textPrimary)),
      ],
    );
  }
}
