import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_providers.dart';

/// 一次 API 调用可能出的问题。**每一种都要能告诉用户下一步怎么办**，
/// 不能笼统地报「请求失败」。
enum AiFailureKind {
  /// 地址 / 密钥 / 模型还没填全。
  notConfigured,

  /// 用户没输入单词。
  emptyInput,

  /// 请求本身有问题（400 / 404：模型名写错、地址不对）。
  badRequest,

  /// 密钥无效或没权限（401 / 403）。
  unauthorized,

  /// 被限流（429）。
  rateLimited,

  /// 服务端错误（5xx）。
  serverError,

  /// 连不上：断网、代理没开、本地模型没启动。
  network,

  /// 超时。
  timeout,

  /// 返回了 200 但不是我们能懂的结构。
  badResponse,

  /// 模型返回了空内容。
  emptyContent,

  /// 拿到了内容，但不是能入库的卡片（交给解析器判断）。
  unparsable,
}

/// 一次生成失败的原因 + 给用户的下一步建议。
class AiApiFailure implements Exception {
  const AiApiFailure(this.kind, this.message, {this.hint, this.statusCode});

  final AiFailureKind kind;

  /// 面向用户的一句话。
  final String message;

  /// 「下一步怎么办」；失败降级引导就用它。
  final String? hint;

  final int? statusCode;

  /// 值得原样重试的错误。
  bool get isRetryable =>
      kind == AiFailureKind.network ||
      kind == AiFailureKind.timeout ||
      kind == AiFailureKind.serverError ||
      kind == AiFailureKind.rateLimited;

  @override
  String toString() => message;
}

/// 一次成功的生成结果。
class AiCompletion {
  const AiCompletion({
    required this.content,
    this.model = '',
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
  });

  final String content;
  final String model;
  final int promptTokens;
  final int completionTokens;

  /// `stop` / `length` 之类；被截断时要提醒用户。
  final String? finishReason;

  bool get truncated => finishReason == 'length';
}

/// 一次请求的全部参数。
class AiRequest {
  const AiRequest({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.prompt,
    this.timeoutSeconds = 15,
    this.temperature = 0.3,
    this.maxTokens = 0,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String prompt;
  final int timeoutSeconds;
  final double temperature;

  /// 0 表示不传 `max_tokens`，让服务端用自己的默认值。
  final int maxTokens;
}

/// HTTP 客户端接口；测试里换成假的，应用里用 [HttpAiApiClient]。
abstract interface class AiApiClient {
  Future<AiCompletion> complete(AiRequest request);

  void close();
}

/// OpenAI 兼容接口的客户端。
///
/// 只做 `POST {base}/chat/completions` 一件事，所以任何 OpenAI 兼容的
/// 服务（包括本机 Ollama / LM Studio）都能用。
class HttpAiApiClient implements AiApiClient {
  HttpAiApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const int minTimeoutSeconds = 5;
  static const int maxTimeoutSeconds = 300;

  @override
  Future<AiCompletion> complete(AiRequest request) async {
    final String url = chatCompletionsUrl(request.baseUrl);
    if (url.isEmpty) {
      throw const AiApiFailure(
        AiFailureKind.notConfigured,
        '还没有填 API 地址',
        hint: '去设置页填地址、密钥和模型，或者先用网页聊天导入',
      );
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiApiFailure(
        AiFailureKind.badRequest,
        'API 地址不是合法的 http(s) 链接：$url',
        hint: '地址写成 https://api.deepseek.com/v1 这样的形式',
      );
    }
    if (request.model.trim().isEmpty) {
      throw const AiApiFailure(
        AiFailureKind.notConfigured,
        '还没有填模型名',
        hint: '比如 deepseek-chat、gpt-4o-mini、qwen2.5:7b',
      );
    }

    final Map<String, Object?> body = <String, Object?>{
      'model': request.model.trim(),
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': request.prompt},
      ],
      'temperature': request.temperature,
      'stream': false,
    };
    if (request.maxTokens > 0) body['max_tokens'] = request.maxTokens;

    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    final String key = request.apiKey.trim();
    if (key.isNotEmpty) headers['authorization'] = 'Bearer $key';

    final int seconds =
        request.timeoutSeconds.clamp(minTimeoutSeconds, maxTimeoutSeconds);
    http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(Duration(seconds: seconds));
    } on TimeoutException {
      throw AiApiFailure(
        AiFailureKind.timeout,
        '等了 $seconds 秒还没返回',
        hint: '把超时调大一点；或者换更快的小模型、减少一次生成的单词数',
      );
    } on AiApiFailure {
      rethrow;
    } catch (error) {
      throw AiApiFailure(
        AiFailureKind.network,
        '连不上 API：$error',
        hint: '检查网络或代理；本地模型要确认服务已经启动',
      );
    }

    return _decode(response);
  }

