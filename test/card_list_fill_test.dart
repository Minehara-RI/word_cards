// 卡片列表里的「一键补全」：单张按钮 + 批量入口。
// 模型那一层换成假服务，不发真实请求。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/data/ai/card_completion.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/cached_generation.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/domain/repositories.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/state/server_providers.dart';
import 'package:word_flashcards/src/ui/pages/card_list_page.dart';

import 'support/test_harness.dart';

/// 假补全服务：接口是现成的，只是不发请求。
class _FakeCompletionService extends CardCompletionService {
  _FakeCompletionService()
      : super(client: _NoClient(), cache: _NoCache());

  int calls = 0;

  @override
  Future<CardCompletionOutcome> complete({
    required String word,
    required String definition,
    required CardLanguage language,
    required AppSettings settings,
    String? existingPhonetic,
    String? existingPartOfSpeech,
    String? existingExample,
    String? existingNote,
    List<String> existingDistractors = const <String>[],
  }) async {
    calls++;
    return const CardCompletionOutcome(
      cacheKey: 'k',
      completion: CardCompletion(
        phonetic: '/test/',
        partOfSpeech: 'verb',
        example: 'An example.',
        note: '一个记忆点',
        distractors: <String>['a', 'b', 'c', 'd'],
      ),
    );
  }
}

class _NoClient implements AiApiClient {
  @override
  Future<AiCompletion> complete(AiRequest request) async =>
      throw UnimplementedError('测试里不走真实请求');

  @override
  void close() {}
}

class _NoCache implements ApiCacheRepository {
  @override
  Future<CachedGeneration?> read(
    String key, {
    required DateTime now,
    required Duration ttl,
  }) async =>
      null;

  @override
  Future<void> write(CachedGeneration entry) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<int> count() async => 0;
}

WordCard _bareCard() => WordCard(
      id: 'c1',
      word: 'abandon',
      definition: 'v. 放弃；抛弃',
      distractors: const <String>[],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Widget _wrap(TestHarness harness, Widget child, CardCompletionService service) {
  return ProviderScope(
    overrides: [
      cardRepositoryProvider.overrideWithValue(harness.cards),
      answerRecordRepositoryProvider.overrideWithValue(harness.records),
      deckRepositoryProvider.overrideWithValue(harness.decks),
      settingsRepositoryProvider.overrideWithValue(harness.settings),
      apiCacheRepositoryProvider.overrideWithValue(harness.cache),
      syncRepositoryProvider.overrideWithValue(harness.sync),
      cardCompletionServiceProvider.overrideWithValue(service),
    ],
    child: child,
  );
}

void main() {
  testWidgets('单张补全：点一下就把空着的项补上', (WidgetTester tester) async {
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsert(_bareCard());
    await harness.settings.save(const AppSettings(
      apiBaseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      apiModel: 'm',
    ));
    final _FakeCompletionService service = _FakeCompletionService();

    await tester.pumpWidget(
      _wrap(harness, const MaterialApp(home: CardListPage()), service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card-fill-c1')));
    await tester.pumpAndSettle();

    final WordCard? card = await harness.cards.getById('c1');
    expect(card!.phonetic, '/test/');
    expect(card.distractors, hasLength(4));
    expect(find.textContaining('已补全'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('没配 API 时点补全，告诉用户去设置页配', (WidgetTester tester) async {
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsert(_bareCard());
    final _FakeCompletionService service = _FakeCompletionService();

    await tester.pumpWidget(
      _wrap(harness, const MaterialApp(home: CardListPage()), service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card-fill-c1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('设置页配好 API'), findsOneWidget);
    expect(service.calls, 0);
  });

  testWidgets('批量补全：先问范围，补完给一句总结', (WidgetTester tester) async {
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsert(_bareCard());
    await harness.settings.save(const AppSettings(
      apiBaseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      apiModel: 'm',
    ));
    final _FakeCompletionService service = _FakeCompletionService();

    await tester.pumpWidget(
      _wrap(harness, const MaterialApp(home: CardListPage()), service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card-batch-fill')));
    await tester.pumpAndSettle();

    expect(find.text('批量补全'), findsOneWidget);
    expect(find.text('缺音标'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fill-scope-phonetic')));
    await tester.pumpAndSettle();

    final WordCard? card = await harness.cards.getById('c1');
    expect(card!.phonetic, '/test/');
    expect(find.textContaining('补全完成'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('没有缺项的卡时，批量对话框里的「缺音标」点不动', (WidgetTester tester) async {
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon'));
    await harness.settings.save(const AppSettings(
      apiBaseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      apiModel: 'm',
    ));
    final _FakeCompletionService service = _FakeCompletionService();

    await tester.pumpWidget(
      _wrap(harness, const MaterialApp(home: CardListPage()), service),
    );
    await tester.pumpAndSettle();

    // 默认 makeCard 音标与干扰项都齐 → 批量对话框里「缺音标」是 0，点不动。
    await tester.tap(find.byKey(const Key('card-batch-fill')));
    await tester.pumpAndSettle();
    expect(find.text('批量补全'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fill-scope-phonetic')));
    await tester.pumpAndSettle();
    expect(find.text('批量补全'), findsOneWidget);
    expect(service.calls, 0);
  });
}
