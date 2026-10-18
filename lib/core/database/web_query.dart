/// Tiny evaluator for the SQL fragments the repositories issue, used by the
/// web storage backend, which keeps each table as a JSON list.
///
/// WHERE supports `col <op> ?` conditions joined by AND, with op one of
/// `=`, `!=`, `>=`, `<=`, `>`, `<`. Anything else throws, so a query the web
/// backend can't evaluate fails loudly instead of matching the wrong rows.
library;

final _condition = RegExp(r'^\s*(\w+)\s*(>=|<=|!=|=|>|<)\s*\?\s*$');
final _and = RegExp(r'\s+AND\s+', caseSensitive: false);

bool matchesWhere(
  Map<String, dynamic> row,
  String where,
  List<dynamic> args,
) {
  final conditions = where.trim().split(_and);
  if (conditions.length != args.length) {
    throw ArgumentError(
        'WHERE "$where" has ${conditions.length} placeholders, got ${args.length} args');
  }
  for (var i = 0; i < conditions.length; i++) {
    final match = _condition.firstMatch(conditions[i]);
    if (match == null) {
      throw UnsupportedError(
          'Web storage cannot evaluate WHERE condition "${conditions[i]}"');
    }
    final value = row[match.group(1)];
    final arg = args[i];
    // SQL semantics: any comparison with NULL is false.
    if (value == null || arg == null) return false;
    final cmp = compareValues(value, arg);
    final ok = switch (match.group(2)) {
      '=' => cmp == 0,
      '!=' => cmp != 0,
      '>=' => cmp >= 0,
      '<=' => cmp <= 0,
      '>' => cmp > 0,
      '<' => cmp < 0,
      _ => false,
    };
    if (!ok) return false;
  }
  return true;
}

/// Compares numbers numerically and everything else as strings. NULLs sort
/// last, matching how the native queries order rows.
int compareValues(dynamic a, dynamic b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  return a.toString().compareTo(b.toString());
}

/// Sorts [rows] in place by an ORDER BY clause such as
/// `"date DESC, created_at DESC"`.
void sortRows(List<Map<String, dynamic>> rows, String orderBy) {
  final keys = orderBy.split(',').map((part) {
    final tokens = part.trim().split(RegExp(r'\s+'));
    final desc = tokens.length > 1 && tokens[1].toUpperCase() == 'DESC';
    return (tokens[0], desc);
  }).toList();

  rows.sort((a, b) {
    for (final (col, desc) in keys) {
      final cmp = compareValues(a[col], b[col]);
      if (cmp != 0) return desc ? -cmp : cmp;
    }
    return 0;
  });
}
