import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/money.dart';
import '../../../shared/utils/month_utils.dart';
import 'transaction.dart';

class TransactionRepository {
  final _db = DatabaseHelper.instance;

  static const _table = DatabaseConstants.tableTransactions;

  Future<List<Transaction>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'date DESC, created_at DESC');
    return rows.map(Transaction.fromJson).toList();
  }

  Future<Transaction?> getById(String id) async {
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Transaction.fromJson(rows.first);
  }

  Future<List<Transaction>> getByMonth(int year, int month) async {
    final (startDate, endDate) = monthDateRange(year, month);
    final rows = await _db.query(
      _table,
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Transaction.fromJson).toList();
  }

  Future<double> sumByMonth(int year, int month, String type) async {
    final (startDate, endDate) = monthDateRange(year, month);
    final result = await _db.rawQuery(
      'SELECT SUM(amount) as total FROM $_table '
      'WHERE type = ? AND date >= ? AND date <= ?',
      [type, startDate, endDate],
    );
    return fromCents((result.first['total'] as num?) ?? 0);
  }

  Future<Map<String, double>> sumExpenseByCategories(int year, int month) async {
    final (startDate, endDate) = monthDateRange(year, month);
    final result = await _db.rawQuery(
      'SELECT category_id, SUM(amount) as total FROM $_table '
      'WHERE type = ? AND date >= ? AND date <= ? GROUP BY category_id',
      ['expense', startDate, endDate],
    );
    return {
      for (final row in result)
        if (row['category_id'] != null)
          row['category_id'] as String: fromCents(row['total'] as num),
    };
  }

  Future<double> sumByCategory(String categoryId, int year, int month, String type) async {
    final (startDate, endDate) = monthDateRange(year, month);
    final result = await _db.rawQuery(
      'SELECT SUM(amount) as total FROM $_table '
      'WHERE type = ? AND category_id = ? AND date >= ? AND date <= ?',
      [type, categoryId, startDate, endDate],
    );
    return fromCents((result.first['total'] as num?) ?? 0);
  }

  /// Income minus expenses per account id in cents, over all time. Records
  /// without an account are left out.
  Future<Map<String, int>> netCentsByAccount() async {
    final net = <String, int>{};
    for (final (type, sign) in [('income', 1), ('expense', -1)]) {
      final rows = await _db.rawQuery(
        'SELECT account_id, SUM(amount) as total FROM $_table '
        'WHERE type = ? GROUP BY account_id',
        [type],
      );
      for (final row in rows) {
        final id = row['account_id'] as String?;
        if (id == null) continue;
        net[id] = (net[id] ?? 0) + sign * (row['total'] as num).toInt();
      }
    }
    return net;
  }

  Future<int> countByCategory(String categoryId) async {
    final rows = await _db.query(
      _table,
      columns: ['id'],
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
    return rows.length;
  }

  /// Moves every record in [fromCategoryId] to [toCategoryId].
  Future<int> reassignCategory(String fromCategoryId, String toCategoryId) {
    return _db.update(
      _table,
      {'category_id': toCategoryId},
      where: 'category_id = ?',
      whereArgs: [fromCategoryId],
    );
  }

  /// Unlinks records from a deleted account.
  Future<int> clearAccount(String accountId) {
    return _db.update(
      _table,
      {'account_id': null},
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  Future<List<Transaction>> getRecent({int limit = 5}) async {
    final rows = await _db.query(
      _table,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromJson).toList();
  }

  Future<void> insert(Transaction tx) async {
    await _db.insert(_table, tx.toJson());
  }

  Future<void> update(Transaction tx) async {
    await _db.update(_table, tx.toJson(), where: 'id = ?', whereArgs: [tx.id]);
  }

  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
