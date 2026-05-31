import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_constants.dart';
import 'api_client.dart';
import 'storage_config.dart';

/// Unified database API: sqflite (local) or HTTP API (remote).
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;
  SharedPreferences? _prefs;
  Future<void>? _initFuture;
  ApiClient? _apiClient;
  bool _remote = false;

  bool get isRemote => _remote;

  Future<void> ensureInit() async {
    _initFuture ??= _doInit();
    await _initFuture;
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
      if (!_prefs!.containsKey('db_${DatabaseConstants.tableCategories}')) {
        await _seedCategoriesWeb();
      }
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, DatabaseConstants.databaseName);
      _db = await openDatabase(
        path,
        version: DatabaseConstants.databaseVersion,
        onCreate: (db, version) async {
          await _createAllTables(db);
          await _seedCategoriesNative(db);
          await _seedAccountsNative(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _seedCategoriesNative(db);
          }
          if (oldVersion < 3) {
            await _upgradeToV3(db);
          }
          if (oldVersion < 4) {
            await _seedCategoriesNative(db);
          }
        },
      );
    }
  }

  /// Switch storage mode at runtime. Resets the init state.
  Future<void> switchMode(StorageMode mode) async {
    await StorageConfig.setMode(mode);
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
    if (kIsWeb) return _insertWeb(table, row);
    return _db!.insert(table, row, conflictAlgorithm: conflictAlgorithm);
  }

  Future<int> update(String table, Map<String, dynamic> row, {String? where, List<dynamic>? whereArgs}) async {
    await ensureInit();
    if (_remote) return _apiClient!.update(table, row, where: where, whereArgs: whereArgs);
    if (kIsWeb) return _updateWeb(table, row);
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

  List<Map<String, dynamic>> _queryWeb(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) {
    var rows = _readTable(table);

    if (where != null && whereArgs != null) {
      // Handle simple "col = ?" or "col >= ? AND col <= ?" etc.
      rows = _filterRows(rows, where, whereArgs);
    }

    if (orderBy != null) {
      final parts = orderBy.split(' ');
      final col = parts[0];
      final desc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
      rows.sort((a, b) => _compare(a[col], b[col], desc: desc));
    }

    if (limit != null && rows.length > limit) {
      rows = rows.sublist(0, limit);
    }
    return rows;
  }

  List<Map<String, dynamic>> _filterRows(
    List<Map<String, dynamic>> rows,
    String where,
    List<dynamic> whereArgs,
  ) {
    return rows.where((r) {
      // Very simple: replace ? with args in order
      var idx = 0;
      final conditions = where.split(' AND ');
      for (final cond in conditions) {
        final trimmed = cond.trim();
        final parts = trimmed.split('?');
        final col = parts[0].trim();
        if (col.endsWith('=')) {
          final colName = col.substring(0, col.length - 1).trim();
          if (idx >= whereArgs.length) return false;
          if (r[colName]?.toString() != whereArgs[idx]?.toString()) return false;
          idx++;
        } else if (col.endsWith('>=')) {
          final colName = col.substring(0, col.length - 2).trim();
          if (idx >= whereArgs.length) return false;
          final rv = r[colName];
          if (rv == null) return false;
          if (rv is num && whereArgs[idx] is num) {
            if (rv < (whereArgs[idx] as num)) return false;
          } else if (rv.toString().compareTo(whereArgs[idx].toString()) < 0) {
            return false;
          }
          idx++;
        } else if (col.endsWith('<=')) {
          final colName = col.substring(0, col.length - 2).trim();
          if (idx >= whereArgs.length) return false;
          final rv = r[colName];
          if (rv == null) return false;
          if (rv is num && whereArgs[idx] is num) {
            if (rv > (whereArgs[idx] as num)) return false;
          } else if (rv.toString().compareTo(whereArgs[idx].toString()) > 0) {
            return false;
          }
          idx++;
        }
      }
      return true;
    }).toList();
  }

  int _compare(dynamic a, dynamic b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final cmp = a is num ? a.compareTo(b as num) : a.toString().compareTo(b.toString());
    return desc ? -cmp : cmp;
  }

  List<Map<String, dynamic>> _rawQueryWeb(String sql, List<dynamic> args) {
    final upper = sql.toUpperCase();
    if (upper.contains('SUM(')) {
      final table = _tableFromSql(sql);
      final rows = _readTable(table);
      final sumCol = sql.split('SUM(')[1].split(')')[0].trim();
      final wherePart = _extractWhere(sql);
      var filtered = rows;
      if (wherePart != null) {
        filtered = _filterRows(filtered, wherePart, args);
      }
      final groupBy = _extractGroupBy(sql);
      if (groupBy != null) {
        final sums = <String, double>{};
        for (final row in filtered) {
          final key = row[groupBy]?.toString();
          if (key == null) continue;
          sums[key] = (sums[key] ?? 0) + ((row[sumCol] as num?)?.toDouble() ?? 0);
        }
        return sums.entries.map((entry) => {groupBy: entry.key, 'total': entry.value}).toList();
      }
      final sum = filtered.fold<double>(0, (s, r) => s + ((r[sumCol] as num?)?.toDouble() ?? 0));
      return [{'total': sum}];
    }
    return [];
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

  Future<int> _insertWeb(String table, Map<String, dynamic> row) async {
    final rows = _readTable(table);
    rows.add(row);
    await _writeTable(table, rows);
    return 1;
  }

  Future<int> _updateWeb(String table, Map<String, dynamic> row) async {
    final rows = _readTable(table);
    final idx = rows.indexWhere((r) => r['id'] == row['id']);
    if (idx >= 0) {
      rows[idx] = row;
      await _writeTable(table, rows);
      return 1;
    }
    return 0;
  }

  Future<int> _deleteWeb(String table, {String? where, List<dynamic>? whereArgs}) async {
    var rows = _readTable(table);
    final before = rows.length;
    if (where != null && whereArgs != null) {
      rows = _filterRows(rows, where, whereArgs);
      final toRemove = rows.map((r) => r['id']).toSet();
      final all = _readTable(table);
      all.removeWhere((r) => toRemove.contains(r['id']));
      await _writeTable(table, all);
      return before - all.length;
    }
    await _writeTable(table, rows);
    return 0;
  }

  // ─── Native table creation ───

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableCategories} (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, icon_code INTEGER NOT NULL,
        color_value INTEGER NOT NULL DEFAULT 0xFFD4914A,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        sort_order INTEGER NOT NULL DEFAULT 0, is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableTransactions} (
        id TEXT PRIMARY KEY, amount REAL NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        category_id TEXT NOT NULL, date TEXT NOT NULL, note TEXT,
        account_id TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_tx_date ON ${DatabaseConstants.tableTransactions}(date)');
    await db.execute('CREATE INDEX idx_tx_category ON ${DatabaseConstants.tableTransactions}(category_id)');
    await db.execute('CREATE INDEX idx_tx_type ON ${DatabaseConstants.tableTransactions}(type)');
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableBudgets} (
        id TEXT PRIMARY KEY, category_id TEXT NOT NULL, amount REAL NOT NULL,
        month INTEGER NOT NULL, year INTEGER NOT NULL,
        spent REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
        UNIQUE(category_id, month, year)
      )
    ''');
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableBills} (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, amount REAL NOT NULL,
        category_id TEXT NOT NULL, due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
        is_recurring INTEGER NOT NULL DEFAULT 1, is_paid INTEGER NOT NULL DEFAULT 0,
        notification_id INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableAccounts} (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
        balance REAL, icon_code INTEGER NOT NULL DEFAULT 0,
        color_value INTEGER NOT NULL DEFAULT 0xFF4A90D9,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedCategoriesNative(Database db) async => _seed(db, _cats(DateTime.now().toIso8601String()), DatabaseConstants.tableCategories);

  Future<void> _upgradeToV3(Database db) async {
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
    await _seed(db, _seedAccounts(DateTime.now().toIso8601String()), DatabaseConstants.tableAccounts);
  }
  Future<void> _seedCategoriesWeb() async => _writeTable(DatabaseConstants.tableCategories, _cats(DateTime.now().toIso8601String()));

  Future<void> _seed(Database db, List<Map<String, dynamic>> rows, String table) async {
    for (final row in rows) {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _seedAccountsNative(Database db) async =>
      _seed(db, _seedAccounts(DateTime.now().toIso8601String()), DatabaseConstants.tableAccounts);

  List<Map<String, dynamic>> _seedAccounts(String now) => [
    {'id': 'acc001', 'name': '微信零钱', 'type': 'wechat', 'balance': 0, 'icon_code': 0xe3d9, 'color_value': 0xFF07C160, 'sort_order': 0, 'created_at': now, 'updated_at': now},
    {'id': 'acc002', 'name': '支付宝余额', 'type': 'alipay', 'balance': 0, 'icon_code': 0xe5d2, 'color_value': 0xFF1677FF, 'sort_order': 1, 'created_at': now, 'updated_at': now},
    {'id': 'acc003', 'name': '现金', 'type': 'cash', 'balance': 0, 'icon_code': 0xe1e1, 'color_value': 0xFF795548, 'sort_order': 2, 'created_at': now, 'updated_at': now},
  ];

  List<Map<String, dynamic>> _cats(String now) => [
    // ── Income ──
    {'id': 'ic001', 'name': '工资', 'icon_code': 0xe0f2, 'color_value': 0xFF2E7D32, 'type': 'income', 'sort_order': 0, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic002', 'name': '兼职', 'icon_code': 0xe31b, 'color_value': 0xFF388E3C, 'type': 'income', 'sort_order': 1, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic003', 'name': '投资', 'icon_code': 0xe80e, 'color_value': 0xFF43A047, 'type': 'income', 'sort_order': 2, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic004', 'name': '礼金', 'icon_code': 0xe8b0, 'color_value': 0xFF66BB6A, 'type': 'income', 'sort_order': 3, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic005', 'name': '退款', 'icon_code': 0xe5d3, 'color_value': 0xFF81C784, 'type': 'income', 'sort_order': 4, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic006', 'name': '奖金', 'icon_code': 0xe565, 'color_value': 0xFF1B5E20, 'type': 'income', 'sort_order': 5, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic007', 'name': '理财', 'icon_code': 0xe80e, 'color_value': 0xFF1565C0, 'type': 'income', 'sort_order': 6, 'is_default': 1, 'created_at': now, 'updated_at': now},
    {'id': 'ic008', 'name': '副业', 'icon_code': 0xe4a3, 'color_value': 0xFF6A1B9A, 'type': 'income', 'sort_order': 7, 'is_default': 1, 'created_at': now, 'updated_at': now},
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
