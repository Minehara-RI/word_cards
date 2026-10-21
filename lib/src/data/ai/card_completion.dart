// 私有字段没法用 this._x 形式的具名参数，这里按仓库里其它文件的惯例关掉这条提示。
// ignore_for_file: prefer_initializing_formals
//
// 「AI 补全」：把已经填好的单词 + 释义送给大模型，只补齐非必填项。
//
// 刻意**只走 API**：这里没有「复制 Prompt 去网页聊天」这条退路。
// 补全的结果要直接落进输入框，复制粘贴那套做法等于让用户自己抄一遍，
// 还不如手填。没配 API 时按钮会给一句明确的下一步，不降级。

import 'dart:convert';

import '../../core/ids.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/cached_generation.dart';
import '../../domain/repositories.dart';
import 'api_client.dart';
import 'generation_service.dart';
import 'prompt_templates.dart';

/// 模型补齐的那几个非必填项。
class CardCompletion {
  const CardCompletion({
    this.phonetic,
    this.partOfSpeech,
    this.example,
    this.note,
    this.distractors = const <String>[],
  });

  final String? phonetic;
  final String? partOfSpeech;
  final String? example;
  final String? note;
  final List<String> distractors;

  bool get isEmpty =>
      phonetic == null &&
      partOfSpeech == null &&
      example == null &&
      note == null &&
      distractors.isEmpty;

  /// 补齐了几项（界面上的「补全完成：音标、例句…」用它）。
  List<String> get filledLabels => <String>[
        if (phonetic != null) '音标',
        if (partOfSpeech != null) '词性',
        if (example != null) '例句',
        if (note != null) '备注',
        if (distractors.isNotEmpty) '干扰项',
      ];

  /// 从模型原文里抠出字段。允许代码块、前后废话、尾随逗号。
  static CardCompletion? parse(String raw) {
    final Map<String, Object?>? map = _extractObject(raw);
    if (map == null) return null;

    final String? phonetic = _text(map, <String>['phonetic', 'ipa', 'pronunciation']);
    final String? partOfSpeech = _text(
      map,
      <String>['partOfSpeech', 'part_of_speech', 'pos', 'partofspeech'],
    );
    final String? example = _text(map, <String>['example', 'sentence', 'exampleSentence']);
    final String? note = _text(map, <String>['note', 'notes', 'mnemonic', 'tip']);

    final List<String> distractors = _stringList(
      map['distractors'] ?? map['distractor'] ?? map['options'],
    );

    final CardCompletion completion = CardCompletion(
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      example: example,
      note: note,
      distractors: distractors,
    );
    return completion.isEmpty ? null : completion;
  }

  static String? _text(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.isNotEmpty) {
        final String joined = value
            .map((Object? item) => (item ?? '').toString().trim())
            .where((String item) => item.isNotEmpty)
            .join('；');
        if (joined.isNotEmpty) return joined;
      }
    }
    return null;
  }

  static List<String> _stringList(Object? value) {
    final List<String> result = <String>[];
    Iterable<Object?> items;
    if (value is List) {
      items = value;
    } else if (value is String) {
      items = value.split(RegExp(r'[\n,，;；、]+'));
    } else {
      return const <String>[];
    }
    for (final Object? item in items) {
      final String text = (item ?? '').toString().trim();
      if (text.isEmpty) continue;
      if (result.any((String existing) =>
          existing.toLowerCase() == text.toLowerCase())) {
        continue;
      }
      result.add(text);
    }
    return result;
  }

  static Map<String, Object?>? _extractObject(String raw) {
    String text = raw.trim();
    if (text.isEmpty) return null;

    // 模型爱把 JSON 包在代码块里。
    final RegExpMatch? fenced =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fenced != null) text = fenced.group(1)!.trim();

    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    text = text.substring(start, end + 1);

    final Map<String, Object?>? direct = _decodeMap(text);
    if (direct != null) return direct;

    // 尾随逗号是最常见的语法毛病，去掉再试一次。
    // 注意用 replaceAllMapped：replaceAll 不展开 $1，会把字面量「$1」塞进 JSON。
    final String repaired = text.replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (Match match) => match.group(1)!,
    );
    return _decodeMap(repaired);
  }

  static Map<String, Object?>? _decodeMap(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // 交给调用方判断，不用异常打扰用户。
    }
    return null;
  }
}

