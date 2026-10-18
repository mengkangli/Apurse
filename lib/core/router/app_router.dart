import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/transaction/presentation/transaction_list_screen.dart';
import '../../features/transaction/domain/transaction.dart';
import '../../features/transaction/presentation/add_transaction_screen.dart';
import '../../features/statistics/presentation/statistics_screen.dart';
import '../../features/budget/presentation/budget_list_screen.dart';
import '../../features/bill/presentation/bill_list_screen.dart';
import '../../features/category/presentation/category_management_screen.dart';
import '../../features/category/presentation/add_category_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/export_screen.dart';
import '../../features/budget/presentation/add_budget_screen.dart';
import '../../features/bill/presentation/add_bill_screen.dart';
import '../../features/ai_scan/presentation/ai_scan_screen.dart';
import '../../features/account/presentation/account_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../constants/app_colors.dart';
import '../constants/app_radius.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

part 'route_names.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              builder: (context, state) => const TransactionListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/statistics',
              builder: (context, state) => const StatisticsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

    // ── Push routes (above the shell) ────────────────────────────
    GoRoute(
      path: '/transaction/add',
      parentNavigatorKey: _rootNavigatorKey,
      // extra: a Transaction to edit, or a TransactionDraft to pre-fill.
      builder: (context, state) {
        final extra = state.extra;
        return AddTransactionScreen(
          editing: extra is Transaction ? extra : null,
          draft: extra is TransactionDraft ? extra : null,
        );
      },
    ),
    GoRoute(
      path: '/ai-scan',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AiScanScreen(),
    ),
    GoRoute(
      path: '/budgets',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BudgetListScreen(),
    ),
    GoRoute(
      path: '/budget/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AddBudgetScreen(),
    ),
    GoRoute(
      path: '/bills',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BillListScreen(),
    ),
    GoRoute(
      path: '/bill/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AddBillScreen(),
    ),
    GoRoute(
      path: '/accounts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountListScreen(),
    ),
    GoRoute(
      path: '/category/manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CategoryManagementScreen(),
    ),
    GoRoute(
      path: '/category/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AddCategoryScreen(),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/export',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ExportScreen(),
    ),
  ],
);

/// Top-level shell that hosts the 4 main tabs and the docked center FAB.
///
/// The FAB's primary action is "记一笔" (manual add) — single tap goes
/// straight to the add-transaction screen because that's what users want
/// 95% of the time. Long-press opens a sheet for AI scan / future voice
/// input — the secondary entry points that would otherwise compete for
/// the same surface.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  void _quickAdd(BuildContext context) {
    HapticFeedback.lightImpact();
    context.push('/transaction/add');
  }

  Future<void> _showQuickAddMenu(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _QuickAddSheet(
        onManual: () {
          Navigator.of(sheetCtx).pop();
          context.push('/transaction/add');
        },
        onAiScan: () {
          Navigator.of(sheetCtx).pop();
          context.push('/ai-scan');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      // Center FAB docked into the bottom bar's notch — Material standard
      // pattern. The bar is a 4-slot row split around the notch.
      floatingActionButton: _CenterFab(
        onTap: () => _quickAdd(context),
        onLongPress: () => _showQuickAddMenu(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomBar(
        currentIndex: navigationShell.currentIndex,
        onSelect: (branch) {
          navigationShell.goBranch(
            branch,
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

/// Bottom bar with a notch carved out for the centered FAB. Two tabs on
/// each side; the middle "slot" is purely visual whitespace owned by the
/// FAB itself.
class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _BottomBar({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BottomAppBar(
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      elevation: 0,
      padding: EdgeInsets.zero,
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            branch: 0,
            current: currentIndex,
            onTap: onSelect,
            iconOutlined: Icons.home_outlined,
            iconFilled: Icons.home_rounded,
            label: '首页',
          ),
          _NavItem(
            branch: 1,
            current: currentIndex,
            onTap: onSelect,
            iconOutlined: Icons.receipt_long_outlined,
            iconFilled: Icons.receipt_long_rounded,
            label: '流水',
          ),
          // Notch gap — FAB occupies this slot.
          const SizedBox(width: 64),
          _NavItem(
            branch: 2,
            current: currentIndex,
            onTap: onSelect,
            iconOutlined: Icons.bar_chart_outlined,
            iconFilled: Icons.bar_chart_rounded,
            label: '统计',
          ),
          _NavItem(
            branch: 3,
            current: currentIndex,
            onTap: onSelect,
            iconOutlined: Icons.person_outline_rounded,
            iconFilled: Icons.person_rounded,
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int branch;
  final int current;
  final ValueChanged<int> onTap;
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;

  const _NavItem({
    required this.branch,
    required this.current,
    required this.onTap,
    required this.iconOutlined,
    required this.iconFilled,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = current == branch;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return Expanded(
      child: InkResponse(
        onTap: () => onTap(branch),
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? iconFilled : iconOutlined,
                size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterFab extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _CenterFab({required this.onTap, required this.onLongPress});

  @override
  State<_CenterFab> createState() => _CenterFabState();
}

class _CenterFabState extends State<_CenterFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0,
    upperBound: 0.06,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final s = 1 - _ctrl.value;
          return Transform.scale(scale: s, child: child);
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary,
                Color.lerp(cs.primary, Colors.black, 0.10) ?? cs.primary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: AppColors.opacityAccentBorder),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 32),
        ),
      ),
    );
  }
}

/// Bottom-sheet shown on FAB long-press. Two big targets:
/// "AI 扫描收据" and "手动记账" — covers the cases the FAB-tap default
/// can't (camera shortcut, future voice input).
class _QuickAddSheet extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onAiScan;

  const _QuickAddSheet({required this.onManual, required this.onAiScan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: AppRadius.allXl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetAction(
                icon: Icons.edit_note_rounded,
                title: '手动记账',
                subtitle: '自己输入金额、分类、备注',
                onTap: onManual,
              ),
              Divider(
                  height: 1,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: cs.outlineVariant),
              _SheetAction(
                icon: Icons.document_scanner_rounded,
                title: 'AI 扫描收据',
                subtitle: '拍照或选图，自动识别',
                onTap: onAiScan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allLg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: AppColors.opacityMuted),
                borderRadius: AppRadius.allMd,
              ),
              child: Icon(icon, color: cs.primary),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleSmall),
                  AppSpacing.gapXs,
                  Text(subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
