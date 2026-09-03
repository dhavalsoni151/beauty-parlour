import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/package_models.dart';
import '../../core/providers/package_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Shows every package valid (active + within its start/expiry date range)
/// for [date] and lets the user pick one. Re-validates the pick before
/// returning it, per the "validate again when selecting" business rule.
/// Returns `null` if the user cancels or no valid packages exist.
Future<Package?> showPackagePickerSheet(BuildContext context, String date) async {
  final provider = context.read<PackageProvider>();
  final packages = await provider.getValidPackagesForDate(date);
  if (!context.mounted) return null;

  if (packages.isEmpty) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Packages Available'),
        content: Text(
          'There are no active packages valid for '
          '${AppFormatters.formatDate(DateTime.tryParse(date) ?? DateTime.now())}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return null;
  }

  return showModalBottomSheet<Package>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Package',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: packages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _PackageTile(
                      package: packages[i],
                      onTap: () => Navigator.pop(ctx, packages[i]),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _PackageTile extends StatelessWidget {
  final Package package;
  final VoidCallback onTap;
  const _PackageTile({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(package.startDate);
    final expiry = DateTime.tryParse(package.expiryDate);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(package.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (package.description != null && package.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(package.description!,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(AppFormatters.formatCurrency(package.normalTotal),
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint,
                    decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textHint),
                const SizedBox(width: 6),
                Text(AppFormatters.formatCurrency(package.packagePrice),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Save ${AppFormatters.formatCurrency(package.discount)} · '
              '${package.services.length} service${package.services.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
            if (start != null && expiry != null) ...[
              const SizedBox(height: 4),
              Text(
                'Valid: ${AppFormatters.formatDate(start)} to ${AppFormatters.formatDate(expiry)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
