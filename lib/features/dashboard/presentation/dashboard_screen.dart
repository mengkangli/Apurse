import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_elevation.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/shell_tab_scaffold.dart';
import '../../../shared/providers/category_list_provider.dart';
import '../../../shared/providers/selected_month_provider.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../bill/domain/bill.dart';
import '../../bill/domain/bill_repository.dart';
import '../../budget/domain/budget.dart';
import '../../budget/domain/budget_repository.dart';
import '../../category/domain/category.dart';
import '../../transaction/domain/transaction.dart';
import '../../transaction/domain/transaction_repository.dart';

final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  ref.watch(transactionChangeProvider);
  final txRepo = TransactionRepository();
  final billRepo = BillRepository();
  final budgetRepo = BudgetRepository();

  final results = await Future.wait([
    txRepo.sumByMonth(month.year, month.month, 'income'),
    txRepo.sumByMonth(month.year, month.month, 'expense'),
    txRepo.getRecent(limit: 5),
    billRepo.getUpcoming(days: 7),
    budgetRepo.getByMonth(month.year, month.month),
  ]);

  return DashboardSummary(
    totalIncome: (results[0] as double),
    totalExpense: (results[1] as double),
    balance: (results[0] as double) - (results[1] as double),
    recentTransactions: results[2] as List<Transaction>,
    upcomingBills: results[3] as List<Bill>,
    budgets: results[4] as List<Budget>,
  );
});

class DashboardSummary {
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final List<Transaction> recentTransactions;
  final List<Bill> upcomingBills;
  final List<Budget> budgets;

  const DashboardSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.recentTransactions,
    required this.upcomingBills,
    required this.budgets,
  });

  /// Aggregated budget utilisation across categories (0..1+, capped at 1.5
  /// when exceeded so the % display reads sanely). Returns null when no
  /// budgets are set so the UI can fall back to a different message.
  double? get overallBudgetUsage {
    if (budgets.isEmpty) return null;
    final totalLimit = budgets.fold<double>(0, (s, b) => s + b.amount);
    if (totalLimit <= 0) return null;
    final totalSpent = budgets.fold<double>(0, (s, b) => s + b.spent);
    return (totalSpent / totalLimit).clamp(0.0, 1.5);
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final categoriesAsync = ref.watch(sharedCategoryListProvider);

    return ShellTabScaffold(
      title: Text(DateFormat('yyyy年M月', 'zh_CN').format(month)),
      actions: [
        IconButton(
          icon: const Icon(Icons.document_scanner_outlined),
          tooltip: 'AI 扫描记账',
          onPressed: () async {
            await context.push('/ai-scan');
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(sharedCategoryListProvider);
          },
        ),
      ],
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(
          onRetry: () => ref.invalidate(dashboardSummaryProvider),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
          child: CustomScrollView(
            // Bottom padding clears the FAB + bottom bar so the last item
            // isn't hidden behind them.
            slivers: [
              const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.sm)),
              SliverToBoxAdapter(child: _HeroBalance(summary: summary)),
              const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.lg)),
              SliverToBoxAdapter(child: _IncomeExpenseRow(summary: summary)),
              const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.lg)),
              SliverToBoxAdapter(child: _SmartInsight(summary: summary)),
              const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.lg)),
              SliverToBoxAdapter(
                child: _QuickAddChips(
                  categories: categoriesAsync.valueOrNull ?? const [],
                ),
              ),
              if (summary.budgets.isNotEmpty) ...[
                const SliverPadding(
                    padding: EdgeInsets.only(top: AppSpacing.xl)),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: '预算',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/budgets'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _BudgetRail(
                    budgets: summary.budgets,
                    categories: categoriesAsync.valueOrNull ?? const [],
                  ),
                ),
              ],
              if (summary.upcomingBills.isNotEmpty) ...[
                const SliverPadding(
                    padding: EdgeInsets.only(top: AppSpacing.xl)),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: '即将到期账单',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/bills'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _UpcomingBillsRail(bills: summary.upcomingBills),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.xl)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: '最近记录',
                  actionLabel: '查看全部',
                  onAction: () => context.push('/transactions'),
                ),
              ),
              if (summary.recentTransactions.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: '暂无记录',
                    subtitle: '点击底部 + 按钮开始记账',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tx = summary.recentTransactions[index];
                      final cat = categoriesAsync.valueOrNull
                          ?.where((c) => c.id == tx.categoryId)
                          .firstOrNull;
                      return _TransactionTile(tx: tx, category: cat);
                    },
                    childCount: summary.recentTransactions.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero balance card ────────────────────────────────────────────
