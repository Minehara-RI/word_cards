import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

/// 本地数据库的打开/关闭与 store 定义。
///
/// 卡片、答题记录、词库、配置全部落在**本机**的一个文件里，
/// 不做任何云端同步。
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static final StoreRef<String, Map<String, Object?>> cards =
      stringMapStoreFactory.store('cards');
  static final StoreRef<String, Map<String, Object?>> records =
      stringMapStoreFactory.store('answer_records');
  static final StoreRef<String, Map<String, Object?>> decks =
      stringMapStoreFactory.store('decks');
  static final StoreRef<String, Map<String, Object?>> settings =
      stringMapStoreFactory.store('settings');

  static const int schemaVersion = 1;
  static const String fileName = 'word_cards.db';

  /// 在指定文件路径打开数据库；测试里用 [openInMemory]。
  static Future<AppDatabase> openAt(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final DatabaseFactory effective = factory ?? databaseFactoryIo;
    final db = await effective.openDatabase(
      path,
      version: schemaVersion,
      // sembast 是按需建 store 的；将来要迁移数据结构时在这里做。
      onVersionChanged: (Database db, int oldVersion, int newVersion) async {},
    );
    return AppDatabase._(db);
  }

  /// 纯内存库，供单元测试与“不落盘”的临时会话使用。
  static Future<AppDatabase> openInMemory() =>
      openAt(sembastInMemoryDatabasePath, factory: databaseFactoryMemory);

  /// 应用默认库：放在系统给应用的数据目录里。
  static Future<AppDatabase> openDefault() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, fileName);
    return openAt(path);
  }

  Future<void> close() => db.close();
}
