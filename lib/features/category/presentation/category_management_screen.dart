import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/providers/category_list_provider.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../transaction/domain/transaction_repository.dart';
import '../domain/category.dart';
import '../domain/category_repository.dart';
import 'add_category_screen.dart';

final categoryListProvider = FutureProvider<List<Category>>((ref) async {
  return CategoryRepository().getAll();
});

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddCategoryScreen(),
                ),
              );
              ref.invalidate(categoryListProvider);
            },
          ),
        ],
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: '暂无分类',
              subtitle: '点击右上角 + 添加分类',
            );
          }

          final incomeCategories =
              categories.where((c) => c.type == 'income').toList();
          final expenseCategories =
              categories.where((c) => c.type == 'expense').toList();

          return ListView(
            children: [
              _buildSection(context, '收入分类', incomeCategories, ref, colorScheme),
              _buildSection(context, '支出分类', expenseCategories, ref, colorScheme),
              AppSpacing.gapXxl,
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Category> categories,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ...categories.map((cat) => _buildCategoryTile(context, cat, ref)),
      ],
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    Category category,
    WidgetRef ref,
  ) {
    final color = Color(category.colorValue);

    return ListTile(
      leading: CategoryIcon(
        iconCodePoint: category.iconCodePoint,
        color: color,
        size: 40,
      ),
      title: Text(category.name),
      trailing: category.isDefault
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除分类',
              onPressed: () async {
                final used = await TransactionRepository()
                    .countByCategory(category.id);
                if (!context.mounted) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除分类'),
                    content: Text(used > 0
                        ? '"${category.name}"下有 $used 笔记录，删除后它们会移到「其他」分类，该分类的预算也会一并删除。'
                        : '确定要删除"${category.name}"吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除',
                            style: TextStyle(color: AppColors.expense)),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                try {
                  await CategoryRepository().deleteAndReassign(category);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('删除失败：$e')),
                    );
                  }
                  return;
                }
                ref.invalidate(categoryListProvider);
                ref.invalidate(sharedCategoryListProvider);
                if (context.mounted) notifyTransactionChanged(context);
              },
            ),
    );
  }
}
