import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/package_provider.dart';
import '../../core/database/daos/db_exceptions.dart';
import '../../core/models/package_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_widgets.dart';

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackageProvider>().loadPackages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Packages')),
      body: Consumer<PackageProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final packages = provider.packages;
          if (packages.isEmpty) {
            return EmptyState(
              title: 'No Packages Yet',
              subtitle: 'Bundle multiple services at a special price',
              icon: Icons.card_giftcard_rounded,
              actionLabel: 'Add Package',
              onAction: () => context.push('/package/new'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: packages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _PackageCard(package: packages[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/package/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Package'),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(package.startDate);
    final expiry = DateTime.tryParse(package.expiryDate);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(package.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                _StatusChip(isActive: package.isActive),
              ],
            ),
            if (package.description != null && package.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(package.description!,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 8),
            Text('${package.services.length} service${package.services.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(AppFormatters.formatCurrency(package.normalTotal),
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint, decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 8),
                Text(AppFormatters.formatCurrency(package.packagePrice),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const Spacer(),
                Text('Save ${AppFormatters.formatCurrency(package.discount)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
              ],
            ),
            if (start != null && expiry != null) ...[
              const SizedBox(height: 6),
              Text('Valid: ${AppFormatters.formatDate(start)} to ${AppFormatters.formatDate(expiry)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
            const Divider(height: 20),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => context.push('/package/${package.id}/edit'),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => context.read<PackageProvider>().toggleActive(package),
                  icon: Icon(package.isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16),
                  label: Text(package.isActive ? 'Deactivate' : 'Activate'),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                  onPressed: () => _delete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Package?'),
        content: Text('Are you sure you want to delete "${package.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<PackageProvider>().deletePackage(package);
    } on InUseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  final bool isActive;
  const _StatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(isActive ? 'Active' : 'Inactive',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