/// 一次补全的结果：成功给 [completion]，失败给 [failure]。
class CardCompletionOutcome {
  const CardCompletionOutcome({
    required this.cacheKey,
    this.completion,
    this.failure,
    this.response = '',
    this.fromCache = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  final String cacheKey;
  final CardCompletion? completion;
  final AiApiFailure? failure;
  final String response;
  final bool fromCache;
  final int promptTokens;
  final int completionTokens;

  bool get ok => completion != null;

  CardCompletionOutcome withFailure(AiApiFailure value) =>
      CardCompletionOutcome(cacheKey: cacheKey, failure: value);
}

/// 补全的编排：拼 Prompt -> 查缓存 -> 请求 -> 解析 -> 写缓存。
class CardCompletionService {
  CardCompletionService({
    required AiApiClient client,
    required ApiCacheRepository cache,
    Clock clock = systemClock,
    this.temperature = 0.4,
  })  : _client = client,
        _cache = cache,
        _clock = clock;

  final AiApiClient _client;
  final ApiCacheRepository _cache;
  final Clock _clock;

  /// 补全要一点创造力（干扰项、记忆提示），但不能胡编事实。
  final double temperature;

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
    final String w = word.trim();
    final String d = definition.trim();
    if (w.isEmpty || d.isEmpty) {
      return CardCompletionOutcome(
        cacheKey: '',
        failure: const AiApiFailure(
          AiFailureKind.emptyInput,
          '先填好单词和释义',
          hint: '这两项是必填的，AI 补全只负责其余字段',
        ),
      );
    }
    if (!settings.hasApiCredentials) {
      return CardCompletionOutcome(
        cacheKey: '',
        failure: const AiApiFailure(
          AiFailureKind.notConfigured,
          '还没有配好 API',
          hint: 'AI 补全只能走 API：去设置页选一家提供商、填地址和密钥。'
              '这里不提供复制 Prompt 的做法。',
        ),
      );
    }

    final String prompt = buildCompletionPrompt(
      word: w,
      definition: d,
      language: language,
      existingPhonetic: existingPhonetic,
      existingPartOfSpeech: existingPartOfSpeech,
      existingExample: existingExample,
      existingNote: existingNote,
      existingDistractors: existingDistractors,
    );
    final String cacheKey = GenerationService.cacheKeyFor(
      baseUrl: settings.apiBaseUrl ?? '',
      model: settings.apiModel ?? '',
      prompt: prompt,
    );

    final Duration ttl = Duration(hours: settings.apiCacheHours);
    final DateTime now = _clock();
    if (ttl > Duration.zero) {
      final CachedGeneration? cached =
          await _cache.read(cacheKey, now: now, ttl: ttl);
      if (cached != null) {
        final CardCompletion? parsed = CardCompletion.parse(cached.response);
        if (parsed != null) {
          return CardCompletionOutcome(
            cacheKey: cacheKey,
            completion: parsed,
            response: cached.response,
            fromCache: true,
          );
        }
      }
    }

    AiCompletion completion;
    try {
      completion = await _client.complete(
        AiRequest(
          baseUrl: settings.apiBaseUrl ?? '',
          apiKey: settings.apiKey ?? '',
          model: settings.apiModel ?? '',
          prompt: prompt,
          timeoutSeconds: settings.apiTimeoutSeconds,
          temperature: temperature,
        ),
      );
    } on AiApiFailure catch (failure) {
      return CardCompletionOutcome(cacheKey: cacheKey, failure: failure);
    } catch (error) {
      return CardCompletionOutcome(
        cacheKey: cacheKey,
        failure: AiApiFailure(
          AiFailureKind.network,
          '补全失败：$error',
          hint: '检查网络或代理；也可以直接手填这些字段',
        ),
      );
    }

    final CardCompletion? parsed = CardCompletion.parse(completion.content);
    if (parsed == null) {
      // 解析不出来不写缓存：下次重试说不定就好了。
      return CardCompletionOutcome(
        cacheKey: cacheKey,
        response: completion.content,
        promptTokens: completion.promptTokens,
        completionTokens: completion.completionTokens,
        failure: const AiApiFailure(
          AiFailureKind.unparsable,
          '模型返回的内容里没有可用的补充',
          hint: '可以再点一次，或者换一个模型；也可以直接手填',
        ),
      );
    }

    if (ttl > Duration.zero) {
      await _cache.write(
        CachedGeneration(
          key: cacheKey,
          response: completion.content,
          model: completion.model,
          promptTokens: completion.promptTokens,
          completionTokens: completion.completionTokens,
          createdAt: now,
        ),
      );
    }

    return CardCompletionOutcome(
      cacheKey: cacheKey,
      completion: parsed,
      response: completion.content,
      promptTokens: completion.promptTokens,
      completionTokens: completion.completionTokens,
    );
  }
}
