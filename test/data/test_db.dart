import 'dart:io';

import 'package:apurse/core/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points [DatabaseHelper] at a fresh SQLite file in a temp dir, using the
/// FFI implementation so tests run on the host without a device.
Future<String> useFreshDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});
  final dir = await Directory.systemTemp.createTemp('apurse_test_');
  final path = p.join(dir.path, 'apurse.db');
  await DatabaseHelper.instance.resetForTesting(databasePath: path);
  return path;
}
