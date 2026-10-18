import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_icon_data.dart';
import '../../shared/utils/month_utils.dart';
import 'database_constants.dart';
import 'api_client.dart';
import 'storage_config.dart';
import 'web_query.dart';

/// Unified database API: sqflite (local), SharedPreferences JSON tables
/// (web) or the HTTP dev server (remote, debug builds only).
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;
  SharedPreferences? _prefs;
  Future<void>? _initFuture;
  ApiClient? _apiClient;
  bool _remote = false;
  String? _pathOverride;

  bool get isRemote => _remote;

  static const _webVersionKey = 'db_schema_version';

  Future<void> ensureInit() async {
    _initFuture ??= _doInit();
    await _initFuture;
  }

  /// Closes the current database and points the helper at [databasePath]
  /// (a file opened through whatever `databaseFactory` the test installed).
  @visibleForTesting
  Future<void> resetForTesting({String? databasePath}) async {
    await _db?.close();
    _db = null;
    _prefs = null;
    _apiClient = null;
    _remote = false;
    _initFuture = null;
    _pathOverride = databasePath;
  }

  Future<void> _doInit() async {
    final mode = await StorageConfig.getMode();
    if (mode == StorageMode.remote) {
      _remote = true;
      _apiClient = ApiClient(baseUrl: StorageConfig.remoteUrl);
      return;
    }
    _remote = false;
    if (kIsWeb) {
      _prefs = await SharedPreferences.getInstance();
      await _initWeb();
      return;
    }
    final path = _pathOverride ??
        join(await getDatabasesPath(), DatabaseConstants.databaseName);
    _db = await openDatabase(
      path,
      version: DatabaseConstants.databaseVersion,
      // SQLite ignores FOREIGN KEY clauses unless this is on per connection.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createAllTables(db);
        final now = DateTime.now().toIso8601String();
        await _insertAll(db, DatabaseConstants.tableCategories, _cats(now));
        await _insertAll(db, DatabaseConstants.tableAccounts, _seedAccounts(now));
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _refreshDefaultCategories(db);
        if (oldVersion < 3) await _upgradeToV3(db);
        if (oldVersion < 4) await _refreshDefaultCategories(db);
        if (oldVersion < 5) await _upgradeToV5(db);
      },
    );
  }

  /// Switch storage mode at runtime. Resets the init state.
  Future<void> switchMode(StorageMode mode) async {
    await StorageConfig.setMode(mode);
    await _db?.close();
    _initFuture = null;
    _db = null;
    _apiClient = null;
    _remote = false;
    await ensureInit();
  }

  // ─── Unified API ───

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    await ensureInit();
    if (_remote) return _apiClient!.query(table, columns: columns, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
    if (kIsWeb) return _queryWeb(table, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
    final rows = await _db!.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    await ensureInit();
    if (_remote) return _apiClient!.rawQuery(sql, args);
    if (kIsWeb) return _rawQueryWeb(sql, args ?? []);
    final rows = await _db!.rawQuery(sql, args);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<int> insert(String table, Map<String, dynamic> row, {ConflictAlgorithm? conflictAlgorithm}) async {
    await ensureInit();
    if (_remote) return _apiClient!.insert(table, row);
    if (kIsWeb) return _insertWeb(table, row, conflictAlgorithm: conflictAlgorithm);
    return _db!.insert(table, row, conflictAlgorithm: conflictAlgorithm);
  }

  Future<int> update(String table, Map<String, dynamic> row, {String? where, List<dynamic>? whereArgs}) async {
    await ensureInit();
    if (_remote) return _apiClient!.update(table, row, where: where, whereArgs: whereArgs);
    if (kIsWeb) return _updateWeb(table, row, where: where, whereArgs: whereArgs);
    return _db!.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, {String? where, List<dynamic>? whereArgs}) async {
    await ensureInit();
    if (_remote) return _apiClient!.delete(table, where: where, whereArgs: whereArgs);
    if (kIsWeb) return _deleteWeb(table, where: where, whereArgs: whereArgs);
    return _db!.delete(table, where: where, whereArgs: whereArgs);
  }

  // ─── Web implementation ───

  List<Map<String, dynamic>> _readTable(String table) {
    final jsonStr = _prefs!.getString('db_$table');
    if (jsonStr == null) return [];
    try {
      return (jsonDecode(jsonStr) as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeTable(String table, List<Map<String, dynamic>> rows) async {
    await _prefs!.setString('db_$table', jsonEncode(rows));
  }

  Future<void> _initWeb() async {
    final version = _prefs!.getInt(_webVersionKey) ??
        // Installs before v5 never stored a version; they seeded categories.
        (_prefs!.containsKey('db_${DatabaseConstants.tableCategories}') ? 4 : 0);
    if (version == 0) {
      final now = DateTime.now().toIso8601String();
      await _writeTable(DatabaseConstants.tableCategories, _cats(now));
      await _writeTable(DatabaseConstants.tableAccounts, _seedAccounts(now));
    } else if (version < 5) {
      await _migrateWebToV5();
    }
    await _prefs!.setInt(_webVersionKey, DatabaseConstants.databaseVersion);
  }

  /// Same changes as [_upgradeToV5], applied to the JSON tables.
  Future<void> _migrateWebToV5() async {
    final now = DateTime.now().toIso8601String();
    int? cents(dynamic v) => v == null ? null : ((v as num) * 100).round();

    final categories = _readTable(DatabaseConstants.tableCategories);
    for (final fallback in _cats(now).where(_isFallbackCategory)) {
      if (!categories.any((c) => c['id'] == fallback['id'])) categories.add(fallback);
    }
    for (final c in categories) {
      final icon = AppIconData.defaultCategoryIcons[c['id']];
      if (icon != null) c['icon_code'] = icon.codePoint;
    }
    await _writeTable(DatabaseConstants.tableCategories, categories);
    final categoryIds = categories.map((c) => c['id']).toSet();

    final accounts = _readTable(DatabaseConstants.tableAccounts);
    if (accounts.isEmpty) accounts.addAll(_seedAccounts(now));
    for (final a in accounts) {
      if (a.containsKey('balance')) a['initial_balance'] = cents(a.remove('balance'));
      final icon = AppIconData.defaultAccountIcons[a['id']];
      if (icon != null && a['icon_code'] == _legacyAccountIcons[a['id']]) {
        a['icon_code'] = icon.codePoint;
      }
    }
    await _writeTable(DatabaseConstants.tableAccounts, accounts);

    final transactions = _readTable(DatabaseConstants.tableTransactions);
    for (final t in transactions) {
      t['amount'] = cents(t['amount']);
      if (!categoryIds.contains(t['category_id'])) {
        t['category_id'] = t['type'] == 'income'
            ? DatabaseConstants.fallbackIncomeCategoryId
            : DatabaseConstants.fallbackExpenseCategoryId;
      }
    }
    await _writeTable(DatabaseConstants.tableTransactions, transactions);

    final budgets = _readTable(DatabaseConstants.tableBudgets)
      ..removeWhere((b) => !categoryIds.contains(b['category_id']));
    for (final b in budgets) {
      b['amount'] = cents(b['amount']);
      b.remove('spent');
    }
    await _writeTable(DatabaseConstants.tableBudgets, budgets);

    final bills = _readTable(DatabaseConstants.tableBills);
    for (final b in bills) {
      b['amount'] = cents(b['amount']);
      b['last_paid_period'] = b['is_paid'] == 1 ? monthKey(DateTime.now()) : null;
      if (!categoryIds.contains(b['category_id'])) {
        b['category_id'] = DatabaseConstants.fallbackExpenseCategoryId;
      }
    }
    await _writeTable(DatabaseConstants.tableBills, bills);
  }

  List<Map<String, dynamic>> _queryWeb(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) {
    var rows = _readTable(table);
    if (where != null) {
      rows = rows.where((r) => matchesWhere(r, where, whereArgs ?? const [])).toList();
    }
    if (orderBy != null) sortRows(rows, orderBy);
    if (limit != null && rows.length > limit) {
      rows = rows.sublist(0, limit);
    }
    return rows;
  }

  /// Supports `SELECT [col,] SUM(x) as total FROM t [WHERE ...] [GROUP BY col]`,
  /// the only raw query shape the repositories use.
  List<Map<String, dynamic>> _rawQueryWeb(String sql, List<dynamic> args) {
    final sumMatch = RegExp(r'SUM\((\w+)\)', caseSensitive: false).firstMatch(sql);
    if (sumMatch == null) {
      throw UnsupportedError('Web storage cannot run raw query: $sql');
    }
    final sumCol = sumMatch.group(1)!;
    var rows = _readTable(_tableFromSql(sql));
    final wherePart = _extractWhere(sql);
    if (wherePart != null) {
      rows = rows.where((r) => matchesWhere(r, wherePart, args)).toList();
    }
    final groupBy = _extractGroupBy(sql);
    if (groupBy != null) {
      final sums = <String?, num>{};
      for (final row in rows) {
        final key = row[groupBy]?.toString();
        sums[key] = (sums[key] ?? 0) + ((row[sumCol] as num?) ?? 0);
      }
      return sums.entries.map((e) => {groupBy: e.key, 'total': e.value}).toList();
    }
    if (rows.isEmpty) return [{'total': null}];
    final sum = rows.fold<num>(0, (s, r) => s + ((r[sumCol] as num?) ?? 0));
    return [{'total': sum}];
  }

  String _tableFromSql(String sql) {
    final m = RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
    return m?.group(1) ?? '';
  }

  String? _extractWhere(String sql) {
    final upper = sql.toUpperCase();
    final idx = upper.indexOf('WHERE');
    if (idx < 0) return null;
    var wherePart = sql.substring(idx + 5);
    final orderIdx = wherePart.toUpperCase().indexOf('ORDER BY');
    if (orderIdx >= 0) wherePart = wherePart.substring(0, orderIdx);
    final groupIdx = wherePart.toUpperCase().indexOf('GROUP BY');
    if (groupIdx >= 0) wherePart = wherePart.substring(0, groupIdx);
    return wherePart.trim();
  }

  String? _extractGroupBy(String sql) {
    final match = RegExp(r'GROUP\s+BY\s+(\w+)', caseSensitive: false).firstMatch(sql);
    return match?.group(1);
  }

  Future<int> _insertWeb(
    String table,
    Map<String, dynamic> row, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final rows = _readTable(table);
    final idx = rows.indexWhere((r) => r['id'] == row['id']);
    if (idx >= 0) {
      if (conflictAlgorithm == ConflictAlgorithm.ignore) return 0;
      if (conflictAlgorithm != ConflictAlgorithm.replace) {
        throw StateError('Duplicate id ${row['id']} in $table');
      }
      rows[idx] = Map<String, dynamic>.from(row);
    } else {
      rows.add(Map<String, dynamic>.from(row));
    }
    await _writeTable(table, rows);
    return 1;
  }

  /// Merges [values] into every matching row, like SQL `UPDATE ... SET`.
  Future<int> _updateWeb(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final rows = _readTable(table);
    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      final match = where == null || matchesWhere(rows[i], where, whereArgs ?? const []);
      if (match) {
        rows[i] = {...rows[i], ...values};
        count++;
      }
    }
    if (count > 0) await _writeTable(table, rows);
    return count;
  }

  Future<int> _deleteWeb(String table, {String? where, List<dynamic>? whereArgs}) async {
    final rows = _readTable(table);
    final before = rows.length;
    if (where == null) {
      rows.clear();
    } else {
      rows.removeWhere((r) => matchesWhere(r, where, whereArgs ?? const []));
    }
    await _writeTable(table, rows);
    return before - rows.length;
  }

  // ─── Native schema ───

  static String _categoriesDdl() => '''
    CREATE TABLE ${DatabaseConstants.tableCategories} (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, icon_code INTEGER NOT NULL,
      color_value INTEGER NOT NULL DEFAULT 0xFFD4914A,
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      sort_order INTEGER NOT NULL DEFAULT 0, is_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''';

  static String _accountsDdl(String table) => '''
    CREATE TABLE $table (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
      initial_balance INTEGER, icon_code INTEGER NOT NULL DEFAULT 0,
      color_value INTEGER NOT NULL DEFAULT 0xFF4A90D9,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''';

  static String _transactionsDdl(String table) => '''
    CREATE TABLE $table (
      id TEXT PRIMARY KEY, amount INTEGER NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      category_id TEXT NOT NULL, date TEXT NOT NULL, note TEXT,
      account_id TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id),
      FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
    )''';

  static String _budgetsDdl(String table) => '''
    CREATE TABLE $table (
      id TEXT PRIMARY KEY, category_id TEXT NOT NULL, amount INTEGER NOT NULL,
      month INTEGER NOT NULL, year INTEGER NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
      UNIQUE(category_id, month, year)
    )''';

  static String _billsDdl(String table) => '''
    CREATE TABLE $table (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, amount INTEGER NOT NULL,
      category_id TEXT NOT NULL, due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
      is_recurring INTEGER NOT NULL DEFAULT 1, is_paid INTEGER NOT NULL DEFAULT 0,
      last_paid_period TEXT,
      notification_id INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )''';

  static Future<void> _createTransactionIndexes(Database db) async {
    const t = DatabaseConstants.tableTransactions;
    await db.execute('CREATE INDEX idx_tx_date ON $t(date)');
    await db.execute('CREATE INDEX idx_tx_category ON $t(category_id)');
    await db.execute('CREATE INDEX idx_tx_type ON $t(type)');
    await db.execute('CREATE INDEX idx_tx_account ON $t(account_id)');
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute(_categoriesDdl());
    await db.execute(_accountsDdl(DatabaseConstants.tableAccounts));
    await db.execute(_transactionsDdl(DatabaseConstants.tableTransactions));
    await _createTransactionIndexes(db);
    await db.execute(_budgetsDdl(DatabaseConstants.tableBudgets));
    await db.execute(_billsDdl(DatabaseConstants.tableBills));
  }

  // ─── Native migrations ───

  /// Re-applies the default categories' names, icons and colors (what the
  /// v2 and v4 upgrades did). An UPDATE-then-INSERT instead of REPLACE: with
  /// foreign keys on, REPLACE deletes the row first and would cascade to
  /// that category's budgets.
  Future<void> _refreshDefaultCategories(Database db) async {
    for (final row in _cats(DateTime.now().toIso8601String())) {
      final values = Map<String, dynamic>.from(row)..remove('id')..remove('created_at');
      final changed = await db.update(DatabaseConstants.tableCategories, values,
          where: 'id = ?', whereArgs: [row['id']]);
      if (changed == 0) await db.insert(DatabaseConstants.tableCategories, row);
    }
  }

  Future<void> _upgradeToV3(Database db) async {
    // The v3 schema; v5 rebuilds this table with initial_balance in cents.
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableAccounts} (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
        balance REAL, icon_code INTEGER NOT NULL DEFAULT 0,
        color_value INTEGER NOT NULL DEFAULT 0xFF4A90D9,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableTransactions} ADD COLUMN account_id TEXT');
    final legacyAccounts = _seedAccounts(DateTime.now().toIso8601String())
        .map((r) => Map<String, dynamic>.from(r)
          ..remove('initial_balance')
          ..['balance'] = 0)
        .toList();
    await _insertAll(db, DatabaseConstants.tableAccounts, legacyAccounts);
  }

  /// Money → integer cents, drop the stored budgets.spent, add
  /// bills.last_paid_period and rename accounts.balance → initial_balance.
  /// SQLite can't change a column's type in place, so each money table is
  /// rebuilt: create the new table, copy, drop the old one, rename.
  Future<void> _upgradeToV5(Database db) async {
    const fbExpense = DatabaseConstants.fallbackExpenseCategoryId;
    const fbIncome = DatabaseConstants.fallbackIncomeCategoryId;
    final now = DateTime.now().toIso8601String();

    for (final row in _cats(now).where(_isFallbackCategory)) {
      await db.insert(DatabaseConstants.tableCategories, row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Before v5 foreign keys weren't enforced, so deleting a category left
    // its records pointing nowhere. Re-home them before the new tables
    // (which do enforce the keys) receive the rows.
    await db.execute(
      "UPDATE transactions SET category_id = CASE type WHEN 'income' THEN ? ELSE ? END "
      'WHERE category_id NOT IN (SELECT id FROM categories)',
      [fbIncome, fbExpense],
    );
    await db.execute(
      'UPDATE bills SET category_id = ? WHERE category_id NOT IN (SELECT id FROM categories)',
      [fbExpense],
    );
    await db.execute('DELETE FROM budgets WHERE category_id NOT IN (SELECT id FROM categories)');

    // Accounts first: the new transactions table references it.
    await db.execute(_accountsDdl('accounts_v5'));
    await db.execute('''
      INSERT INTO accounts_v5 (id, name, type, initial_balance, icon_code, color_value, sort_order, created_at, updated_at)
      SELECT id, name, type, CAST(ROUND(balance * 100) AS INTEGER), icon_code, color_value, sort_order, created_at, updated_at
      FROM accounts
    ''');
    await db.execute('DROP TABLE accounts');
    await db.execute('ALTER TABLE accounts_v5 RENAME TO accounts');

    await db.execute(_transactionsDdl('transactions_v5'));
    await db.execute('''
      INSERT INTO transactions_v5 (id, amount, type, category_id, date, note, account_id, created_at, updated_at)
      SELECT id, CAST(ROUND(amount * 100) AS INTEGER), type, category_id, date, note,
             CASE WHEN account_id IN (SELECT id FROM accounts) THEN account_id END,
             created_at, updated_at
      FROM transactions
    ''');
    await db.execute('DROP TABLE transactions');
    await db.execute('ALTER TABLE transactions_v5 RENAME TO transactions');
    await _createTransactionIndexes(db);

    await db.execute(_budgetsDdl('budgets_v5'));
    await db.execute('''
      INSERT INTO budgets_v5 (id, category_id, amount, month, year, created_at, updated_at)
      SELECT id, category_id, CAST(ROUND(amount * 100) AS INTEGER), month, year, created_at, updated_at
      FROM budgets
    ''');
    await db.execute('DROP TABLE budgets');
    await db.execute('ALTER TABLE budgets_v5 RENAME TO budgets');

    // A bill marked paid counts as paid for the current month only, so
    // recurring bills come back next month.
    await db.execute(_billsDdl('bills_v5'));
    await db.execute('''
      INSERT INTO bills_v5 (id, name, amount, category_id, due_day, is_recurring, is_paid, last_paid_period, notification_id, created_at, updated_at)
      SELECT id, name, CAST(ROUND(amount * 100) AS INTEGER), category_id, due_day, is_recurring, is_paid,
             CASE WHEN is_paid = 1 THEN ? END, notification_id, created_at, updated_at
      FROM bills
    ''', [monthKey(DateTime.now())]);
    await db.execute('DROP TABLE bills');
    await db.execute('ALTER TABLE bills_v5 RENAME TO bills');

    // The built-in categories' icon codes pointed at unrelated glyphs (餐饮
    // showed "screen share"). Defaults can't be edited, so overwrite them;
    // seeded accounts only if the user hasn't changed the icon.
    for (final MapEntry(key: id, value: icon) in AppIconData.defaultCategoryIcons.entries) {
      await db.update(DatabaseConstants.tableCategories, {'icon_code': icon.codePoint},
          where: 'id = ?', whereArgs: [id]);
    }
    for (final MapEntry(key: id, value: icon) in AppIconData.defaultAccountIcons.entries) {
      await db.update(DatabaseConstants.tableAccounts, {'icon_code': icon.codePoint},
          where: 'id = ? AND icon_code = ?', whereArgs: [id, _legacyAccountIcons[id]]);
    }
  }

  /// Icon codes the accounts were seeded with before v5.
  static const _legacyAccountIcons = {'acc001': 0xe3d9, 'acc002': 0xe5d2, 'acc003': 0xe1e1};

  // ─── Seed data ───

  Future<void> _insertAll(Database db, String table, List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await db.insert(table, row);
    }
  }

  static bool _isFallbackCategory(Map<String, dynamic> row) =>
      row['id'] == DatabaseConstants.fallbackExpenseCategoryId ||
      row['id'] == DatabaseConstants.fallbackIncomeCategoryId;

  /// Seed rows with icons from [AppIconData.defaultAccountIcons].
  List<Map<String, dynamic>> _seedAccounts(String now) => [
        for (final row in _seedAccountRows(now))
          {...row, 'icon_code': AppIconData.defaultAccountIcons[row['id']]!.codePoint},
      ];

  List<Map<String, dynamic>> _seedAccountRows(String now) => [
    {'id': 'acc001', 'name': '微信零钱', 'type': 'wechat', 'initial_balance': 0, 'icon_code': 0xe3d9, 'color_value': 0xFF07C160, 'sort_order': 0, 'created_at': now, 'updated_at': now},
    {'id': 'acc002', 'name': '支付宝余额', 'type': 'alipay', 'initial_balance': 0, 'icon_code': 0xe5d2, 'color_value': 0xFF1677FF, 'sort_order': 1, 'created_at': now, 'updated_at': now},
    {'id': 'acc003', 'name': '现金', 'type': 'cash', 'initial_balance': 0, 'icon_code': 0xe1e1, 'color_value': 0xFF795548, 'sort_order': 2, 'created_at': now, 'updated_at': now},
  ];

  /// Default categories with icons from [AppIconData.defaultCategoryIcons].
  List<Map<String, dynamic>> _cats(String now) => [
        for (final row in _catRows(now))
          {...row, 'icon_code': AppIconData.defaultCategoryIcons[row['id']]!.codePoint},
      ];

  List<Map<String, dynamic>> _catRows(String now) => [
    // ── Income ──
    {'id': 'ic001', 'name': '工资', 'icon_code': 0xe0f2, 'color_value': 0xFF2E7D32, 'type': 'income', 'sort_order': 0, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic002', 'name': '兼职', 'icon_code': 0xe31b, 'color_value': 0xFF388E3C, 'type': 'income', 'sort_order': 1, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic003', 'name': '投资', 'icon_code': 0xe80e, 'color_value': 0xFF43A047, 'type': 'income', 'sort_order': 2, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic004', 'name': '礼金', 'icon_code': 0xe8b0, 'color_value': 0xFF66BB6A, 'type': 'income', 'sort_order': 3, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic005', 'name': '退款', 'icon_code': 0xe5d3, 'color_value': 0xFF81C784, 'type': 'income', 'sort_order': 4, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic006', 'name': '奖金', 'icon_code': 0xe565, 'color_value': 0xFF1B5E20, 'type': 'income', 'sort_order': 5, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic007', 'name': '理财', 'icon_code': 0xe80e, 'color_value': 0xFF1565C0, 'type': 'income', 'sort_order': 6, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic008', 'name': '副业', 'icon_code': 0xe4a3, 'color_value': 0xFF6A1B9A, 'type': 'income', 'sort_order': 7, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic009', 'name': '其他', 'icon_code': 0xe5d2, 'color_value': 0xFF78909C, 'type': 'income', 'sort_order': 8, 'is_default': 1, 'created_at': now, 'updated_at': now},
    // ── Expense ──
    {'id': 'ec001', 'name': '餐饮', 'icon_code': 0xe561, 'color_value': 0xFFD4914A, 'type': 'expense', 'sort_order': 0, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec002', 'name': '交通', 'icon_code': 0xe531, 'color_value': 0xFF795548, 'type': 'expense', 'sort_order': 1, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec003', 'name': '购物', 'icon_code': 0xe54f, 'color_value': 0xFF7B1FA2, 'type': 'expense', 'sort_order': 2, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec004', 'name': '娱乐', 'icon_code': 0xe02c, 'color_value': 0xFFE64A19, 'type': 'expense', 'sort_order': 3, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec005', 'name': '账单', 'icon_code': 0xe328, 'color_value': 0xFF546E7A, 'type': 'expense', 'sort_order': 4, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec006', 'name': '医疗', 'icon_code': 0xe548, 'color_value': 0xFFD32F2F, 'type': 'expense', 'sort_order': 5, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec007', 'name': '教育', 'icon_code': 0xe227, 'color_value': 0xFF1976D2, 'type': 'expense', 'sort_order': 6, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec008', 'name': '居住', 'icon_code': 0xe0af, 'color_value': 0xFFF57C00, 'type': 'expense', 'sort_order': 7, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec009', 'name': '日用', 'icon_code': 0xe16d, 'color_value': 0xFF00838F, 'type': 'expense', 'sort_order': 8, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec010', 'name': '通讯', 'icon_code': 0xe0cf, 'color_value': 0xFF0277BD, 'type': 'expense', 'sort_order': 9, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec011', 'name': '服饰', 'icon_code': 0xe422, 'color_value': 0xFFC2185B, 'type': 'expense', 'sort_order': 10, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec012', 'name': '数码', 'icon_code': 0xe323, 'color_value': 0xFF455A64, 'type': 'expense', 'sort_order': 11, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec013', 'name': '运动', 'icon_code': 0xe3b0, 'color_value': 0xFF00695C, 'type': 'expense', 'sort_order': 12, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec014', 'name': '宠物', 'icon_code': 0xe7ec, 'color_value': 0xFF8D6E63, 'type': 'expense', 'sort_order': 13, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec015', 'name': '居家', 'icon_code': 0xe751, 'color_value': 0xFFE65100, 'type': 'expense', 'sort_order': 14, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec016', 'name': '其他', 'icon_code': 0xe5d2, 'color_value': 0xFF78909C, 'type': 'expense', 'sort_order': 15, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec017', 'name': '订阅', 'icon_code': 0xe627, 'color_value': 0xFF00897B, 'type': 'expense', 'sort_order': 16, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ec018', 'name': '学习', 'icon_code': 0xe80c, 'color_value': 0xFF283593, 'type': 'expense', 'sort_order': 17, 'is_default': 1, 'created_at': now, 'updated_at': now},
  ];
}
