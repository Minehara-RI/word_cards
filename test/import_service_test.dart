import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/import/import_service.dart';
import 'package:word_flashcards/src/domain/models/card_source.dart';

import 'support/test_harness.dart';

const String kThreeCards = '''
[
  {"word":"abandon","definition":"v. 放弃；抛弃","distractors":["v. 遵守","v. 维持","v. 增加","v. 分配"]},
  {"word":"meticulous","definition":"adj. 一丝不苟的","distractors":["adj. 漫不经心的","adj. 慷慨的","adj. 沉默的","adj. 固执的"]},
  {"word":"resilient","definition":"adj. 有韧性的","distractors":["adj. 易碎的","adj. 冷淡的","adj. 奢侈的","adj. 含糊的"]}
]
''';

void main() {
  late TestHarness harness;
  late ImportService service;

  setUp(() async {
    harness = await TestHarness.create();
    service = ImportService(cards: harness.cards, decks: harness.decks);
  });

  tearDown(() => harness.dispose());

  test('导入三张卡片并落库', () async {
    final report = await service.importJson(kThreeCards);
    expect(report.importedCount, 3);
    expect(report.failedCount, 0);
    expect(report.duplicateCount, 0);

    final stored = await harness.cards.getAll();
    expect(stored, hasLength(3));
    expect(
      stored.map((card) => card.word).toList()..sort(),
      <String>['abandon', 'meticulous', 'resilient'],
    );
    expect(stored.every((card) => card.source == CardSource.manualImport), isTrue);
    expect(stored.every((card) => card.distractors.length == 4), isTrue);
  });

  test('第二次导入同名单词会被跳过', () async {
    await service.importJson(kThreeCards);
    final second = await service.importJson(kThreeCards);
    expect(second.importedCount, 0);
    expect(second.duplicateCount, 3);
    expect(await harness.cards.count(), 3);
  });

  test('overwriteExisting 时覆盖已有卡片', () async {
    await service.importJson(kThreeCards);
    final updated = await service.importJson(
      '[{"word":"abandon","definition":"v. 放弃（新版释义）","distractors":["v. 遵守","v. 维持","v. 增加","v. 分配"]}]',
      overwriteExisting: true,
    );
    expect(updated.importedCount, 1);
    final stored = await harness.cards.findByWord('abandon');
    expect(stored?.definition, 'v. 放弃（新版释义）');
    expect(await harness.cards.count(), 3, reason: '覆盖不应该新增行');
  });

  test('批量导入里部分数据有问题，好的仍然入库', () async {
    final report = await service.importJson(
      '[{"word":"ok1","definition":"甲","distractors":["乙","丙","丁","戊"]},'
      '{"definition":"缺单词","distractors":["乙"]},'
      '{"word":"ok2","definition":"己","distractors":["庚","辛","壬","癸"]}]',
    );
    expect(report.importedCount, 2);
    expect(report.failedCount, 1);
    expect(report.errors.single.index, 2);
    expect(await harness.cards.count(), 2);
  });

  test('干扰项不足时从同批其他卡片补齐到 4 个', () async {
    final report = await service.importJson(
      '[{"word":"solo","definition":"adj. 单独的","distractors":["adj. 共同的"]},'
      '{"word":"other","definition":"adj. 其他的","distractors":["adj. 相同的","adj. 多数的","adj. 少数的","adj. 全部的"]}]',
    );
    expect(report.importedCount, 2);
    final solo = await harness.cards.findByWord('solo');
    expect(solo?.distractors, hasLength(4));
    expect(solo?.distractors, contains('adj. 共同的'));
  });

  test('同一批里重复的单词只导入第一张', () async {
    final report = await service.importJson(
      '[{"word":"dup","definition":"甲","distractors":["乙","丙","丁","戊"]},'
      '{"word":"DUP","definition":"己","distractors":["庚","辛","壬","癸"]}]',
    );
    expect(report.importedCount, 1);
    expect(
      report.warnings.any((warning) => warning.toLowerCase().contains('dup')),
      isTrue,
      reason: '应该提醒用户这一批里有重复单词',
    );
    final stored = await harness.cards.findByWord('dup');
    expect(stored?.definition, '甲');
  });

  test('全是坏数据时不写库并给具体错误', () async {
    final report = await service.importJson('not json at all');
    expect(report.importedCount, 0);
    expect(report.errors, isNotEmpty);
    expect(await harness.cards.count(), 0);
  });

  test('preview 不改动数据库', () async {
    final result = service.preview(kThreeCards);
    expect(result.cards, hasLength(3));
    expect(await harness.cards.count(), 0);
  });
}
