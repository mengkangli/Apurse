import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../shared/utils/month_utils.dart';
import 'bill.dart';

class BillRepository {
  final _db = DatabaseHelper.instance;

  static const _table = DatabaseConstants.tableBills;

  /// Unpaid bills first, then by due day. Sorted in Dart because "paid"
  /// depends on the current month for recurring bills.
  Future<List<Bill>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'due_day ASC');
    final bills = rows.map(Bill.fromJson).toList();
    final now = DateTime.now();
    bills.sort((a, b) {
      final paid = (a.isPaidOn(now) ? 1 : 0) - (b.isPaidOn(now) ? 1 : 0);
      return paid != 0 ? paid : a.dueDay.compareTo(b.dueDay);
    });
    return bills;
  }

  Future<List<Bill>> getUpcoming({int days = 7}) async {
    final bills = await getAll();
    bills.sort((a, b) => a.dueDay.compareTo(b.dueDay));
    return bills.where((b) => !b.isPaid && b.daysUntilDue <= days && b.daysUntilDue >= -7).toList();
  }

  Future<void> insert(Bill bill) async {
    await _db.insert(_table, bill.toJson());
  }

  Future<void> update(Bill bill) async {
    await _db.update(_table, bill.toJson(), where: 'id = ?', whereArgs: [bill.id]);
  }

  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Marks the bill paid for [date]'s month (default: now).
  Future<void> markPaid(String id, {DateTime? date}) async {
    await _db.update(
      _table,
      {'is_paid': 1, 'last_paid_period': monthKey(date ?? DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markUnpaid(String id) async {
    await _db.update(
      _table,
      {'is_paid': 0, 'last_paid_period': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> reassignCategory(String fromCategoryId, String toCategoryId) {
    return _db.update(
      _table,
      {'category_id': toCategoryId},
      where: 'category_id = ?',
      whereArgs: [fromCategoryId],
    );
  }
}
