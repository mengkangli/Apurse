import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Client for the debug-only dev server (`tools/dev_server.py`).
class ApiClient {
  final String baseUrl;
  final Duration timeout;

  ApiClient({required this.baseUrl, this.timeout = const Duration(seconds: 10)});

  Future<bool> healthCheck() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/health')).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final body = <String, dynamic>{'table': table};
    if (columns != null) body['columns'] = columns;
    if (where != null) body['where'] = where;
    if (whereArgs != null) body['whereArgs'] = whereArgs;
    if (orderBy != null) body['orderBy'] = orderBy;
    if (limit != null) body['limit'] = limit;
    return _parseList(await _post('query', body));
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    return _parseList(await _post('raw_query', {'sql': sql, 'args': args ?? []}));
  }

  Future<int> insert(String table, Map<String, dynamic> row) async {
    await _post('insert', {'table': table, 'row': row});
    return 1;
  }

  Future<int> update(
    String table,
    Map<String, dynamic> row, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final body = <String, dynamic>{'table': table, 'row': row};
    if (where != null) body['where'] = where;
    if (whereArgs != null) body['whereArgs'] = whereArgs;
    final data = jsonDecode(await _post('update', body)) as Map<String, dynamic>;
    return data['count'] as int;
  }

  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final body = <String, dynamic>{'table': table};
    if (where != null) body['where'] = where;
    if (whereArgs != null) body['whereArgs'] = whereArgs;
    final data = jsonDecode(await _post('delete', body)) as Map<String, dynamic>;
    return data['count'] as int;
  }

  Future<String> _post(String endpoint, Map<String, dynamic> body) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw ApiException('Dev server /$endpoint failed: ${resp.statusCode} ${resp.body}');
    }
    return resp.body;
  }

  List<Map<String, dynamic>> _parseList(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }
}
