// 音标口音（英式 / 美式）：只改「要 AI 生成音标时怎么说」，
// 已经进库的音标一个字节都不动，其它语言的注音方式也不受影响。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/data/ai/card_completion.dart';
import 'package:word_flashcards/src/data/ai/generation_service.dart';
import 'package:word_flashcards/src/data/ai/prompt_templates.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';

import 'support/test_harness.dart';

/// 配好 API、口音选英式的一整套设置。
const AppSettings kBritish = AppSettings(
  apiBaseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  apiModel: 'test-model',
  phoneticAccent: PhoneticAccent.british,
);

/// 记下最后一次请求的 Prompt，用来断言口音真的发出去了。
class CapturingClient implements AiApiClient {
  CapturingClient(this.reply);

  final String reply;
  AiRequest? lastRequest;

  @override
  Future<AiCompletion> complete(AiRequest request) async {
    lastRequest = request;
    return AiCompletion(
      content: reply,
      model: 'test-model',
      promptTokens: 10,
      completionTokens: 5,
    );
  }

  @override
  void close() {}
}

void main() {
  group('语言与口音', () {
    test('英语默认美式，换成英式就换一种说法', () {
      expect(CardLanguage.english.phoneticHint(), contains('美式音标'));
      final String british = CardLanguage.english
          .phoneticHint(accent: PhoneticAccent.british);
      expect(british, contains('英式音标'));
      expect(british, isNot(contains('美式音标')));
      // 两种标法在界面上要有明显不同，设置页拿 water 当例子
      expect(PhoneticAccent.british.example, isNot(PhoneticAccent.american.example));
    });

    test('其它语言的注音方式与口音无关', () {
      for (final CardLanguage language in CardLanguage.values) {
        if (language == CardLanguage.english) continue;
        expect(
          language.phoneticHint(accent: PhoneticAccent.british),
          language.phoneticHint(),
          reason: '${language.label}不该受口音影响',
        );
      }
      expect(CardLanguage.japanese.phoneticHint(), contains('平假名'));
      expect(CardLanguage.russian.phoneticHint(), contains('国际音标'));
    });
  });

  group('Prompt', () {
    test('生成模板里的音标要求跟着口音变', () {
      final PromptTemplate template = kPromptTemplates.first;
      final String british = template.build(
        'water',
        accent: PhoneticAccent.british,
      );
      final String american = template.build('water');
      expect(british, contains('英式音标'));
      expect(american, contains('美式音标'));
      expect(british, isNot(american));
    });

    test('AI 补全的 Prompt 也跟着变', () {
      String promptFor(PhoneticAccent accent) => buildCompletionPrompt(
            word: 'water',
            definition: 'n. 水',
            language: CardLanguage.english,
            accent: accent,
          );
      expect(promptFor(PhoneticAccent.british), contains('英式音标'));
      expect(promptFor(PhoneticAccent.american), contains('美式音标'));
    });

    test('日语的补全 Prompt 不带英式/美式字样', () {
      final String prompt = buildCompletionPrompt(
        word: '水泳',
        definition: 'n. 游泳',
        language: CardLanguage.japanese,
        accent: PhoneticAccent.british,
      );
      expect(prompt, contains('平假名'));
      expect(prompt, isNot(contains('英式音标')));
    });
  });

  group('服务层', () {
    test('生成请求里的音标要求来自设置', () async {
      final TestHarness harness = TestHarness.fake();
      final CapturingClient client = CapturingClient(
        '{"word":"water","definition":"n. 水",'
        '"distractors":["n. 火","n. 土","n. 风","n. 木"],'
        '"phonetic":"/ˈwɔːtə/","example":"I drink water."}',
      );
      final GenerationService service = GenerationService(
        client: client,
        cache: harness.cache,
        clock: () => DateTime(2026, 3, 1),
      );

      await service.generate(
        words: 'water',
        template: kPromptTemplates.first,
        language: CardLanguage.english,
        settings: kBritish,
      );

      expect(client.lastRequest!.prompt, contains('英式音标'));
      expect(client.lastRequest!.prompt, isNot(contains('美式音标')));
    });

    test('AI 补全的请求也带着口音', () async {
      final TestHarness harness = TestHarness.fake();
      final CapturingClient client = CapturingClient(
        '{"phonetic":"/ˈwɔːtə/","partOfSpeech":"noun","example":"I drink water.",'
        '"note":"water 是不可数名词","distractors":["n. 火","n. 土","n. 风","n. 木"]}',
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: harness.cache,
        clock: () => DateTime(2026, 3, 1),
      );

      await service.complete(
        word: 'water',
        definition: 'n. 水',
        language: CardLanguage.english,
        settings: kBritish,
      );

      expect(client.lastRequest!.prompt, contains('英式音标'));
    });
  });

  group('设置', () {
    test('存得住；老库（没有这个键）默认美式', () {
      const AppSettings saved = AppSettings(
        phoneticAccent: PhoneticAccent.british,
      );
      expect(
        AppSettings.fromMap(saved.toMap()).phoneticAccent,
        PhoneticAccent.british,
      );
      expect(
        AppSettings.fromMap(<String, Object?>{}).phoneticAccent,
        PhoneticAccent.american,
      );
      expect(
        AppSettings.fromMap(<String, Object?>{'phonetic_accent': 'british'})
            .phoneticAccent,
        PhoneticAccent.british,
      );
      // 认不出的值退回默认，而不是抛错
      expect(
        AppSettings.fromMap(<String, Object?>{'phonetic_accent': '???'})
            .phoneticAccent,
        PhoneticAccent.american,
      );
    });

    testWidgets('设置页点「英式」会写进设置', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardRepositoryProvider.overrideWithValue(harness.cards),
            answerRecordRepositoryProvider.overrideWithValue(harness.records),
            deckRepositoryProvider.overrideWithValue(harness.decks),
            settingsRepositoryProvider.overrideWithValue(harness.settings),
            apiCacheRepositoryProvider.overrideWithValue(harness.cache),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder british = find.descendant(
        of: find.byKey(const Key('phonetic-accent')),
        matching: find.text('英式'),
      );
      await tester.ensureVisible(british);
      await tester.tap(british);
      await tester.pumpAndSettle();

      expect(
        (await harness.settings.load()).phoneticAccent,
        PhoneticAccent.british,
      );
      // 下面那行说明也跟着换成 DJ 音标
      expect(find.textContaining('DJ 音标'), findsOneWidget);
    });
  });
}
