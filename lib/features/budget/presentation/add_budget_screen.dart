import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../shared/providers/selected_month_provider.dart';
import '../../category/domain/category.dart';
import '../../category/domain/category_repository.dart';
import '../domain/budget.dart';
import '../domain/budget_repository.dart';

/// Adds a budget for the selected month, or edits [budget] when given.
/// Pops `true` when something was saved or deleted.
class AddBudgetScreen extends ConsumerStatefulWidget {
  final Budget? budget;
  const AddBudgetScreen({super.key, this.budget});

  @override
  ConsumerState<AddBudgetScreen> createState() => _AddBudgetScreenState();
}

class _AddBudgetScreenState extends ConsumerState<AddBudgetScreen> {
  String? _categoryId;
  final _amountController = TextEditingController();
  late final Future<List<Category>> _categories =
      CategoryRepository().getByType('expense');
  bool _saving = false;

  bool get _isEditing => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    if (budget != null) {
      _categoryId = budget.categoryId;
      _amountController.text = _formatAmount(budget.amount);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  static String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  DateTime get _month {
    final budget = widget.budget;
    return budget != null
        ? DateTime(budget.year, budget.month)
        : ref.read(selectedMonthProvider);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      _toast('请输入预算金额');
      return;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }

    setState(() => _saving = true);
    try {
      final month = _month;
      final created = await BudgetRepository().upsert(
        categoryId: _categoryId!,
        year: month.year,
        month: month.month,
        amount: amount,
      );
      if (!mounted) return;
      if (!created && !_isEditing) _toast('该分类本月已有预算，已更新金额');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('保存失败：$e');
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预算'),
        content: const Text('确定要删除这项预算吗？已记录的支出不受影响。'),
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
    if (confirm != true) return;
    await BudgetRepository().delete(widget.budget!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final month = _month;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑预算' : '添加预算'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '删除预算',
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy年M月', 'zh_CN').format(month),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            AppSpacing.gapXl,
            Text('分类', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            FutureBuilder<List<Category>>(
              future: _categories,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                final cats = snapshot.data!;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: cats.map((cat) {
                    final selected = cat.id == _categoryId;
                    final color = Color(cat.colorValue);
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryIcon(
                            iconCodePoint: cat.iconCodePoint,
                            color: color,
                            size: 24,
                          ),
                          AppSpacing.gapXs,
                          Text(cat.name),
                        ],
                      ),
                      selected: selected,
                      // The category is what identifies a budget, so it's
                      // fixed while editing.
                      onSelected: _isEditing
                          ? null
                          : (_) => setState(() => _categoryId = cat.id),
                    );
                  }).toList(),
                );
              },
            ),
            AppSpacing.gapXl,
            Text('预算金额', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                hintText: '输入月预算金额',
                prefixText: '¥ ',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
