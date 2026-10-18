import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/providers/selected_month_provider.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../category/domain/category_repository.dart';
import '../domain/budget.dart';
import '../domain/budget_repository.dart';
import 'add_budget_screen.dart';

final budgetProgressListProvider =
    FutureProvider<List<BudgetProgress>>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  ref.watch(transactionChangeProvider);
  final budgets = await BudgetRepository().getByMonth(month.year, month.month);
  final allCats = await CategoryRepository().getAll();

  final results = <BudgetProgress>[];
  for (final budget in budgets) {
    final cat = allCats.where((c) => c.id == budget.categoryId).firstOrNull;
    if (cat != null) {
      results.add(BudgetProgress(
        budget: budget,
        categoryName: cat.name,
        categoryIconCode: cat.iconCodePoint,
        categoryColorValue: cat.colorValue,
      ));
    }
  }
  // Closest to (or over) the limit first.
  results.sort((a, b) => b.percentage.compareTo(a.percentage));
  return results;
});

final _whole = NumberFormat('#,##0', 'en_US');
final _cents = NumberFormat('#,##0.00', 'en_US');

/// ¥1,500 for whole amounts, ¥1,623.50 otherwise — never ¥1,623.5.
String _yuan(double v) =>
    '¥${(v == v.roundToDouble() ? _whole : _cents).format(v)}';

Color _statusColor(double percentage) {
  if (percentage >= 100) return AppColors.budgetExceeded;
  if (percentage >= 80) return AppColors.budgetWarning;
  return AppColors.budgetSafe;
}

class BudgetListScreen extends ConsumerWidget {
  const BudgetListScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, {Budget? budget}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddBudgetScreen(budget: budget)),
    );
    ref.invalidate(budgetProgressListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final progressAsync = ref.watch(budgetProgressListProvider);

    void shiftMonth(int delta) => ref
        .read(selectedMonthProvider.notifier)
        .update((state) => DateTime(state.year, state.month + delta));

    return Scaffold(
      appBar: AppBar(
        title: const Text('预算'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加预算',
            onPressed: () => _open(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _MonthSwitcher(
            month: month,
            onPrevious: () => shiftMonth(-1),
            onNext: () => shiftMonth(1),
          ),
          Expanded(
            child: progressAsync.when(
              data: (progressList) {
                if (progressList.isEmpty) {
                  return EmptyState(
                    icon: Icons.savings_outlined,
                    title: '本月还没有预算',
                    subtitle: '给常花钱的分类定个上限，花到 80% 会提醒你',
                    actionLabel: '添加预算',
                    onAction: () => _open(context, ref),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                  children: [
                    _SummaryCard(progressList: progressList),
                    AppSpacing.gapLg,
                    for (final p in progressList) ...[
                      _BudgetCard(
                        progress: p,
                        onTap: () => _open(context, ref, budget: p.budget),
                      ),
                      AppSpacing.gapSm,
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('加载失败: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: '上个月',
            onPressed: onPrevious,
          ),
          SizedBox(
            width: 120,
            child: Text(
              DateFormat('yyyy年M月', 'zh_CN').format(month),
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: '下个月',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<BudgetProgress> progressList;
  const _SummaryCard({required this.progressList});

  @override
  Widget build(BuildContext context) {
    final total = progressList.fold<double>(0, (s, p) => s + p.budget.amount);
    final spent = progressList.fold<double>(0, (s, p) => s + p.budget.spent);
    final pct = total > 0 ? spent / total * 100 : 0.0;
    final exceeded = progressList.where((p) => p.status == 'exceeded').length;
    final warning = progressList.where((p) => p.status == 'warning').length;
    final remaining = total - spent;

    final String note;
    if (exceeded > 0) {
      note = '$exceeded 项已超支${warning > 0 ? '，$warning 项接近上限' : ''}';
    } else if (warning > 0) {
      note = '$warning 项接近上限，注意节奏';
    } else {
      note = '各项都在预算内';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFFE8A860)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.allXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            remaining >= 0 ? '本月还可以花' : '本月已超支',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: AppColors.opacityProminent),
              letterSpacing: 1.2,
            ),
          ),
          AppSpacing.gapXs,
          Text(
            _yuan(remaining.abs()),
            style: AppTypography.displayLarge.copyWith(
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          AppSpacing.gapMd,
          ClipRRect(
            borderRadius: AppRadius.allPill,
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          AppSpacing.gapSm,
          Row(
            children: [
              Expanded(
                child: Text(
                  '已用 ${_yuan(spent)} / ${_yuan(total)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: AppColors.opacityProminent),
                  ),
                ),
              ),
              Text(
                note,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetProgress progress;
  final VoidCallback onTap;

  const _BudgetCard({required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final budget = progress.budget;
    final statusColor = _statusColor(budget.percentage);
    final exceeded = budget.remaining < 0;

    return Material(
      color: cs.surface,
      borderRadius: AppRadius.allLg,
      child: InkWell(
        borderRadius: AppRadius.allLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allLg,
            border: Border.all(
              color: exceeded
                  ? AppColors.budgetExceeded.withValues(alpha: AppColors.opacityAccentBorder)
                  : cs.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CategoryIcon(
                    iconCodePoint: progress.categoryIconCode,
                    color: Color(progress.categoryColorValue),
                    size: 40,
                  ),
                  AppSpacing.gapMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(progress.categoryName, style: AppTypography.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '已用 ${_yuan(budget.spent)} / ${_yuan(budget.amount)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${budget.percentage.toStringAsFixed(0)}%',
                    style: AppTypography.titleMedium.copyWith(color: statusColor),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              ClipRRect(
                borderRadius: AppRadius.allPill,
                child: LinearProgressIndicator(
                  value: (budget.percentage / 100).clamp(0.0, 1.0),
                  backgroundColor: statusColor.withValues(alpha: AppColors.opacityMuted),
                  color: statusColor,
                  minHeight: 6,
                ),
              ),
              AppSpacing.gapSm,
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  exceeded
                      ? '超出 ${_yuan(-budget.remaining)}'
                      : '剩余 ${_yuan(budget.remaining)}',
                  style: AppTypography.bodySmall.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
