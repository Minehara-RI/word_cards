/// 卡片的来源方式。
///
/// 两种模式生成的数据结构完全一致，入库后不再区分使用方式，
/// [source] 仅用于统计与排查（例如“这张卡是 API 生成的还是粘贴导入的”）。
enum CardSource {
  manualImport('manual_import', '手动导入'),
  api('api', 'API 生成');

  const CardSource(this.id, this.label);

  /// 持久化用的稳定标识，不要随枚举名变化。
  final String id;

  /// 界面上展示的中文名。
  final String label;

  static CardSource fromId(Object? value) {
    if (value is String) {
      for (final source in CardSource.values) {
        if (source.id == value || source.name == value) return source;
      }
    }
    return CardSource.manualImport;
  }
}
