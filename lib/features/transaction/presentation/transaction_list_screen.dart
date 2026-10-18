import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/illustrations.dart';
import '../../../core/widgets/shell_tab_scaffold.dart';
import '../../../shared/providers/category_list_provider.dart';
import '../../../shared/providers/selected_month_provider.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../../shared/utils/month_utils.dart';
import '../../category/domain/category.dart';
import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

final transactionsByMonthProvider =
    FutureProvider.family<List<Transaction>, DateTime>((ref, month) async {
  ref.watch(transactionChangeProvider);
  return TransactionRepository().getByMonth(month.year, month.month);
});

enum _TypeFilter { all, expense, income }

final _typeFilterProvider = StateProvider<_TypeFilter>((_) => _TypeFilter.all);
final _searchQueryProvider = StateProvider<String>((_) => '');

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final transactionsAsync = ref.watch(transactionsByMonthProvider(month));
    final filter = ref.watch(_typeFilterProvider);
    final query = ref.watch(_searchQueryProvider);
    final categoriesAsync = ref.watch(sharedCategoryListProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];

    final selectedDay = _selectedDayForMonth(month);

    return ShellTabScaffold(
      title: Text(DateFormat('yyyy年M月流水', 'zh_CN').format(month)),
      body: Column(
        children: [
          Expanded(
            child: transactionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('加载失败: $err')),
              data: (all) {
                final daySummaries = _buildDaySummaries(all);
                final dayItems = _transactionsForDay(all, selectedDay);
                final filtered =
                    _applyFilters(dayItems, filter, query, categories);

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _TransactionCalendar(
                          month: month,
                          selectedDay: selectedDay,
                          summaries: daySummaries,
                          canGoNext: !isCurrentOrFutureMonth(month),
                          onPreviousMonth: () {
                            final previous =
                                DateTime(month.year, month.month - 1);
                            ref
                                .read(selectedMonthProvider.notifier)
                                .update((_) => previous);
                          },
                          onNextMonth: () {
                            final next = DateTime(month.year, month.month + 1);
                            ref
                                .read(selectedMonthProvider.notifier)
                                .update((_) => clampToCurrentMonth(next));
                          },
                          onSelectDay: (day) {
                            setState(() => _selectedDay = day);
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SelectedDayHeader(
                        day: selectedDay,
                        transactions: dayItems,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _FilterBar(
                        filter: filter,
                        onFilterChanged: (f) =>
                            ref.read(_typeFilterProvider.notifier).state = f,
                        onSearchChanged: (q) =>
                            ref.read(_searchQueryProvider.notifier).state = q,
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmpty(
                          hasFilter:
                              query.isNotEmpty || filter != _TypeFilter.all,
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _TransactionCard(
                            tx: filtered[index],
                            category: categories
                                .where(
                                    (c) => c.id == filtered[index].categoryId)
                                .firstOrNull,
                            onChanged: () =>
                                ref.invalidate(transactionsByMonthProvider),
                          ),
                          childCount: filtered.length,
                        ),
                      ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DateTime _selectedDayForMonth(DateTime month) {
    final selected = _selectedDay;
    if (selected != null &&
        selected.year == month.year &&
        selected.month == month.month) {
      return DateTime(selected.year, selected.month, selected.day);
    }

    final now = DateTime.now();
    if (now.year == month.year && now.month == month.month) {
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime(month.year, month.month);
  }

  Map<DateTime, _DaySummary> _buildDaySummaries(List<Transaction> all) {
    final summaries = <DateTime, _DaySummary>{};
    for (final tx in all) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      final current = summaries[day] ?? const _DaySummary();
      summaries[day] = current.add(tx);
    }
    return summaries;
  }

  List<Transaction> _transactionsForDay(List<Transaction> all, DateTime day) {
    final result = all
        .where((tx) =>
            tx.date.year == day.year &&
            tx.date.month == day.month &&
            tx.date.day == day.day)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  Widget _buildEmpty({
    required bool hasFilter,
  }) {
    if (!hasFilter) return const _SimpleEmptyRecords();
    return const EmptyState(
      illustration: EmptyIllustration.noResults,
      title: '没有匹配的记录',
      subtitle: '换个关键字或筛选条件试试',
    );
  }

  List<Transaction> _applyFilters(
    List<Transaction> all,
    _TypeFilter filter,
    String query,
    List<Category> categories,
  ) {
    Iterable<Transaction> out = all;
    if (filter == _TypeFilter.expense) {
      out = out.where((t) => !t.isIncome);
    } else if (filter == _TypeFilter.income) {
      out = out.where((t) => t.isIncome);
    }
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      out = out.where((t) {
        final note = (t.note ?? '').toLowerCase();
        final cat = categories
            .where((c) => c.id == t.categoryId)
            .firstOrNull
            ?.name
            .toLowerCase();
        return note.contains(q) || (cat?.contains(q) ?? false);
      });
    }
    return out.toList();
  }
}

class _DaySummary {
  final double income;
  final double expense;

  const _DaySummary({
    this.income = 0,
    this.expense = 0,
  });

  double get net => income - expense;

  _DaySummary add(Transaction tx) {
    return tx.isIncome
        ? _DaySummary(income: income + tx.amount, expense: expense)
        : _DaySummary(income: income, expense: expense + tx.amount);
  }
}

class _TransactionCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final Map<DateTime, _DaySummary> summaries;
  final bool canGoNext;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDay;

  const _TransactionCalendar({
    required this.month,
    required this.selectedDay,
    required this.summaries,
    required this.canGoNext,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = _calendarDays(month);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: '上个月',
                onPressed: onPreviousMonth,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                DateFormat('yyyy年M月', 'zh_CN').format(month),
                style: AppTypography.titleSmall,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: '下个月',
                onPressed: canGoNext ? onNextMonth : null,
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text(
                '点击日期查看流水',
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          const _WeekdayRow(),
          AppSpacing.gapXs,
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              if (day == null) return const SizedBox.shrink();
              final summary = summaries[day];
              final selected = _isSameDay(day, selectedDay);
              return _CalendarDayCell(
                day: day,
                summary: summary,
                selected: selected,
                onTap: () => onSelectDay(day),
              );
            },
          ),
        ],
      ),
    );
  }

  static List<DateTime?> _calendarDays(DateTime month) {
    final first = DateTime(month.year, month.month);
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= totalDays; day++)
        DateTime(month.year, month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const labels = ['日', '一', '二', '三', '四', '五', '六'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final _DaySummary? summary;
  final bool selected;
  final VoidCallback onTap;

  const _CalendarDayCell({
    required this.day,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = summary?.net ?? 0;
    final hasAmount = summary != null && net != 0;
    final positive = net > 0;
    final accent = positive ? AppColors.income : AppColors.expense;
    final today = DateTime.now();
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    // Empty days recede so the days with activity stand out.
    final bgColor = hasAmount ? accent.withValues(alpha: 0.12) : Colors.transparent;
    final borderColor = selected
        ? cs.primary
        : hasAmount
            ? accent.withValues(alpha: 0.28)
            : isToday
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.35);

    return Material(
      color: bgColor,
      borderRadius: AppRadius.allMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allMd,
            border: Border.all(
              color: borderColor,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: AppTypography.labelSmall.copyWith(
                  color: selected ? cs.primary : cs.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasAmount ? _formatCompactAmount(net) : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: hasAmount ? accent : cs.onSurfaceVariant,
                  fontSize: 10,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCompactAmount(double value) {
    final absValue = value.abs();
    final sign = value > 0 ? '+' : '-';
    if (absValue >= 10000) {
      return '$sign${(absValue / 10000).toStringAsFixed(1)}万';
    }
    if (absValue >= 1000) {
      return '$sign${(absValue / 1000).toStringAsFixed(1)}k';
    }
    return '$sign${absValue.toStringAsFixed(0)}';
  }
}

class _SelectedDayHeader extends StatelessWidget {
  final DateTime day;
  final List<Transaction> transactions;

  const _SelectedDayHeader({
    required this.day,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final income = transactions
        .where((tx) => tx.isIncome)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final expense = transactions
        .where((tx) => !tx.isIncome)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final net = income - expense;
    final netColor = net >= 0 ? AppColors.income : AppColors.expense;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('M月d日 EEEE', 'zh_CN').format(day),
                  style: AppTypography.titleMedium,
                ),
                AppSpacing.gapXs,
                Text(
                  '${transactions.length} 笔流水',
                  style: AppTypography.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${net >= 0 ? '+' : '-'}¥${net.abs().toStringAsFixed(2)}',
            style: AppTypography.titleSmall.copyWith(
              color: netColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleEmptyRecords extends StatelessWidget {
  const _SimpleEmptyRecords();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: cs.onSurfaceVariant.withValues(alpha: 0.32),
          ),
          AppSpacing.gapSm,
          Text(
            '暂无记录',
            style: AppTypography.titleSmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  final _TypeFilter filter;
  final ValueChanged<_TypeFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _FilterBar({
    required this.filter,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  bool _searching = false;
  late final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _ctrl.clear();
        widget.onSearchChanged('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _searching
                  ? _SearchField(
                      key: const ValueKey('search'),
                      controller: _ctrl,
                      onChanged: widget.onSearchChanged,
                    )
                  : _TypeChipRow(
                      key: const ValueKey('chips'),
                      filter: widget.filter,
                      onChanged: widget.onFilterChanged,
                    ),
            ),
          ),
          AppSpacing.gapXs,
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? '关闭搜索' : '搜索',
            onPressed: _toggleSearch,
          ),
        ],
      ),
    );
  }
}

class _TypeChipRow extends StatelessWidget {
  final _TypeFilter filter;
  final ValueChanged<_TypeFilter> onChanged;

  const _TypeChipRow({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _TypeChip(
            label: '全部',
            selected: filter == _TypeFilter.all,
            onTap: () => onChanged(_TypeFilter.all),
          ),
          AppSpacing.gapSm,
          _TypeChip(
            label: '支出',
            selected: filter == _TypeFilter.expense,
            accent: AppColors.expense,
            onTap: () => onChanged(_TypeFilter.expense),
          ),
          AppSpacing.gapSm,
          _TypeChip(
            label: '收入',
            selected: filter == _TypeFilter.income,
            accent: AppColors.income,
            onTap: () => onChanged(_TypeFilter.income),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? cs.primary;
    return Material(
      color: selected
          ? color.withValues(alpha: AppColors.opacityAccentFill)
          : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allPill,
        side: BorderSide(
          color: selected ? color : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: AppRadius.allPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: selected ? color : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: '搜索备注或分类',
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
          prefixIcon: Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 36),
        ),
      ),
    );
  }
}

class _TransactionCard extends ConsumerWidget {
  final Transaction tx;
  final Category? category;
  final VoidCallback onChanged;

  const _TransactionCard({
    required this.tx,
    required this.category,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: Key(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.expense,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        try {
          await TransactionRepository().delete(tx.id);
          ref.read(transactionChangeProvider.notifier).state++;
        } finally {
          onChanged();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.allLg,
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
          onTap: () => context.push('/transaction/add', extra: tx),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 4),
          leading: category != null
              ? CategoryIcon(
                  iconCodePoint: category!.iconCodePoint,
                  color: Color(category!.colorValue),
                )
              : null,
          title: Text(
            category?.name ?? '未知分类',
            style: AppTypography.titleSmall,
          ),
          subtitle: tx.note != null && tx.note!.isNotEmpty
              ? Text(
                  tx.note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                )
              : null,
          trailing: AmountText(
            amount: tx.amount,
            isIncome: tx.isIncome,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条记录吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
