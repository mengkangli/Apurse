import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import 'budget.dart';

class BudgetRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Budget>> getByMonth(int year, int month) async {
    final rows = await _db.query(
      DatabaseConstants.tableBudgets,
      where: 'year = ? AND month = ?',
      whereArgs: [year, month],
    );
    return rows.map(Budget.fromJson).toList();
  }

  Future<void> insert(Budget budget) async {
    await _db.insert(DatabaseConstants.tableBudgets, budget.toJson());
  }

  Future<void> update(Budget budget) async {
    await _db.update(
      DatabaseConstants.tableBudgets,
      budget.toJson(),
      where: 'id = ?',
      whereArgs: [budget.id],
    );
  }

  Future<void> delete(String id) async {
    await _db.delete(
      DatabaseConstants.tableBudgets,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recalculateSpent({
    required String categoryId, required int year, required int month,
  }) async {
    final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final endDate = '$year-${month.toString().padLeft(2, '0')}-$lastDay';

    final result = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM ${DatabaseConstants.tableTransactions} '
      'WHERE category_id = ? AND type = ? AND date >= ? AND date <= ?',
      [categoryId, 'expense', startDate, endDate],
    );
    final spent = (result.first['total'] as num).toDouble();

    final rows = await _db.query(
      DatabaseConstants.tableBudgets,
      where: 'category_id = ? AND year = ? AND month = ?',
      whereArgs: [categoryId, year, month],
    );
    for (final row in rows) {
      await _db.update(
        DatabaseConstants.tableBudgets,
        {'spent': spent},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}
