import 'package:apurse/core/database/web_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchesWhere', () {
    final row = {'id': 't1', 'date': '2026-10-05', 'amount': 2461, 'type': 'expense', 'note': null};

    test('range conditions (>= / <=) — previously parsed as "="', () {
      expect(matchesWhere(row, 'date >= ? AND date <= ?', ['2026-10-01', '2026-10-31']), true);
      expect(matchesWhere(row, 'date >= ? AND date <= ?', ['2026-11-01', '2026-11-30']), false);
    });

    test('equality, inequality and strict comparisons', () {
      expect(matchesWhere(row, 'type = ?', ['expense']), true);
      expect(matchesWhere(row, 'type != ?', ['expense']), false);
      expect(matchesWhere(row, 'amount > ?', [2000]), true);
      expect(matchesWhere(row, 'amount < ?', [2000]), false);
      expect(matchesWhere(row, 'id = ? and type = ?', ['t1', 'expense']), true);
    });

    test('comparisons with NULL are false, as in SQL', () {
      expect(matchesWhere(row, 'note = ?', ['x']), false);
      expect(matchesWhere(row, 'note != ?', ['x']), false);
    });

    test('unsupported conditions and wrong arg counts throw', () {
      expect(() => matchesWhere(row, 'note LIKE ?', ['%a%']), throwsUnsupportedError);
      expect(() => matchesWhere(row, 'type = ? AND id = ?', ['expense']), throwsArgumentError);
    });
  });

  test('sortRows orders by several keys', () {
    final rows = [
      {'date': '2026-10-01', 'created_at': 'b'},
      {'date': '2026-10-02', 'created_at': 'a'},
      {'date': '2026-10-01', 'created_at': 'c'},
    ];
    sortRows(rows, 'date DESC, created_at DESC');
    expect(rows.map((r) => '${r['date']}/${r['created_at']}'),
        ['2026-10-02/a', '2026-10-01/c', '2026-10-01/b']);
  });
}
