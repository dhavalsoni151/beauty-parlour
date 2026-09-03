import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/daos/reminder_dao.dart';
import '../../core/models/reminder_models.dart';
import '../../core/models/visit_models.dart';
import '../../core/providers/category_provider.dart';
import '../../core/providers/reminder_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _daysCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<CategoryProvider>().loadCategories();
      final provider = context.read<ReminderProvider>();
      await provider.loadSettings();
      _daysCtrl.text = '${provider.daysSinceVisit}';
      _amountCtrl.text = provider.minAmount.toStringAsFixed(0);
      await provider.search();
    });
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parlourName = context.watch<SettingsProvider>().parlourName;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Customer Reminders'),
        actions: [
          IconButton(
            tooltip: 'Reminder settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: Consumer<ReminderProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildSearchCard(provider),
                    const SizedBox(height: 12),
                    _buildFilterCard(provider),
                    const SizedBox(height: 12),
                    _buildResultsHeader(provider),
                    const SizedBox(height: 8),
                    if (provider.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!provider.hasSearched)
                      const _HintCard()
                    else if (provider.candidates.isEmpty)
                      _EmptyResults(neverVisited: provider.showNeverVisited)
                    else
                      ...provider.candidates.map(
                        (c) => _CustomerCard(
                          candidate: c,
                          selected: provider.selectedIds.contains(c.customer.id),
                          onToggle: () => provider.toggleSelect(c.customer.id),
                          onWhatsApp: () => _openPreview(c),
                        ),
                      ),
                  ],
                ),
              ),
              _buildFooter(provider),
            ],
          );
        },
      ),
    );
  }

  // ── Search card ──────────────────────────────────────────────────────────

  Widget _buildSearchCard(ReminderProvider provider) {
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
          const Text('Find customers to remind',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _daysCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Not visited for (days)',
                    helperText: 'Customers who have not visited for',
                    suffixText: 'Days',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !provider.showNeverVisited,
                  decoration: const InputDecoration(
                    labelText: 'Min. last visit amount',
                    helperText: 'Latest visit bill ≥ this amount',
                    prefixText: '₹ ',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _runSearch(provider),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search'),
            ),
          ),
        ],
      ),
    );
  }

  void _runSearch(ReminderProvider provider) {
    final days = int.tryParse(_daysCtrl.text.trim()) ?? provider.daysSinceVisit;
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    provider.setDaysSinceVisit(days);
    provider.setMinAmount(amount);
    provider.search();
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _buildFilterCard(ReminderProvider provider) {
    final categories = context.watch<CategoryProvider>().categories;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Never-visited toggle.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: provider.showNeverVisited,
            activeColor: AppColors.primary,
            title: const Text('Customers With No Visit',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: const Text('Show customers who have never visited (separate list)',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onChanged: (v) => provider.setShowNeverVisited(v),
          ),
          if (!provider.showNeverVisited) ...[
            const Divider(height: 16),
            // Days quick chips
            _chipRow(
              label: 'Days since visit',
              values: const [15, 25, 30, 45, 60, 90],
              isSelected: (v) => provider.daysSinceVisit == v,
              labelOf: (v) => '$v+',
              onPick: (v) {
                _daysCtrl.text = '$v';
                provider.setDaysSinceVisit(v);
                provider.search();
              },
            ),
            const SizedBox(height: 8),
            // Amount quick chips
            _chipRow(
              label: 'Min. amount',
              values: const [0, 300, 500, 1000],
              isSelected: (v) => provider.minAmount == v.toDouble(),
              labelOf: (v) => v == 0 ? '₹0' : '₹$v',
              onPick: (v) {
                _amountCtrl.text = '$v';
                provider.setMinAmount(v.toDouble());
                provider.search();
              },
            ),
            const SizedBox(height: 8),
            // Category + package
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: provider.categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All')),
                      ...categories.map((c) =>
                          DropdownMenuItem<int?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) {
                      provider.setCategory(v);
                      provider.search();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<bool?>(
                    initialValue: provider.packageUsed,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Package', isDense: true),
                    items: const [
                      DropdownMenuItem<bool?>(value: null, child: Text('All')),
                      DropdownMenuItem<bool?>(value: true, child: Text('Package Used')),
                      DropdownMenuItem<bool?>(value: false, child: Text('No Package')),
                    ],
                    onChanged: (v) {
                      provider.setPackageUsed(v);
                      provider.search();
                    },
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 16),
          // Sort
          Row(
            children: [
              const Icon(Icons.sort_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text('Sort by',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<ReminderSort>(
                  initialValue: provider.sort,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  items: const [
                    DropdownMenuItem(value: ReminderSort.daysDesc, child: Text('Days Since Visit (Highest First)')),
                    DropdownMenuItem(value: ReminderSort.dateAsc, child: Text('Last Visit Date (Oldest First)')),
                    DropdownMenuItem(value: ReminderSort.amountDesc, child: Text('Last Visit Amount (Highest First)')),
                    DropdownMenuItem(value: ReminderSort.nameAsc, child: Text('Customer Name (A–Z)')),
                  ],
                  onChanged: (v) {
                    if (v != null) provider.setSort(v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipRow<T>({
    required String label,
    required List<T> values,
    required bool Function(T) isSelected,
    required String Function(T) labelOf,
    required void Function(T) onPick,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: values.map((v) {
                final selected = isSelected(v);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(labelOf(v)),
                    selected: selected,
                    onSelected: (_) => onPick(v),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Results header / footer ───────────────────────────────────────────────

  Widget _buildResultsHeader(ReminderProvider provider) {
    if (!provider.hasSearched || provider.candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Checkbox(
          value: provider.allSelected,
          tristate: provider.selectedIds.isNotEmpty && !provider.allSelected,
          activeColor: AppColors.primary,
          onChanged: (v) {
            if (provider.allSelected) {
              provider.clearSelection();
            } else {
              provider.selectAll();
            }
          },
        ),
        GestureDetector(
          onTap: () =>
              provider.allSelected ? provider.clearSelection() : provider.selectAll(),
          child: const Text('Select All',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        const Spacer(),
        Text('${provider.candidates.length} found',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildFooter(ReminderProvider provider) {
    final selected = provider.selectedCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('$selected Customer${selected == 1 ? '' : 's'} Selected',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: selected == 0 ? null : () => _startBulkReminders(provider),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send WhatsApp Reminder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.divider,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WhatsApp / preview flow ───────────────────────────────────────────────

  Future<void> _openPreview(ReminderCandidate c) async {
    final provider = context.read<ReminderProvider>();
    final parlourName = context.read<SettingsProvider>().parlourName;
    await provider.recordActivity(c, ReminderStatus.previewed);
    if (!mounted) return;
    await _showMessageSheet(
      candidate: c,
      initialMessage: provider.renderMessage(c, parlourName: parlourName),
      stepLabel: null,
    );
  }

  /// Walks through each selected customer one by one: preview/edit → share to
  /// WhatsApp (manual send) → next. Nothing is sent automatically.
  Future<void> _startBulkReminders(ReminderProvider provider) async {
    final selected = provider.selectedCandidates;
    if (selected.isEmpty) return;
    final parlourName = context.read<SettingsProvider>().parlourName;

    for (var i = 0; i < selected.length; i++) {
      final c = selected[i];
      await provider.recordActivity(c, ReminderStatus.previewed);
      if (!mounted) return;
      final proceed = await _showMessageSheet(
        candidate: c,
        initialMessage: provider.renderMessage(c, parlourName: parlourName),
        stepLabel: 'Customer ${i + 1} of ${selected.length}',
        isLast: i == selected.length - 1,
      );
      if (proceed != true) break; // user stopped the flow
    }
    if (mounted) {
      provider.clearSelection();
      provider.search(); // refresh so suppression takes effect
    }
  }

  /// Shows the editable message preview sheet. Returns true if the user chose
  /// to open WhatsApp (and, in a bulk flow, continue to the next customer).
  Future<bool?> _showMessageSheet({
    required ReminderCandidate candidate,
    required String initialMessage,
    String? stepLabel,
    bool isLast = true,
  }) {
    final provider = context.read<ReminderProvider>();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _MessagePreviewSheet(
        candidate: candidate,
        initialMessage: initialMessage,
        stepLabel: stepLabel,
        isLast: isLast,
        onOpenWhatsApp: (message) async {
          await provider.recordActivity(candidate, ReminderStatus.opened);
          await Share.share(message, subject: 'Reminder');
        },
        onDismiss: () async {
          await provider.recordActivity(candidate, ReminderStatus.dismissed);
        },
      ),
    );
  }

  // ── Settings sheet ────────────────────────────────────────────────────────

  void _openSettingsSheet() {
    final provider = context.read<ReminderProvider>();
    final suppressCtrl = TextEditingController(text: '${provider.suppressWithinDays}');
    final templateCtrl = TextEditingController(text: provider.messageTemplate);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reminder Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: suppressCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Do not show customers contacted within (days)',
                  helperText: 'Hide customers reminded in the last X days (0 = off)',
                  suffixText: 'Days',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: templateCtrl,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Message template',
                  helperText:
                      'Variables: {customer_name} {days_since_visit} {last_visit_date} {visit_amount} {services} {parlour_name}',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () async {
                    final days = int.tryParse(suppressCtrl.text.trim()) ?? 15;
                    await provider.setSuppressWithinDays(days);
                    final template = templateCtrl.text.trim();
                    if (template.isNotEmpty) {
                      await provider.setMessageTemplate(template);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    provider.search();
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatefulWidget {
  final ReminderCandidate candidate;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onWhatsApp;

  const _CustomerCard({
    required this.candidate,
    required this.selected,
    required this.onToggle,
    required this.onWhatsApp,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.selected ? AppColors.primary : AppColors.divider,
          width: widget.selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.selected,
                activeColor: AppColors.primary,
                onChanged: (_) => widget.onToggle(),
              ),
              Expanded(
                child: Text(c.customer.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (c.hasPackage)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('PACKAGE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accent)),
                ),
            ],
          ),
          if (c.hasVisit) ...[
            _infoRow('Last Visit', AppFormatters.formatDate(c.lastVisitDate!)),
            _infoRow('Amount', AppFormatters.formatCurrency(c.lastVisitAmount ?? 0)),
            _infoRow('Days Since Visit', '${c.daysSinceVisit}'),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Never visited',
                  style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600)),
            ),
          if (c.hasPackage) ...[
            const SizedBox(height: 6),
            _packageBlock(c),
          ],
          if (c.services.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Services:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            ...c.services.map((s) => Padding(
                  padding: const EdgeInsets.only(left: 4, top: 1),
                  child: Text('• ${s.pathLabel} — ${AppFormatters.formatCurrency(s.total)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                )),
          ],
          if (c.hasVisit) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text('Last Visit Details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    Icon(Icons.expand_more, size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            ),
            if (_expanded) _buildDetails(c),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => context.push('/customer/${c.customer.id}/profile'),
                icon: const Icon(Icons.person_rounded, size: 16),
                label: const Text('View Customer'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: EdgeInsets.zero),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: widget.onWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 16),
                label: const Text('WhatsApp'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF25D366), padding: EdgeInsets.zero),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => context.push('/appointment/new?customerId=${c.customer.id}'),
                icon: const Icon(Icons.event_available_rounded, size: 16),
                label: const Text('Book'),
                style: TextButton.styleFrom(foregroundColor: AppColors.secondary, padding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _packageBlock(ReminderCandidate c) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.accentLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Package: ${c.packageName ?? 'Package'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          _pkgRow('Normal Service Value', c.packageNormalTotal ?? 0, strike: true),
          _pkgRow('Package Price', c.packagePrice ?? 0, bold: true),
          _pkgRow('Package Discount', c.packageDiscount ?? 0, color: AppColors.success),
          if ((c.visitTotalPaid ?? 0) > 0) _pkgRow('Paid', c.visitTotalPaid ?? 0),
        ],
      ),
    );
  }

  Widget _pkgRow(String label, double value, {bool strike = false, bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Text(AppFormatters.formatCurrency(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? AppColors.textPrimary,
              decoration: strike ? TextDecoration.lineThrough : null,
            )),
      ],
    );
  }

  Widget _buildDetails(ReminderCandidate c) {
    // Group services by category → type for the expandable "Last Visit Details".
    final Map<String, List<VisitService>> byCategory = {};
    for (final s in c.services) {
      final cat = s.categoryNameSnapshot.isEmpty ? 'Services' : s.categoryNameSnapshot;
      byCategory.putIfAbsent(cat, () => []).add(s);
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppFormatters.formatDate(c.lastVisitDate!),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Divider(height: 12),
          ...byCategory.entries.map((entry) {
            // Sub-group by service type (skip a blank level).
            final Map<String, List<VisitService>> byType = {};
            for (final s in entry.value) {
              final type = (s.serviceTypeNameSnapshot ?? '').isEmpty ? '' : s.serviceTypeNameSnapshot!;
              byType.putIfAbsent(type, () => []).add(s);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                  ...byType.entries.map((te) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (te.key.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Text(te.key,
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                            ),
                          ...te.value.map((s) => Padding(
                                padding: EdgeInsets.only(left: te.key.isEmpty ? 8 : 16, top: 1),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                          '${s.serviceNameSnapshot}${s.quantity > 1 ? ' ×${s.quantity}' : ''}',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                                    ),
                                    Text(AppFormatters.formatCurrency(s.total),
                                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                                  ],
                                ),
                              )),
                        ],
                      )),
                ],
              ),
            );
          }),
          const Divider(height: 12),
          _pkgRow('Visit Total', c.lastVisitAmount ?? 0, bold: true),
          _pkgRow('Paid', c.visitTotalPaid ?? 0),
          _pkgRow('Pending', c.visitPendingAmount ?? 0,
              color: (c.visitPendingAmount ?? 0) > 0 ? AppColors.error : null),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ── Message preview sheet ─────────────────────────────────────────────────────

class _MessagePreviewSheet extends StatefulWidget {
  final ReminderCandidate candidate;
  final String initialMessage;
  final String? stepLabel;
  final bool isLast;
  final Future<void> Function(String message) onOpenWhatsApp;
  final Future<void> Function() onDismiss;

  const _MessagePreviewSheet({
    required this.candidate,
    required this.initialMessage,
    required this.stepLabel,
    required this.isLast,
    required this.onOpenWhatsApp,
    required this.onDismiss,
  });

  @override
  State<_MessagePreviewSheet> createState() => _MessagePreviewSheetState();
}

class _MessagePreviewSheetState extends State<_MessagePreviewSheet> {
  late TextEditingController _msgCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.stepLabel != null)
              Text(widget.stepLabel!,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Message for ${c.customer.name}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if ((c.customer.phone ?? '').isNotEmpty)
              Text(c.customer.phone!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Message (edit before sending)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Opens WhatsApp — you press Send there. Nothing is sent automatically.',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            await widget.onDismiss();
                            if (mounted) Navigator.pop(context, false);
                          },
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _sending
                        ? null
                        : () async {
                            setState(() => _sending = true);
                            await widget.onOpenWhatsApp(_msgCtrl.text.trim());
                            if (mounted) Navigator.pop(context, true);
                          },
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(widget.isLast ? 'Open WhatsApp' : 'Open WhatsApp & Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small placeholders ────────────────────────────────────────────────────────

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text('Set the filters above and tap Search to find customers to remind.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final bool neverVisited;
  const _EmptyResults({required this.neverVisited});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          neverVisited
              ? 'Every customer has visited at least once.'
              : 'No customers match these filters right now.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
