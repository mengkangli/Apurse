import 'package:apurse/core/database/database_helper.dart';
import 'package:apurse/core/widgets/app_icon_data.dart';
import 'package:apurse/features/budget/domain/budget_repository.dart';
import 'package:apurse/shared/utils/month_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// The schema v4 shipped with (before this change), verbatim.
Future<void> _createV4(Database db) async {
  await db.execute('''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, icon_code INTEGER NOT NULL,
      color_value INTEGER NOT NULL DEFAULT 0xFFD4914A,
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      sort_order INTEGER NOT NULL DEFAULT 0, is_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY, amount REAL NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      category_id TEXT NOT NULL, date TEXT NOT NULL, note TEXT,
      account_id TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )''');
  await db.execute('''
    CREATE TABLE budgets (
      id TEXT PRIMARY KEY, category_id TEXT NOT NULL, amount REAL NOT NULL,
      month INTEGER NOT NULL, year INTEGER NOT NULL,
      spent REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
      UNIQUE(category_id, month, year)
    )''');
  await db.execute('''
    CREATE TABLE bills (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, amount REAL NOT NULL,
      category_id TEXT NOT NULL, due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
      is_recurring INTEGER NOT NULL DEFAULT 1, is_paid INTEGER NOT NULL DEFAULT 0,
      notification_id INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
    )''');
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
      balance REAL, icon_code INTEGER NOT NULL DEFAULT 0,
      color_value INTEGER NOT NULL DEFAULT 0xFF4A90D9,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
}

Future<void> _seedV4(Database db) async {
  const t = '2026-10-01T00:00:00';
  Map<String, Object?> cat(String id, String name, String type) => {
        'id': id, 'name': name, 'icon_code': 0xe561, 'color_value': 0xFFD4914A,
        'type': type, 'sort_order': 0, 'is_default': 1, 'created_at': t, 'updated_at': t,
      };
  // v4 had no income "其他" (ic009) yet.
  await db.insert('categories', cat('ec001', '餐饮', 'expense'));
  await db.insert('categories', cat('ec016', '其他', 'expense'));
  await db.insert('categories', cat('ic001', '工资', 'income'));
  // A user category picked from the old icon picker (0xe553 = savings).
  await db.insert('categories', {
    ...cat('custom1', '存钱', 'expense'), 'icon_code': 0xe553, 'is_default': 0,
  });

  await db.insert('accounts', {
    'id': 'acc001', 'name': '微信零钱', 'type': 'wechat', 'balance': 100.5,
    'icon_code': 0xe3d9, 'color_value': 0xFF07C160, 'sort_order': 0, 'created_at': t, 'updated_at': t,
  });
  // Seeded account whose icon the user already changed.
  await db.insert('accounts', {
    'id': 'acc002', 'name': '支付宝余额', 'type': 'alipay', 'balance': 0.0,
    'icon_code': 0xe8b0, 'color_value': 0xFF1677FF, 'sort_order': 1, 'created_at': t, 'updated_at': t,
  });

  Map<String, Object?> tx(String id, double amount, String type, String cat, {String? account}) => {
        'id': id, 'amount': amount, 'type': type, 'category_id': cat, 'date': '2026-10-05',
        'note': null, 'account_id': account, 'created_at': t, 'updated_at': t,
      };
  await db.insert('transactions', tx('t1', 24.61, 'expense', 'ec001', account: 'acc001'));
  await db.insert('transactions', tx('t2', 0.1, 'expense', 'ec001'));
  await db.insert('transactions', tx('t3', 0.2, 'expense', 'ec001'));
  // Records left behind by a category deleted while FKs weren't enforced.
  await db.insert('transactions', tx('t4', 50, 'expense', 'gone'));
  await db.insert('transactions', tx('t5', 8, 'income', 'gone'));
  // Points at an account that doesn't exist.
  await db.insert('transactions', tx('t6', 1, 'expense', 'ec001', account: 'ghost'));

  await db.insert('budgets', {
    'id': 'b1', 'category_id': 'ec001', 'amount': 500.0, 'month': 10, 'year': 2026,
    'spent': 999.0, // stale stored value
    'created_at': t, 'updated_at': t,
  });
  await db.insert('budgets', {
    'id': 'b2', 'category_id': 'gone', 'amount': 1.0, 'month': 10, 'year': 2026,
    'spent': 0.0, 'created_at': t, 'updated_at': t,
  });

  Map<String, Object?> bill(String id, String cat, int paid) => {
        'id': id, 'name': id, 'amount': 3000.0, 'category_id': cat, 'due_day': 1,
        'is_recurring': 1, 'is_paid': paid, 'notification_id': null, 'created_at': t, 'updated_at': t,
      };
  await db.insert('bills', bill('rent', 'ec001', 1));
  await db.insert('bills', bill('orphan', 'gone', 0));
}

