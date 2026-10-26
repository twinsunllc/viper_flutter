// What Viper remembers on the phone, per install and per key: where the launcher sits and whether
// it's hidden (D335), the panel's last state (D108), the theme (D279), and unsent reports (D165).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Strings kept on the phone.
abstract interface class ViperStore {
  /// The value at [key], or null.
  Future<String?> read(String key);

  /// Keeps [value] at [key]; null removes it.
  Future<void> write(String key, String? value);
}

/// [ViperStore] over shared_preferences.
class PreferencesStore implements ViperStore {
  /// The store.
  PreferencesStore();

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) => value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}

/// [ViperStore] in memory, for tests.
class MemoryStore implements ViperStore {
  /// An empty store, or one holding [values].
  MemoryStore([Map<String, String>? values]) : values = values ?? <String, String>{};

  /// What's kept.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

/// JSON helpers over a [ViperStore].
extension ViperStoreJson on ViperStore {
  /// The JSON object at [key], or null when there's none or it doesn't read.
  Future<Map<String, Object?>?> readJson(String key) async {
    final raw = await read(key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// Keeps [value] as JSON at [key]; null removes it.
  Future<void> writeJson(String key, Map<String, Object?>? value) =>
      write(key, value == null ? null : jsonEncode(value));
}