  @override
  void close() => _client.close();

  AiCompletion _decode(http.Response response) {
    final int status = response.statusCode;
    // 不能直接用 response.body：不少服务端不发 charset，http 包会按 latin1 解，
    // 中文释义会变成乱码。
    final String text = utf8.decode(response.bodyBytes, allowMalformed: true);

    Object? decoded;
    bool isJson = true;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
      isJson = false;
    }
    final String? providerMessage = _providerMessage(decoded);

    if (status < 200 || status >= 300) {
      throw _failureForStatus(status, providerMessage ?? _snippet(text));
    }
    if (!isJson || decoded is! Map) {
      throw AiApiFailure(
        AiFailureKind.badResponse,
        '服务端返回的不是 JSON（HTTP $status）',
        hint: '确认地址填的是 OpenAI 兼容接口',
        statusCode: status,
      );
    }

    final Map<Object?, Object?> root = decoded;
    final Object? choices = root['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiApiFailure(
        AiFailureKind.badResponse,
        providerMessage ?? '返回里没有 choices 字段',
        hint: '换一个模型试试；也可能是这个地址不是聊天补全接口',
        statusCode: status,
      );
    }

    final Object? first = choices.first;
    final Object? message = first is Map ? first['message'] : null;
    final String content =
        _contentOf(message is Map ? message['content'] : null);
    final Object? finish = first is Map ? first['finish_reason'] : null;

    final Object? usage = root['usage'];
    final int promptTokens =
        _intOf(usage is Map ? usage['prompt_tokens'] : null);
    final int completionTokens =
        _intOf(usage is Map ? usage['completion_tokens'] : null);

    if (content.trim().isEmpty) {
      throw AiApiFailure(
        AiFailureKind.emptyContent,
        '模型返回了空内容',
        hint: finish == 'length'
            ? '输出被长度上限截断了：少给几个单词，或换一个上下文更大的模型'
            : '换一个模型试试；有些推理模型只把答案放在 reasoning_content 里',
        statusCode: status,
      );
    }

    final Object? modelName = root['model'];
    return AiCompletion(
      content: content,
      model: modelName is String ? modelName : '',
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      finishReason: finish is String ? finish : null,
    );
  }

  AiApiFailure _failureForStatus(int status, String detail) {
    switch (status) {
      case 400:
        return AiApiFailure(
          AiFailureKind.badRequest,
          '请求被拒绝（400）：$detail',
          hint: '多半是模型名写错，或地址少了 /v1',
          statusCode: status,
        );
      case 401:
      case 403:
        return AiApiFailure(
          AiFailureKind.unauthorized,
          '密钥无效或没有权限（$status）',
          hint: '检查 API Key 是否过期、有没有多余空格；本地模型可以留空',
          statusCode: status,
        );
      case 404:
        return AiApiFailure(
          AiFailureKind.badRequest,
          '找不到接口（404）',
          hint: '地址一般填到 /v1 为止，程序会自动补 /chat/completions',
          statusCode: status,
        );
      case 408:
      case 504:
        return AiApiFailure(
          AiFailureKind.timeout,
          '服务端超时（$status）',
          hint: '等一会儿重试，或换更快的模型',
          statusCode: status,
        );
      case 429:
        return AiApiFailure(
          AiFailureKind.rateLimited,
          '触发限流（429）',
          hint: '等一会儿再试；一次少生成几个单词也能减少限流',
          statusCode: status,
        );
      default:
        if (status >= 500) {
          return AiApiFailure(
            AiFailureKind.serverError,
            '服务端错误（$status）',
            hint: '等一会儿重试，或换一家提供商',
            statusCode: status,
          );
        }
        return AiApiFailure(
          AiFailureKind.badResponse,
          '请求失败（HTTP $status）：$detail',
          hint: '确认地址、模型名和密钥',
          statusCode: status,
        );
    }
  }

  /// 各家把错误放在不同位置，这里都认。
  String? _providerMessage(Object? decoded) {
    if (decoded is! Map) return null;
    final Object? error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
    if (error is Map) {
      final Object? nested = error['message'] ?? error['msg'] ?? error['type'];
      if (nested is String && nested.trim().isNotEmpty) return nested.trim();
    }
    final Object? message = decoded['message'] ?? decoded['msg'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return null;
  }

  /// `message.content` 一般是字符串，少数实现给的是分段数组。
  String _contentOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final List<String> parts = <String>[];
      for (final Object? part in content) {
        if (part is String) {
          parts.add(part);
        } else if (part is Map && part['text'] is String) {
          parts.add(part['text'] as String);
        }
      }
      return parts.join();
    }
    return '';
  }

  int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _snippet(String text) {
    final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 200) return flat;
    final String head = flat.substring(0, 200);
    return '$head…';
  }
}
