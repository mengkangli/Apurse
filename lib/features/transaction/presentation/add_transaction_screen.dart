import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../shared/providers/transaction_change_provider.dart';
import '../../category/domain/category.dart';
import '../../category/domain/category_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  String _amount = '0';
  String _type = 'expense';
  String? _categoryId;
  DateTime _date = DateTime.now();
  final _noteController = TextEditingController();
  final _noteFocusNode = FocusNode();
  final _uuid = const Uuid();
  bool _hasDecimal = false;
  bool _isNoteFocused = false;
  late AnimationController _shakeController;

  /// Cached categories for the inline chip rail. Reloaded whenever the
  /// type toggle flips between expense ↔ income.
  List<Category> _categories = const [];

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _noteFocusNode.addListener(() {
      if (!mounted) return;
      setState(() => _isNoteFocused = _noteFocusNode.hasFocus);
    });
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await CategoryRepository().getByType(_type);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (key == 'back') {
        if (_amount.length > 1) {
          if (_amount.endsWith('.')) _hasDecimal = false;
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
          _hasDecimal = false;
        }
        return;
      }
      if (key == 'clear' || key == 'C') {
        _amount = '0';
        _hasDecimal = false;
        return;
      }
      if (key == '.') {
        if (_hasDecimal) return;
        _amount += '.';
        _hasDecimal = true;
        return;
      }
      // Numeric keys
      if (key == '00') {
        if (_amount == '0') return; // 00 on 0 does nothing
      }
      if (_amount == '0') {
        _amount = key;
      } else if (_amount.length < 10) {
        _amount += key;
      }
      // Prevent leading zeros like "05"
      if (_amount.startsWith('0') &&
          _amount.length > 1 &&
          !_amount.startsWith('0.')) {
        _amount = _amount.substring(1);
      }
    });
  }

  Future<void> _save() async {
    final parsedAmount = double.tryParse(_amount) ?? 0;
    // Allow amounts ending with "." like "123." → parse as-is (or warn)
    if (parsedAmount <= 0) {
      if (_amount.endsWith('.') ||
          _amount == '0' ||
          _amount == '0.' ||
          _amount == '0.0' ||
          _amount == '0.00') {
        // Amount not yet entered meaningfully
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }

    final now = DateTime.now();
    final tx = Transaction(
      id: _uuid.v4(),
      amount: parsedAmount,
      type: _type,
      categoryId: _categoryId!,
      date: _date,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    try {
      await TransactionRepository().insert(tx);
      if (mounted) notifyTransactionChanged(context);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isExpense = _type == 'expense';
    final accentColor = isExpense ? AppColors.expense : AppColors.income;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('记一笔'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Hero block: type toggle + amount.
            // Refactoring UI cue — the amount is what this screen exists
            // for, so it gets the largest type and lives inside a soft,
            // rounded surface card that anchors the layout.
            Container(
              margin: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: AppRadius.allXl,
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _TypeToggle(
                    isExpense: isExpense,
                    onChanged: (expense) {
                      setState(() {
                        _type = expense ? 'expense' : 'income';
                      });
                      _loadCategories();
                    },
                  ),
                  AppSpacing.gapLg,
                  // Animated currency with `numericLarge` (36px tabular).
                  // We animate scale on each keystroke so the number feels
                  // alive — see `_AnimatedAmount` below.
                  _AnimatedAmount(
                    text: _formatAmountDisplay(_amount),
                    color: accentColor,
                  ),
                ],
              ),
            ),
            AppSpacing.gapMd,
            // Date pill row — quick-select Today / Yesterday / Pick.
            _DatePillRow(
              date: _date,
              onPick: _pickDate,
              onSet: (d) => setState(() => _date = d),
            ),
            AppSpacing.gapMd,
            // Inline category chip rail — replaces the modal sheet.
            _CategoryRail(
              categories: _categories,
              selectedId: _categoryId,
              onSelect: (cat) => setState(() => _categoryId = cat.id),
            ),
            AppSpacing.gapMd,
            if (_isNoteFocused) const Spacer(),
            // Note field — lives below the primary actions because it's
            // optional. Shorter height than before to give the keypad room.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: _noteController,
                focusNode: _noteFocusNode,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: const InputDecoration(
                  hintText: '添加备注…',
                  prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
                  isDense: true,
                ),
                maxLength: 200,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
              ),
            ),
            if (!_isNoteFocused) AppSpacing.gapSm,
            if (!_isNoteFocused) Expanded(child: _buildNumPad()),
          ],
        ),
      ),
    );
  }

  /// Adds thousands separators while the user is still typing — but only
  /// once a decimal hasn't been started, so we don't fight the input.
  String _formatAmountDisplay(String raw) {
    if (raw.contains('.')) {
      final parts = raw.split('.');
      final whole = double.tryParse(parts[0])?.toInt() ?? 0;
      return '¥${NumberFormat('#,##0', 'en_US').format(whole)}.${parts[1]}';
    }
    final n = double.tryParse(raw)?.toInt() ?? 0;
    return '¥${NumberFormat('#,##0', 'en_US').format(n)}';
  }

  Widget _buildNumPad() {
    final colorScheme = Theme.of(context).colorScheme;
    final keys = [
      ['1', '2', '3', 'back'],
      ['4', '5', '6', 'clear'],
      ['7', '8', '9', '.'],
      ['00', '0', '', 'save'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: keys.map((row) {
          return Expanded(
            child: Row(
              children: row.map((key) {
                if (key == 'save') {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _type == 'expense'
                              ? AppColors.expense
                              : AppColors.income,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.buttonRadius),
                          ),
                        ),
                        child: const Text('保存', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  );
                }
                if (key.isEmpty) return const Spacer();
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _buildNumKey(key, colorScheme),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNumKey(String key, ColorScheme colorScheme) {
    final isSpecial = key == 'back' || key == 'clear' || key == '.';
    return _PressableKey(
      onTap: () => _onKeyPress(key),
      child: Container(
        decoration: BoxDecoration(
          color:
              isSpecial ? colorScheme.surfaceContainerLow : colorScheme.surface,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
        ),
        child: Center(
          child: key == 'back'
              ? Icon(Icons.backspace_outlined,
                  size: 22, color: colorScheme.onSurfaceVariant)
              : key == 'clear'
                  ? Text('C',
                      style: AppTypography.titleMedium.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ))
                  : key == '.'
                      ? Text('.',
                          style: AppTypography.numericMedium.copyWith(
                            fontSize: 24,
                            color: colorScheme.onSurface,
                          ))
                      : Text(
                          key,
                          style: AppTypography.numericMedium.copyWith(
                            fontSize: 22,
                            color: colorScheme.onSurface,
                          ),
                        ),
        ),
      ),
    );
  }
}

// ─── Type toggle ────────────────────────────────────────────────
//
// Two-segment pill. The selected side fills with the type's accent color
// (red for expense, green for income) and the unselected side is a
// quiet, almost-transparent surface — Refactoring UI cue: emphasise the
// chosen state, *demote* the other one rather than dressing both up.
class _TypeToggle extends StatelessWidget {
  final bool isExpense;
  final ValueChanged<bool> onChanged;
  const _TypeToggle({required this.isExpense, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        children: [
          Expanded(
              child: _Segment(
            label: '支出',
            selected: isExpense,
            color: AppColors.expense,
            onTap: () => onChanged(true),
          )),
          Expanded(
              child: _Segment(
            label: '收入',
            selected: !isExpense,
            color: AppColors.income,
            onTap: () => onChanged(false),
          )),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        borderRadius: AppRadius.allPill,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.allPill,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.titleSmall.copyWith(
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated currency display — scales up briefly each time the value
/// changes, so keystrokes feel acknowledged. We key off the text itself
/// so AnimatedSwitcher only fires when the digits really change.
class _AnimatedAmount extends StatelessWidget {
  final String text;
  final Color color;
  const _AnimatedAmount({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Text(
        text,
        key: ValueKey(text),
        style: AppTypography.numericLarge.copyWith(color: color),
        maxLines: 1,
      ),
    );
  }
}

// ─── Date pill row ──────────────────────────────────────────────
class _DatePillRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPick;
  final ValueChanged<DateTime> onSet;
  const _DatePillRow({
    required this.date,
    required this.onPick,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final yesterday = t0.subtract(const Duration(days: 1));
    final selectedDay = DateTime(date.year, date.month, date.day);
    final isToday = selectedDay == t0;
    final isYesterday = selectedDay == yesterday;
    final isOther = !isToday && !isYesterday;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _DatePill(
            label: '今天',
            selected: isToday,
            onTap: () => onSet(t0),
          ),
          AppSpacing.gapSm,
          _DatePill(
            label: '昨天',
            selected: isYesterday,
            onTap: () => onSet(yesterday),
          ),
          AppSpacing.gapSm,
          _DatePill(
            label: isOther
                ? DateFormat('M月d日 EEEE', 'zh_CN').format(date)
                : '其他日期',
            icon: Icons.calendar_today_rounded,
            selected: isOther,
            onTap: onPick,
          ),
        ],
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _DatePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primary.withValues(alpha: AppColors.opacityAccentFill)
          : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allPill,
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: AppRadius.allPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? cs.primary : cs.onSurfaceVariant),
                AppSpacing.gapXs,
              ],
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Inline category rail ───────────────────────────────────────
//
// Replaces the old "tap to open a 4×N grid in a sheet" pattern with a
// horizontally-scrollable rail. One tap selects; long press could later
// open the full grid for users with lots of categories.
class _CategoryRail extends StatelessWidget {
  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onSelect;
  const _CategoryRail({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox(height: 76);
    }
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: categories.length,
        separatorBuilder: (_, __) => AppSpacing.gapSm,
        itemBuilder: (_, i) {
          final cat = categories[i];
          final selected = cat.id == selectedId;
          return _CategoryChip(
            category: cat,
            selected: selected,
            onTap: () => onSelect(cat),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final Category category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(category.colorValue);
    return InkWell(
      borderRadius: AppRadius.allLg,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 64,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: AppColors.opacityAccentFill)
              : cs.surface,
          borderRadius: AppRadius.allLg,
          border: Border.all(
            color: selected ? color : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIcon(
              iconCodePoint: category.iconCodePoint,
              color: color,
              size: 32,
            ),
            AppSpacing.gapXs,
            Text(
              category.name,
              style: AppTypography.bodySmall.copyWith(
                color: selected ? color : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Numeric keypad button with scale-on-press feedback. Material's
/// InkWell ripple is a good baseline but easy to miss on dense grids;
/// pairing it with a tiny 6% scale-down lands the press more clearly.
class _PressableKey extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PressableKey({required this.onTap, required this.child});

  @override
  State<_PressableKey> createState() => _PressableKeyState();
}

class _PressableKeyState extends State<_PressableKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
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
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: 1 - _ctrl.value, child: child),
        child: widget.child,
      ),
    );
  }
}
