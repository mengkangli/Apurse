import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/providers/selected_month_provider.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../category/domain/category_repository.dart';
import '../../transaction/domain/transaction_repository.dart';

final categoryBreakdownProvider =
    FutureProvider<List<CategoryBreakdown>>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  ref.watch(transactionChangeProvider);
  final cats = await CategoryRepository().getByType('expense');
  final txRepo = TransactionRepository();

  // Single GROUP BY query instead of per-category queries
  final sumsByCat =
      await txRepo.sumExpenseByCategories(month.year, month.month);

  final catsById = {for (final c in cats) c.id: c};
  final breakdowns = <CategoryBreakdown>[];
  var uncategorized = 0.0;
  for (final MapEntry(key: id, value: sum) in sumsByCat.entries) {
    if (sum <= 0) continue;
    final cat = catsById[id];
    if (cat == null) {
      // Spending must still add up to the month's total even if its
      // category row is gone.
      uncategorized += sum;
      continue;
    }
    breakdowns.add(CategoryBreakdown(
      categoryName: cat.name,
      iconCode: cat.iconCodePoint,
      colorValue: cat.colorValue,
      amount: sum,
    ));
  }
  if (uncategorized > 0) {
    breakdowns.add(CategoryBreakdown(
      categoryName: '未分类',
      iconCode: Icons.more_horiz_rounded.codePoint,
      colorValue: 0xFF9E9E9E,
      amount: uncategorized,
    ));
  }

  final total = breakdowns.fold<double>(0, (s, b) => s + b.amount);
  for (final b in breakdowns) {
    b.percentage = total > 0 ? (b.amount / total * 100) : 0;
  }

  breakdowns.sort((a, b) => b.amount.compareTo(a.amount));
  return breakdowns;
});

final dailyTrendProvider = FutureProvider<List<DailyTrend>>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  ref.watch(transactionChangeProvider);
  final db = TransactionRepository();
  final all = await db.getByMonth(month.year, month.month);

  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final trends = <int, DailyTrend>{};
  for (int d = 1; d <= daysInMonth; d++) {
    trends[d] = DailyTrend(day: d, income: 0, expense: 0);
  }
  for (final tx in all) {
    final d = tx.date.day;
    if (tx.isIncome) {
      trends[d]!.income += tx.amount;
    } else {
      trends[d]!.expense += tx.amount;
    }
  }
  return trends.values.toList();
});

class CategoryBreakdown {
  final String categoryName;
  final int iconCode;
  final int colorValue;
  final double amount;
  double percentage;

  CategoryBreakdown({
    required this.categoryName,
    required this.iconCode,
    required this.colorValue,
    required this.amount,
    this.percentage = 0,
  });
}

class DailyTrend {
  final int day;
  double income;
  double expense;

  DailyTrend({
    required this.day,
    this.income = 0,
    this.expense = 0,
  });
}

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final breakdownAsync = ref.watch(categoryBreakdownProvider);
    final trendAsync = ref.watch(dailyTrendProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          DateFormat('yyyy年M月', 'zh_CN').format(month),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              ref
                  .read(selectedMonthProvider.notifier)
                  .update((state) => DateTime(state.year, state.month - 1));
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () {
              ref
                  .read(selectedMonthProvider.notifier)
                  .update((state) => DateTime(state.year, state.month + 1));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Category breakdown pie chart
            _buildPieSection(context, breakdownAsync, ref),
            AppSpacing.gapXl,
            // Daily trend bar chart
            _buildTrendSection(context, trendAsync, ref),
            AppSpacing.gapXxl,
          ],
        ),
      ),
    );
  }

  Widget _buildPieSection(
    BuildContext context,
    AsyncValue<List<CategoryBreakdown>> async,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '支出分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          AppSpacing.gapLg,
          async.when(
            data: (breakdown) {
              if (breakdown.isEmpty) {
                return const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: '暂无数据',
                  subtitle: '添加支出记录后查看统计',
                );
              }
              return Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: breakdown.map((b) {
                          return PieChartSectionData(
                            color: Color(b.colorValue),
                            value: b.amount,
                            title: b.percentage >= 5
                                ? '${b.percentage.toStringAsFixed(0)}%'
                                : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            radius: 70,
                          );
                        }).toList(),
                        centerSpaceRadius: 35,
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
                  AppSpacing.gapLg,
                  ...breakdown.map((b) {
                    final color = Color(b.colorValue);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          AppSpacing.gapSm,
                          Expanded(
                            child: Text(
                              b.categoryName,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '¥${b.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          AppSpacing.gapSm,
                          Text(
                            '${b.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(child: Text('加载失败: $err')),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSection(
    BuildContext context,
    AsyncValue<List<DailyTrend>> async,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每日趋势',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          AppSpacing.gapLg,
          async.when(
            data: (trends) {
              final hasData = trends.any((t) => t.income > 0 || t.expense > 0);
              if (!hasData) {
                return const EmptyState(
                  icon: Icons.show_chart_outlined,
                  title: '暂无数据',
                  subtitle: '添加记录后查看趋势',
                );
              }
              return SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: trends
                            .map((t) =>
                                (t.expense > t.income ? t.expense : t.income))
                            .reduce((a, b) => a > b ? a : b) *
                        1.2,
                    barGroups: trends.map((t) {
                      return BarChartGroupData(
                        x: t.day,
                        barRods: [
                          BarChartRodData(
                            toY: t.expense,
                            color: AppColors.expense,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                          BarChartRodData(
                            toY: t.income,
                            color: AppColors.income,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() % 5 == 1 || value.toInt() == 1) {
                              return Text(
                                '${value.toInt()}',
                                style: const TextStyle(fontSize: 10),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 100,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: colorScheme.surfaceContainerLow,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(child: Text('加载失败: $err')),
          ),
        ],
      ),
    );
  }
}