//
// Refactoring UI cue: the most important number on the screen should be
// the most visually prominent — by *size* and *weight*, not just color.
// We pair `numericHero` (48px tabular figures) with a soft gradient pill
// and a primary-tinted shadow to lift it off the rice-paper background.
class _HeroBalance extends StatelessWidget {
  final DashboardSummary summary;
  const _HeroBalance({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFFE8A860)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.allXl,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary
                  .withValues(alpha: AppColors.opacityAccentBorder),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded,
                    size: 16,
                    color: Colors.white
                        .withValues(alpha: AppColors.opacityProminent)),
                AppSpacing.gapXs,
                Text(
                  '本月结余',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white
                        .withValues(alpha: AppColors.opacityProminent),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            AppSpacing.gapSm,
            // Animated counter — slide from previous value to current.
            TweenAnimationBuilder<double>(
              key: ValueKey(summary.balance),
              tween: Tween(begin: 0, end: summary.balance),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => Text(
                _formatCurrency(value),
                // The gradient is the same in both themes, so the text is a
                // fixed white rather than onPrimary (dark in dark mode).
                style: AppTypography.numericHero.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.visible,
              ),
            ),
            AppSpacing.gapSm,
            Text(
              summary.balance >= 0 ? '收支平衡良好' : '本月超支，记得复盘开支',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white
                    .withValues(alpha: AppColors.opacityHeroSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double value) {
    final f = NumberFormat('#,##0.00', 'en_US');
    return '¥${f.format(value)}';
  }
}

// ─── Income / Expense pill row ────────────────────────────────────
class _IncomeExpenseRow extends StatelessWidget {
  final DashboardSummary summary;
  const _IncomeExpenseRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _MoneyStatPill(
              isIncome: true,
              amount: summary.totalIncome,
              label: '本月收入',
            ),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: _MoneyStatPill(
              isIncome: false,
              amount: summary.totalExpense,
              label: '本月支出',
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyStatPill extends StatelessWidget {
  final bool isIncome;
  final double amount;
  final String label;
  const _MoneyStatPill({
    required this.isIncome,
    required this.amount,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final cs = Theme.of(context).colorScheme;
    final accent = isIncome ? AppColors.income : AppColors.expense;
    final bg = isIncome ? AppColors.incomeBg : AppColors.expenseBg;
    // In dark mode the pastel income/expense BG colors look out of place;
    // dial them down with a tinted surface variant instead.
    final pillBg = brightness == Brightness.dark ? cs.surfaceContainerHigh : bg;
    final iconData = isIncome ? Icons.south_rounded : Icons.north_rounded;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: AppRadius.allLg,
        boxShadow: AppShadow.subtle(brightness),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: Colors.white, size: 18),
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: accent.withValues(alpha: AppColors.opacityProminent),
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                AppSpacing.gapXs,
                Text(
                  '¥${NumberFormat('#,##0', 'en_US').format(amount)}',
                  style: AppTypography.titleMedium.copyWith(
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Smart insight banner ────────────────────────────────────────
//
// Single-line dynamic copy that turns raw numbers into a feeling. We do
// the simplest possible thing: pick a message based on which signals are
// strongest. Future iterations can add MoM comparison, prediction, etc.
class _SmartInsight extends StatelessWidget {
  final DashboardSummary summary;
  const _SmartInsight({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (msg, accent, icon) = _composeMessage(summary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: AppColors.opacitySoft),
          borderRadius: AppRadius.allMd,
          border: Border.all(
            color: accent.withValues(alpha: AppColors.opacityMuted),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            AppSpacing.gapSm,
            Expanded(
              child: Text(
                msg,
                style: AppTypography.bodyMedium.copyWith(
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData) _composeMessage(DashboardSummary s) {
    final budgetPct = s.overallBudgetUsage;
    if (budgetPct != null) {
      final pctText = (budgetPct * 100).toStringAsFixed(0);
      if (budgetPct >= 1) {
        return (
          '本月支出已超出预算（$pctText%），建议复盘开支',
          AppColors.budgetExceeded,
          Icons.warning_amber_rounded
        );
      }
      if (budgetPct >= 0.8) {
        return (
          '本月预算已用 $pctText%，留意节奏',
          AppColors.budgetWarning,
          Icons.lightbulb_outline_rounded
        );
      }
      return (
        '本月预算只用了 $pctText%，状态不错',
        AppColors.budgetSafe,
        Icons.eco_rounded
      );
    }
    if (s.totalExpense == 0 && s.totalIncome == 0) {
      return ('开始记下你的第一笔收支吧', AppColors.primary, Icons.auto_awesome_rounded);
    }
    return (
      '本月已支出 ¥${NumberFormat('#,##0', 'en_US').format(s.totalExpense)}，继续保持记账习惯',
      AppColors.primary,
      Icons.trending_up_rounded
    );
  }
}

// ─── Quick-add chips ─────────────────────────────────────────────
//
// Top-N expense categories for one-tap entry. Tapping a chip jumps to the
// add-transaction screen with the category pre-selected (handed off via
// `extra`). Until the add screen wires that up, it lands users on the
// add screen with the form ready.
class _QuickAddChips extends StatelessWidget {
  final List<Category> categories;
  const _QuickAddChips({required this.categories});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final picks = categories.where((c) => c.type == 'expense').take(6).toList();
    if (picks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            '快速记账',
            style: AppTypography.labelSmall.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ),
        AppSpacing.gapSm,
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: picks.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (_, i) => _QuickCategoryChip(category: picks[i]),
          ),
        ),
      ],
    );
  }
}

class _QuickCategoryChip extends StatelessWidget {
  final Category category;
  const _QuickCategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(category.colorValue);
    return InkWell(
      borderRadius: AppRadius.allLg,
      onTap: () => context.push(
        '/transaction/add',
        extra: TransactionDraft(type: 'expense', categoryId: category.id),
      ),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.allLg,
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIcon(
              iconCodePoint: category.iconCodePoint,
              color: color,
              size: 36,
            ),
            AppSpacing.gapXs,
            Text(
              category.name,
              style: AppTypography.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Budget rail ─────────────────────────────────────────────────
class _BudgetRail extends StatelessWidget {
  final List<Budget> budgets;
  final List<Category> categories;
  const _BudgetRail({required this.budgets, required this.categories});

  @override
  Widget build(BuildContext context) {
    // Most-used first: the budget closest to its limit is the one to see.
    final sorted = [...budgets]
      ..sort((a, b) => b.percentage.compareTo(a.percentage));
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => AppSpacing.gapMd,
        itemBuilder: (_, i) => _BudgetCard(
          budget: sorted[i],
          category:
              categories.where((c) => c.id == sorted[i].categoryId).firstOrNull,
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final Category? category;
  const _BudgetCard({required this.budget, this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (budget.percentage / 100).clamp(0.0, 1.0);
    final progressColor = budget.percentage >= 100
        ? AppColors.budgetExceeded
        : budget.percentage >= 80
            ? AppColors.budgetWarning
            : AppColors.budgetSafe;
    final money = NumberFormat('#,##0', 'en_US');
    final exceeded = budget.remaining < 0;

    return InkWell(
      borderRadius: AppRadius.allLg,
      onTap: () => context.push('/budgets'),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.allLg,
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (category != null) ...[
                  CategoryIcon(
                    iconCodePoint: category!.iconCodePoint,
                    color: Color(category!.colorValue),
                    size: 28,
                  ),
                  AppSpacing.gapSm,
                ],
                Expanded(
                  child: Text(
                    category?.name ?? '预算',
                    style: AppTypography.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${budget.percentage.toStringAsFixed(0)}%',
                  style: AppTypography.labelSmall.copyWith(color: progressColor),
                ),
              ],
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor:
                    progressColor.withValues(alpha: AppColors.opacityAccentFill),
                color: progressColor,
                minHeight: 6,
              ),
            ),
            AppSpacing.gapSm,
            Text(
              exceeded
                  ? '超支 ¥${money.format(-budget.remaining)}'
                  : '¥${money.format(budget.spent)} / ¥${money.format(budget.amount)}',
              style: AppTypography.bodySmall.copyWith(
                color: exceeded ? AppColors.budgetExceeded : cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upcoming bills ──────────────────────────────────────────────
class _UpcomingBillsRail extends StatelessWidget {
  final List<Bill> bills;
  const _UpcomingBillsRail({required this.bills});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: bills.length,
        separatorBuilder: (_, __) => AppSpacing.gapMd,
        itemBuilder: (_, i) => _BillCard(bill: bills[i]),
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  final Bill bill;
  const _BillCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dueColor =
        bill.isOverdue ? AppColors.expense : AppColors.budgetWarning;
    final days = bill.daysUntilDue;

    return Container(
      width: 180,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.allLg,
        border: Border(
          left: BorderSide(color: dueColor, width: 3),
          top: BorderSide(color: cs.outlineVariant),
          right: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            bill.name,
            style: AppTypography.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.gapXs,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '¥${NumberFormat('#,##0', 'en_US').format(bill.amount)}',
                style: AppTypography.numericMedium.copyWith(
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
              Text(
                bill.isOverdue ? '已逾期' : '$days 天后',
                style: AppTypography.labelSmall.copyWith(color: dueColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Recent transaction tile ─────────────────────────────────────
class _TransactionTile extends StatelessWidget {
  final Transaction tx;
  final Category? category;
  const _TransactionTile({required this.tx, this.category});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push('/transaction/add', extra: tx),
      leading: category != null
          ? CategoryIcon(
              iconCodePoint: category!.iconCodePoint,
              color: Color(category!.colorValue),
            )
          : null,
      title: Text(category?.name ?? '未知', style: AppTypography.titleSmall),
      subtitle: tx.note != null && tx.note!.isNotEmpty
          ? Text(tx.note!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: AmountText(
        amount: tx.amount,
        isIncome: tx.isIncome,
        fontSize: 16,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 40,
              color: cs.error.withValues(alpha: AppColors.opacitySecondary)),
          AppSpacing.gapMd,
          Text('加载失败', style: AppTypography.titleMedium),
          AppSpacing.gapMd,
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
