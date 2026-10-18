import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../bill/domain/bill_repository.dart';
import '../../budget/domain/budget_repository.dart';
import '../../transaction/domain/transaction_repository.dart';
import 'category.dart';

class CategoryRepository {
  final _db = DatabaseHelper.instance;

  static const _table = DatabaseConstants.tableCategories;

  Future<List<Category>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'sort_order ASC');
    return rows.map(Category.fromJson).toList();
  }

  Future<List<Category>> getByType(String type) async {
    final rows = await _db.query(
      _table,
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'sort_order ASC',
    );
    return rows.map(Category.fromJson).toList();
  }

  Future<void> insert(Category category) async {
    await _db.insert(_table, category.toJson());
  }

  Future<void> update(Category category) async {
    await _db.update(
      _table,
      category.toJson(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  /// The default "其他" category that takes over a deleted category's
  /// records.
  Future<Category?> fallbackFor(String type) async {
    final id = type == 'income'
        ? DatabaseConstants.fallbackIncomeCategoryId
        : DatabaseConstants.fallbackExpenseCategoryId;
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Category.fromJson(rows.first);
  }

  /// Deletes [category] after moving its records and bills to the
  /// "其他" category of the same type; its budgets are deleted. Returns how
  /// many records were moved.
  Future<int> deleteAndReassign(Category category) async {
    final fallback = await fallbackFor(category.type);
    if (fallback == null || fallback.id == category.id) {
      throw StateError('Category ${category.id} has no fallback to move records to');
    }
    final moved = await TransactionRepository().reassignCategory(category.id, fallback.id);
    await BillRepository().reassignCategory(category.id, fallback.id);
    await BudgetRepository().deleteByCategory(category.id);
    await _db.delete(_table, where: 'id = ?', whereArgs: [category.id]);
    return moved;
  }
}
