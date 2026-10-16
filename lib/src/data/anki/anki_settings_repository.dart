import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';

/// 配置仓库的 Anki 实现。
///
/// 应用自己的配置（API Key、主题、限时……）不适合塞进 Anki 的 col.conf，
/// 所以单独放在 wc_settings 表里；Anki 会忽略不认识的表。
class AnkiSettingsRepository implements SettingsRepository {
  AnkiSettingsRepository(this._collection);

  final AnkiCollection _collection;

  static const String _key = 'app_settings';

  @override
  Stream<AppSettings> watch() => _collection.watchValue(load);

  @override
  Future<AppSettings> load() async {
    final ResultSet rows = _collection.db.select(
      'select value from wc_settings where key = ?',
      <Object?>[_key],
    );
    if (rows.isEmpty) return const AppSettings();
    final Object? decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is Map) {
      return AppSettings.fromMap(decoded.cast<String, Object?>());
    }
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) async {
    _collection.db.execute(
      'insert or replace into wc_settings (key, value) values (?,?)',
      <Object?>[_key, jsonEncode(settings.toMap())],
    );
    _collection.notify();
  }
}
