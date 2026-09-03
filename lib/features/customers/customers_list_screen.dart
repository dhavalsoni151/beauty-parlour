import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/customer_provider.dart';
import '../../core/models/customer_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class CustomersListScreen extends StatefulWidget {
  const CustomersListScreen({super.key});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends State<CustomersListScreen> {
  bool _showInactive = false;

  Future<void> _loadCustomers() {
    return context.read<CustomerProvider>().loadCustomers(
          activeOnly: !_showInactive,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: Icon(
              _showInactive ? Icons.people_alt : Icons.people_outline,
            ),
            onPressed: () {
              setState(() => _showInactive = !_showInactive);
              _loadCustomers();
            },
            tooltip: _showInactive
                ? 'Hide inactive customers'
                : 'Show inactive customers',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppSearchBar(
              hint: 'Search by name or phone...',
              onChanged: (q) => context.read<CustomerProvider>().search(q),
            ),
          ),
          Expanded(
            child: Consumer<CustomerProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final customers = provider.customers;
                if (customers.isEmpty) {
                  return EmptyState(
                    title: 'No Customers Yet',
                    subtitle: 'Add your first customer to get started',
                    icon: Icons.people_rounded,
                    actionLabel: 'Add Customer',
                    onAction: () =>
                        context.push('/customer/new').then((_) => _loadCustomers()),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadCustomers,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _CustomerCard(customer: customers[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('/customer/new').then((_) => _loadCustomers()),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Customer'),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final initials = customer.name.trim().isNotEmpty
        ? customer.name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () => context.push('/customer/${customer.id}/profile'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(customer.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      if (!customer.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Inactive',
                            style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ),
                    ],
                  ),
                  if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(customer.phone!,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                  if (customer.notes != null && customer.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(customer.notes!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                  onPressed: () => context.push('/new-visit?customerId=${customer.id}'),
                  tooltip: 'New Visit',
                  visualDensity: VisualDensity.compact,
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