void main() {
  late String path;
  final helper = DatabaseHelper.instance;

  setUp(() async {
    path = await useFreshDatabase();
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await _createV4(db);
          await _seedV4(db);
        },
      ),
    );
    await old.close();
    await helper.resetForTesting(databasePath: path);
  });

  tearDown(() => helper.resetForTesting());

  Future<Map<String, Object?>> row(String table, String id) async =>
      (await helper.query(table, where: 'id = ?', whereArgs: [id])).single;

  test('upgrades to version 5', () async {
    final v = await helper.rawQuery('PRAGMA user_version');
    expect(v.single.values.single, 5);
  });

  test('converts money to integer cents', () async {
    final rows = await helper.rawQuery(
        "SELECT id, amount, typeof(amount) AS t FROM transactions WHERE id IN ('t1','t2','t3') ORDER BY id");
    expect(rows.map((r) => r['amount']), [2461, 10, 20]);
    expect(rows.every((r) => r['t'] == 'integer'), true);
    expect((await row('budgets', 'b1'))['amount'], 50000);
    expect((await row('bills', 'rent'))['amount'], 300000);
    expect((await row('accounts', 'acc001'))['initial_balance'], 10050);
  });

  test('re-homes orphaned records and drops orphaned budgets', () async {
    expect((await row('transactions', 't4'))['category_id'], 'ec016');
    expect((await row('transactions', 't5'))['category_id'], 'ic009');
    expect((await row('bills', 'orphan'))['category_id'], 'ec016');
    expect(await helper.query('budgets', where: 'id = ?', whereArgs: ['b2']), isEmpty);
    expect((await row('transactions', 't6'))['account_id'], isNull);
    expect((await row('transactions', 't1'))['account_id'], 'acc001');
    expect(await helper.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('drops the stored budget spent; it is computed instead', () async {
    final cols = await helper.rawQuery('PRAGMA table_info(budgets)');
    expect(cols.map((c) => c['name']), isNot(contains('spent')));
    final budget = (await BudgetRepository().getByMonth(2026, 10)).single;
    expect(budget.spent, 25.91); // t1 + t2 + t3 + t6, not the stale 999
  });

  test('a bill marked paid counts as paid for the current month', () async {
    expect((await row('bills', 'rent'))['last_paid_period'], monthKey(DateTime.now()));
    expect((await row('bills', 'orphan'))['last_paid_period'], isNull);
  });

  test('built-in icons are replaced; user-chosen icons are kept', () async {
    expect((await row('categories', 'ec001'))['icon_code'],
        AppIconData.defaultCategoryIcons['ec001']!.codePoint);
    expect((await row('categories', 'ic009'))['icon_code'],
        AppIconData.defaultCategoryIcons['ic009']!.codePoint);
    expect((await row('categories', 'custom1'))['icon_code'], 0xe553);
    expect((await row('accounts', 'acc001'))['icon_code'],
        AppIconData.defaultAccountIcons['acc001']!.codePoint);
    expect((await row('accounts', 'acc002'))['icon_code'], 0xe8b0);
  });

  test('foreign keys are enforced after the upgrade', () async {
    await expectLater(
      helper.insert('transactions', {
        'id': 'x', 'amount': 1, 'type': 'expense', 'category_id': 'nope', 'date': '2026-10-05',
        'created_at': 't', 'updated_at': 't',
      }),
      throwsA(anything),
    );
  });
}
