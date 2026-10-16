import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// 生成卡片、答题记录等实体的唯一 id。
String newId() => _uuid.v4();

/// 可注入的时钟，方便单元测试里固定时间。
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();
