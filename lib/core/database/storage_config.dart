import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StorageMode { local, remote }

class StorageConfig {
  static const _key = 'storage_mode';

  /// Remote mode talks to `tools/dev_server.py`, which has no auth and runs
  /// plain HTTP, so it exists only in debug builds. Release builds always
  /// use local storage even if the preference was set during development.
  static bool get remoteAvailable => kDebugMode;

  static Future<StorageMode> getMode() async {
    if (!remoteAvailable) return StorageMode.local;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key) ?? 'local';
    return value == 'remote' ? StorageMode.remote : StorageMode.local;
  }

  static Future<void> setMode(StorageMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == StorageMode.remote ? 'remote' : 'local');
  }

  /// Dev server URL. 10.0.2.2 is the host machine as seen from the Android
  /// emulator; the server binds to 127.0.0.1 on the host.
  static String remoteUrl = 'http://10.0.2.2:5000';
}
