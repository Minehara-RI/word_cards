// 「给已有卡片一键补全」：只填空着的项、不覆盖用户写过的内容。
// 不发真实请求：模型那一层用 FakeClient 顶掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/data/ai/card_completion.dart';
import 'package:word_flashcards/src/data/ai/card_filler.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';

import 'support/fake_api_cache.dart';

class FakeClient implements AiApiClient {
  FakeClient(this.reply);

  final AiCompletion Function(AiRequest request) reply;
  int calls = 0;
  String lastPrompt = '';

  @override
  Future<AiCompletion> complete(AiRequest request) async {
    calls++;
    lastPrompt = request.prompt;
    return reply(request);
  }

  @override
  void close() {}
}

const String kReply = '{"phonetic":"/əˈbændən/","partOfSpeech":"verb",'
    '"example":"He abandoned the plan.","note":"丢下乐队自己走了",'
    '"distractors":["v. 遵守；坚持","v. 维持；供养","v. 增加；扩大","v. 分配；指派"]}';

const AppSettings kConfigured = AppSettings(
  apiBaseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  apiModel: 'test-model',
  apiCacheHours: 24,
);

WordCard card({
  String? phonetic,
  String? partOfSpeech,
  String? example,
  String? note,
  List<String> distractors = const <String>[],
  List<String> tags = const <String>[],
}) =>
    WordCard(
      id: 'c1',
      word: 'abandon',
      definition: 'v. 放弃；抛弃',
      distractors: distractors,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      example: example,
      note: note,
      tags: tags,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  late FakeApiCacheRepository cache;
  late FakeClient client;
  late CardCompletionService service;

  setUp(() {
    cache = FakeApiCacheRepository();
    client = FakeClient(
      (_) => const AiCompletion(content: kReply, model: 'test-model'),
    );
    service = CardCompletionService(client: client, cache: cache);
  });

  group('缺项判断', () {
    test('音标 / 词性 / 例句 / 备注 / 干扰项任一为空都算缺项', () {
      expect(needsAiFill(card()), isTrue);
      expect(missingPhonetic(card(phonetic: '/x/')), isFalse);
      expect(missingDistractors(card(distractors: <String>['a', 'b', 'c', 'd'])),
          isFalse);
      expect(
        needsAiFill(card(
          phonetic: '/x/',
          partOfSpeech: 'verb',
          example: 'x',
          note: 'y',
          distractors: <String>['a', 'b', 'c', 'd'],
        )),
        isFalse,
      );
    });
  });

  group('补全一张已有卡片', () {
    test('空着的项全部补上，并推进 updatedAt', () async {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: card(),
      );
      expect(outcome.ok, isTrue);
      expect(outcome.changed, isTrue);
      expect(outcome.filled, <String>['音标', '词性', '例句', '备注', '干扰项']);
      final WordCard filled = outcome.card;
      expect(filled.phonetic, '/əˈbændən/');
      expect(filled.partOfSpeech, 'verb');
      expect(filled.example, contains('abandoned'));
      expect(filled.note, contains('乐队'));
      expect(filled.distractors, hasLength(4));
      expect(filled.updatedAt.isAfter(DateTime(2026, 1, 1)), isTrue);
    });

    test('用户已经写过的音标 / 例句一个字节都不动', () async {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: card(phonetic: '/əˈbændən/ 我自己的标法/', example: '我写的例句'),
      );
      expect(outcome.card.phonetic, '/əˈbændən/ 我自己的标法/');
      expect(outcome.card.example, '我写的例句');
      expect(outcome.filled, isNot(contains('音标')));
      expect(outcome.filled, isNot(contains('例句')));
      expect(outcome.filled, contains('词性'));
    });

    test('干扰项不会把正确释义也算进去，也不会重复', () async {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: card(
          distractors: <String>['v. 放弃；抛弃', 'v. 遵守；坚持'],
        ),
      );
      final List<String> distractors = outcome.card.distractors;
      expect(distractors, isNot(contains('v. 放弃；抛弃')));
      expect(distractors.where((String d) => d == 'v. 遵守；坚持').length, 1);
      expect(distractors, hasLength(4));
    });

    test('干扰项凑够 4 个就把「待补全」标签摘掉', () async {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: card(tags: <String>[WordCard.incompleteTag, 'Unit1']),
      );
      expect(outcome.card.distractors, hasLength(4));
      expect(outcome.card.tags, isNot(contains(WordCard.incompleteTag)));
      expect(outcome.card.tags, contains('Unit1'));
    });

    test('没有可补的项时原样返回，不当成「改过」', () async {
      final WordCard complete = card(
        phonetic: '/x/',
        partOfSpeech: 'verb',
        example: 'x',
        note: 'y',
        distractors: <String>['a', 'b', 'c', 'd'],
      );
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: complete,
      );
      expect(outcome.changed, isFalse);
      expect(outcome.card.updatedAt, complete.updatedAt);
      expect(outcome.message, '这张卡没有要补的项');
    });

    test('没配 API 时给出「去哪配」，不抛异常', () async {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: service,
        settings: const AppSettings(),
        card: card(),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.changed, isFalse);
      expect(outcome.failure!.kind, AiFailureKind.notConfigured);
      expect(outcome.message, contains('设置页'));
      expect(client.calls, 0);
    });

    test('语言跟着卡片走（日语卡片用日语的 Prompt）', () async {
      final WordCard japanese = WordCard(
        id: 'j1',
        word: '私',
        definition: '我',
        distractors: const <String>[],
        language: CardLanguage.japanese,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await fillCardWithAi(
        service: service,
        settings: kConfigured,
        card: japanese,
      );
      expect(client.calls, 1);
      final String prompt = client.lastPrompt;
      expect(prompt, contains('日语'));
    });
  });
}
