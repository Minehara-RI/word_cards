import 'package:sembast/sembast.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

/// 配置是单文档存储，固定用这个 key。
class SembastSettingsRepository implements SettingsRepository {
  SembastSettingsRepository(this._database);

  final AppDatabase _database;

  static const String _key = 'app_settings';

  Database get _db => _database.db;

  @override
  Stream<AppSettings> watch() => AppDatabase.settings
      .record(_key)
      .onSnapshot(_db)
      .map((snapshot) =>
          snapshot == null ? const AppSettings() : AppSettings.fromMap(snapshot.value));

  @override
  Future<AppSettings> load() async {
    final value = await AppDatabase.settings.record(_key).get(_db);
    return value == null ? const AppSettings() : AppSettings.fromMap(value);
  }

  @override
  Future<void> save(AppSettings settings) =>
      AppDatabase.settings.record(_key).put(_db, settings.toMap());
}
