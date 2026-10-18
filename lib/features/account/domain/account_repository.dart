import '../../../core/database/database_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/money.dart';
import '../../transaction/domain/transaction_repository.dart';
import 'account.dart';

class AccountRepository {
  final _db = DatabaseHelper.instance;

  static const _table = DatabaseConstants.tableAccounts;

  Future<List<Account>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'sort_order ASC');
    return rows.map(Account.fromJson).toList();
  }

  /// Every account with current balance = initial balance + income − expenses
  /// recorded against it.
  Future<List<AccountBalance>> getAllWithBalances() async {
    final accounts = await getAll();
    final net = await TransactionRepository().netCentsByAccount();
    return [
      for (final a in accounts)
        AccountBalance(
          account: a,
          // Added in cents so 100 + 4975.39 stays 5075.39.
          balance: fromCents(toCents(a.initialBalance ?? 0) + (net[a.id] ?? 0)),
        ),
    ];
  }

  Future<Account?> getById(String id) async {
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Account.fromJson(rows.first);
  }

  Future<void> insert(Account account) async {
    await _db.insert(_table, account.toJson());
  }

  Future<void> update(Account account) async {
    await _db.update(
      _table,
      account.toJson(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  /// Deletes the account; its records stay but no longer belong to an
  /// account.
  Future<void> delete(String id) async {
    await TransactionRepository().clearAccount(id);
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
