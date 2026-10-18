import 'package:uuid/uuid.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/money.dart';
import '../../transaction/domain/transaction_repository.dart';
import 'budget.dart';

class BudgetRepository {
  final _db = DatabaseHelper.instance;
  final _txRepo = TransactionRepository();

  static const _table = DatabaseConstants.tableBudgets;

  /// The month's budgets with [Budget.spent] summed from that month's
  /// expenses, so a budget created mid-month already counts earlier spending.
  Future<List<Budget>> getByMonth(int year, int month) async {
    final rows = await _db.query(
      _table,
      where: 'year = ? AND month = ?',
      whereArgs: [year, month],
    );
    if (rows.isEmpty) return const [];
    final spentByCategory = await _txRepo.sumExpenseByCategories(year, month);
    return rows
        .map(Budget.fromJson)
        .map((b) => b.copyWith(spent: spentByCategory[b.categoryId] ?? 0))
        .toList();
  }

  Future<Budget?> find(String categoryId, int year, int month) async {
    final rows = await _db.query(
      _table,
      where: 'category_id = ? AND year = ? AND month = ?',
      whereArgs: [categoryId, year, month],
    );
    return rows.isEmpty ? null : Budget.fromJson(rows.first);
  }

  /// Sets the category's budget for the month, updating it if one exists
  /// (each category has at most one budget per month). Returns true when a
  /// new budget was created.
  Future<bool> upsert({
    required String categoryId,
    required int year,
    required int month,
    required double amount,
  }) async {
    final now = DateTime.now();
    final existing = await find(categoryId, year, month);
    if (existing != null) {
      await _db.update(
        _table,
        {'amount': toCents(amount), 'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return false;
    }
    await _db.insert(
      _table,
      Budget(
        id: const Uuid().v4(),
        categoryId: categoryId,
        amount: amount,
        month: month,
        year: year,
        createdAt: now,
        updatedAt: now,
      ).toJson(),
    );
    return true;
  }

  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteByCategory(String categoryId) {
    return _db.delete(_table, where: 'category_id = ?', whereArgs: [categoryId]);
  }
}
