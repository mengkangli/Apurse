import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/category_icon.dart';
import '../../category/domain/category.dart';
import '../../category/domain/category_repository.dart';
import '../domain/bill.dart';
import '../domain/bill_repository.dart';

class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();
  String? _categoryId;
  bool _isRecurring = true;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _dueDayController.text = '1';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDayController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final dueDay = int.tryParse(_dueDayController.text) ?? 1;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入账单名称')),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入金额')),
      );
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }
    if (dueDay < 1 || dueDay > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的日期 (1-31)')),
      );
      return;
    }

    final now = DateTime.now();
    final bill = Bill(
      id: _uuid.v4(),
      name: name,
      amount: amount,
      categoryId: _categoryId!,
      dueDay: dueDay,
      isRecurring: _isRecurring,
      paid: false,
      createdAt: now,
      updatedAt: now,
    );

    await BillRepository().insert(bill);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加账单'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Text('账单名称', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例如: 房租、电费',
              ),
            ),
            AppSpacing.gapXl,

            // Amount
            Text('金额', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '输入金额',
                prefixText: '¥ ',
              ),
            ),
            AppSpacing.gapXl,

            // Category
            Text('分类', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            FutureBuilder<List<Category>>(
              future: CategoryRepository().getByType('expense'),
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
                      onSelected: (_) => setState(() => _categoryId = cat.id),
                    );
                  }).toList(),
                );
              },
            ),
            AppSpacing.gapXl,

            // Due day
            Text('每月到期日', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapSm,
            TextField(
              controller: _dueDayController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: const InputDecoration(
                hintText: '输入日期 (1-31)',
                suffixText: '日',
              ),
            ),
            AppSpacing.gapXl,

            // Recurring toggle
            Row(
              children: [
                Text('每月重复', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: _isRecurring,
                  onChanged: (v) => setState(() => _isRecurring = v),
                  activeTrackColor: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
