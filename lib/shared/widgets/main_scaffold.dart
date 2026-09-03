import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/customers')) return 1;
    if (location.startsWith('/reports')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0,
                  selected: currentIndex == 0, onTap: () => context.go('/')),
                _NavItem(icon: Icons.people_rounded, label: 'Customers', index: 1,
                  selected: currentIndex == 1, onTap: () => context.go('/customers')),
                // New Visit FAB-style center button
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/new-visit'),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 2),
                        const Text('New Visit',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
                _NavItem(icon: Icons.bar_chart_rounded, label: 'Reports', index: 3,
                  selected: currentIndex == 3, onTap: () => context.go('/reports')),
                _MoreNavItem(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                size: 24,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreNavItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _showMoreMenu(context),
        behavior: HitTestBehavior.opaque,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Icon(Icons.grid_view_rounded, size: 24, color: AppColors.textHint),
            ),
            SizedBox(height: 2),
            Text('More', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 20),
            const Text('More', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            _buildMenuGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    final items = [
      ('Services', Icons.spa_rounded, '/categories', AppColors.secondary),
      ('Packages', Icons.card_giftcard_rounded, '/packages', AppColors.accent),
      ('Appointments', Icons.event_rounded, '/appointments', AppColors.primary),
      ('Expenses', Icons.receipt_long_rounded, '/expenses', AppColors.warning),
      ('Pending', Icons.pending_actions_rounded, '/pending-payments', AppColors.error),
      ('Settings', Icons.settings_rounded, '/settings', AppColors.textSecondary),
      ('Backup', Icons.cloud_upload_rounded, '/backup-restore', AppColors.info),
    ];
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.1,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((item) => _buildMenuCard(context, item.$1, item.$2, item.$3, item.$4)).toList(),
    );
  }

  Widget _buildMenuCard(BuildContext context, String label, IconData icon, String route, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        context.push(route);
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
