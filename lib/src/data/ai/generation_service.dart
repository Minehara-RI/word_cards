// 私有字段没法用 this._x 形式的具名参数，这里按仓库里其它文件的惯例关掉这条提示。
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/ids.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/cached_generation.dart';
import '../../domain/models/card_language.dart';
import '../../domain/repositories.dart';
import '../import/card_parser.dart';
import 'ai_providers.dart';
import 'api_client.dart';
import 'prompt_templates.dart';

/// 一次「按单词生成卡片」的结果。
///
/// 成功与失败走同一个类型：失败时 [failure] 非空，[response] 尽量带上
/// 模型已经吐出来的原文（用户可以直接把原文贴回模式 A 手工修）。
class GenerationOutcome {
  const GenerationOutcome({
    required this.parse,
    required this.cacheKey,
    this.response = '',
    this.failure,
    this.fromCache = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.truncated = false,
  });

  /// 交给模式 A 那个容错解析器的结果。
  final ParseResult parse;

  final String cacheKey;

  /// 模型原文（从缓存命中时也是原文）。
  final String response;

  /// 失败原因；成功时为 null。
  final AiApiFailure? failure;

  /// 这次是不是直接命中了缓存（没有产生费用）。
  final bool fromCache;

  final int promptTokens;
  final int completionTokens;

  /// 模型输出被长度上限截断。
  final bool truncated;

  bool get ok => failure == null;

  int get cardCount => parse.cards.length;

  int get totalTokens => promptTokens + completionTokens;

  /// 有没有拿到原文可以贴回模式 A。
  bool get hasRawResponse => response.trim().isNotEmpty;
}

/// 「模式 B：API 直连」的编排。
///
/// 步骤固定为：拼 Prompt → 查缓存 → 请求 → 交给同一个解析器 → 写缓存。
/// 解析器、去重、入库逻辑全部复用模式 A，两种模式产出同样的数据结构。
class GenerationService {
  GenerationService({
    required AiApiClient client,
    required ApiCacheRepository cache,
    Clock clock = systemClock,
    CardParser parser = const CardParser(),
    this.temperature = 0.3,
    this.maxTokens = 0,
  })  : _client = client,
        _cache = cache,
        _clock = clock,
        _parser = parser;

  final AiApiClient _client;
  final ApiCacheRepository _cache;
  final Clock _clock;
  final CardParser _parser;

  /// 出题要用确定性高的回答，不要创作型。释义题给 0.3 就够多样了。
  final double temperature;

  /// 0 表示不传 max_tokens。
  final int maxTokens;

  /// 缓存键：地址 + 模型 + 最终 Prompt 一起哈希。
  ///
  /// 换模型、改地址、改模板（哪怕只改一个字）都会得到新键，
  /// 不会拿旧答案糊弄。
  static String cacheKeyFor({
    required String baseUrl,
    required String model,
    required String prompt,
  }) {
    final String joined = <String>[
      normalizeApiBaseUrl(baseUrl),
      model.trim(),
      prompt,
    ].join('\u0000');
    return sha256.convert(utf8.encode(joined)).toString();
  }

  Future<GenerationOutcome> generate({
    required String words,
    required PromptTemplate template,
    required CardLanguage language,
    required AppSettings settings,
  }) async {
    final String raw = words.trim();
    final String prompt = template.build(words, language: language);
    final String cacheKey = cacheKeyFor(
      baseUrl: settings.apiBaseUrl ?? '',
      model: settings.apiModel ?? '',
      prompt: prompt,
    );

    if (raw.isEmpty) {
      return GenerationOutcome(
        parse: _parser.parse(''),
        cacheKey: cacheKey,
        failure: const AiApiFailure(
          AiFailureKind.emptyInput,
          '请先输入要学的单词',
          hint: '一行一个，也可以直接粘一串用逗号或分号隔开',
        ),
      );
    }
    if (!settings.hasApiCredentials) {
      return GenerationOutcome(
        parse: _parser.parse(''),
        cacheKey: cacheKey,
        failure: const AiApiFailure(
          AiFailureKind.notConfigured,
          '还没有配好 API',
          hint: '去设置页选一家提供商、填地址和密钥；或者继续用网页聊天导入',
        ),
      );
    }

    final Duration ttl = Duration(hours: settings.apiCacheHours);
    final DateTime now = _clock();
    if (ttl > Duration.zero) {
      final CachedGeneration? cached =
          await _cache.read(cacheKey, now: now, ttl: ttl);
      if (cached != null) {
        return GenerationOutcome(
          parse: _parser.parse(cached.response),
          cacheKey: cacheKey,
          response: cached.response,
          fromCache: true,
        );
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
          maxTokens: maxTokens,
        ),
      );
    } on AiApiFailure catch (failure) {
      return GenerationOutcome(
        parse: _parser.parse(''),
        cacheKey: cacheKey,
        failure: failure,
      );
    } catch (error) {
      return GenerationOutcome(
        parse: _parser.parse(''),
        cacheKey: cacheKey,
        failure: AiApiFailure(
          AiFailureKind.network,
          '生成失败：$error',
          hint: '可以改用网页聊天导入',
        ),
      );
    }

    final ParseResult parse = _parser.parse(completion.content);
    if (parse.cards.isEmpty) {
      // 解析不出来就别写缓存：下次重试说不定就好了。
      return GenerationOutcome(
        parse: parse,
        cacheKey: cacheKey,
        response: completion.content,
        promptTokens: completion.promptTokens,
        completionTokens: completion.completionTokens,
        truncated: completion.truncated,
        failure: AiApiFailure(
          AiFailureKind.unparsable,
          parse.issues.isEmpty
              ? '模型返回的内容里没有卡片'
              : parse.issues.first.display,
          hint: '原文已经填进粘贴框，可以直接手改；也可以换一个模型再试',
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

    return GenerationOutcome(
      parse: parse,
      cacheKey: cacheKey,
      response: completion.content,
      promptTokens: completion.promptTokens,
      completionTokens: completion.completionTokens,
      truncated: completion.truncated,
    );
  }
}
