"""
Apurse dev database server — backs the app's "remote" storage mode, which
exists only in debug builds (see lib/core/database/storage_config.dart).

Run:  pip install flask && python tools/dev_server.py
Then switch Settings → 开发调试 → 数据库 in a debug build. The Android
emulator reaches this machine's 127.0.0.1 as 10.0.2.2.

There is no authentication, so the server listens on 127.0.0.1 only and
accepts just the app's tables and column names. Don't expose it.
"""
import os
import re
import sqlite3

from flask import Flask, abort, jsonify, request

app = Flask(__name__)
DB = os.path.join(os.path.dirname(__file__), 'apurse_dev.db')
HOST, PORT = '127.0.0.1', 5000

# Must match the app's schema (lib/core/database/database_helper.dart, v5).
# Money columns hold integer cents.
SCHEMA = '''
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, icon_code INTEGER NOT NULL,
        color_value INTEGER NOT NULL DEFAULT 0xFFD4914A,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        sort_order INTEGER NOT NULL DEFAULT 0, is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
        initial_balance INTEGER, icon_code INTEGER NOT NULL DEFAULT 0,
        color_value INTEGER NOT NULL DEFAULT 0xFF4A90D9,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY, amount INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        category_id TEXT NOT NULL REFERENCES categories(id),
        date TEXT NOT NULL, note TEXT,
        account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        amount INTEGER NOT NULL, month INTEGER NOT NULL, year INTEGER NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        UNIQUE(category_id, month, year)
    );
    CREATE TABLE IF NOT EXISTS bills (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, amount INTEGER NOT NULL,
        category_id TEXT NOT NULL REFERENCES categories(id),
        due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
        is_recurring INTEGER NOT NULL DEFAULT 1, is_paid INTEGER NOT NULL DEFAULT 0,
        last_paid_period TEXT, notification_id INTEGER,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
'''

TABLES = {'categories', 'accounts', 'transactions', 'budgets', 'bills'}
IDENT = re.compile(r'^[a-z_]+$')
# WHERE / ORDER BY fragments the repositories send: identifiers, ?, simple
# comparison operators, AND, ASC/DESC and commas — never literal values.
FRAGMENT = re.compile(r'^[a-z_,\s?=<>!]*$', re.IGNORECASE)


def get_db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys = ON')
    return conn


def init_db():
    with get_db() as conn:
        conn.executescript(SCHEMA)


def table_name(data):
    table = data.get('table')
    if table not in TABLES:
        abort(400, f'unknown table {table!r}')
    return table


def identifiers(names):
    for name in names:
        if not IDENT.match(name):
            abort(400, f'bad column name {name!r}')
    return names


def fragment(text):
    if text and not FRAGMENT.match(text):
        abort(400, f'unsupported clause {text!r}')
    return text


@app.route('/query', methods=['POST'])
def query():
    data = request.get_json()
    table = table_name(data)
    columns = identifiers(data.get('columns') or [])
    where = fragment(data.get('where'))
    order_by = fragment(data.get('orderBy'))
    limit = data.get('limit')

    sql = f'SELECT {", ".join(columns) if columns else "*"} FROM {table}'
    if where:
        sql += f' WHERE {where}'
    if order_by:
        sql += f' ORDER BY {order_by}'
    if limit is not None:
        sql += f' LIMIT {int(limit)}'

    with get_db() as conn:
        rows = conn.execute(sql, data.get('whereArgs', [])).fetchall()
    return jsonify([dict(r) for r in rows])


@app.route('/raw_query', methods=['POST'])
def raw_query():
    """Read-only aggregate queries (SUM ... GROUP BY) from the repositories."""
    data = request.get_json()
    sql = data['sql']
    if not sql.lstrip().upper().startswith('SELECT') or ';' in sql:
        abort(400, 'only single SELECT statements are allowed')
    with get_db() as conn:
        conn.execute('PRAGMA query_only = ON')
        rows = conn.execute(sql, data.get('args', [])).fetchall()
    return jsonify([dict(r) for r in rows])


@app.route('/insert', methods=['POST'])
def insert():
    data = request.get_json()
    table = table_name(data)
    row = data['row']
    columns = identifiers(list(row.keys()))
    sql = (f'INSERT INTO {table} ({", ".join(columns)}) '
           f'VALUES ({", ".join("?" for _ in columns)})')
    with get_db() as conn:
        conn.execute(sql, list(row.values()))
    return jsonify({'id': row.get('id', 'ok')})


@app.route('/update', methods=['POST'])
def update():
    data = request.get_json()
    table = table_name(data)
    row = data['row']
    sets = ', '.join(f'{k} = ?' for k in identifiers(list(row.keys())))
    sql = f'UPDATE {table} SET {sets}'
    args = list(row.values())
    where = fragment(data.get('where'))
    if where:
        sql += f' WHERE {where}'
        args.extend(data.get('whereArgs', []))
    with get_db() as conn:
        cur = conn.execute(sql, args)
    return jsonify({'count': cur.rowcount})


@app.route('/delete', methods=['POST'])
def delete():
    data = request.get_json()
    table = table_name(data)
    sql = f'DELETE FROM {table}'
    where = fragment(data.get('where'))
    if where:
        sql += f' WHERE {where}'
    with get_db() as conn:
        cur = conn.execute(sql, data.get('whereArgs', []))
    return jsonify({'count': cur.rowcount})


@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    init_db()
    print(f'Apurse dev server on http://{HOST}:{PORT}  (db: {DB})')
    app.run(host=HOST, port=PORT, debug=False)
