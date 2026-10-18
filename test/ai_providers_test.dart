import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/ai_providers.dart';

void main() {
  group('地址归一化', () {
    test('去掉首尾空白与结尾斜杠', () {
      expect(normalizeApiBaseUrl('  https://a.com/v1/  '), 'https://a.com/v1');
      expect(normalizeApiBaseUrl('https://a.com/v1///'), 'https://a.com/v1');
      expect(normalizeApiBaseUrl(null), '');
      expect(normalizeApiBaseUrl('   '), '');
    });
  });

  group('拼请求地址', () {
    test('只有 /v1 时自动补 /chat/completions', () {
      expect(
        chatCompletionsUrl('https://api.deepseek.com/v1'),
        'https://api.deepseek.com/v1/chat/completions',
      );
    });

    test('已经填了完整端点就不再追加', () {
      expect(
        chatCompletionsUrl('https://x.com/v1/chat/completions'),
        'https://x.com/v1/chat/completions',
      );
      expect(
        chatCompletionsUrl('https://x.com/v1/chat/completions/'),
        'https://x.com/v1/chat/completions',
      );
    });

    test('空地址返回空串（交给上层报「还没配置」）', () {
      expect(chatCompletionsUrl(''), '');
      expect(chatCompletionsUrl('   '), '');
    });

    test('本地地址（无 /v1 结尾）也能拼出来', () {
      expect(
        chatCompletionsUrl('http://127.0.0.1:11434/v1'),
        'http://127.0.0.1:11434/v1/chat/completions',
      );
    });
  });

  group('反查提供商', () {
    test('每个内置提供商都能按自己的地址认回来', () {
      for (final AiProvider provider in kAiProviders) {
        if (provider.id == 'custom') continue;
        expect(
          providerForBaseUrl(provider.baseUrl)?.id,
          provider.id,
          reason: '认不出 ${provider.name}',
        );
      }
    });

    test('结尾多一个斜杠也认', () {
      expect(
        providerForBaseUrl('https://api.deepseek.com/v1/')?.id,
        'deepseek',
      );
    });

    test('认不出来的地址返回 null（设置页显示「自定义」）', () {
      expect(providerForBaseUrl('https://my-gateway.internal/v1'), isNull);
      expect(providerForBaseUrl(''), isNull);
      expect(providerForBaseUrl(null), isNull);
      expect(providerForBaseUrl('https://api.deepseek.com/v2'), isNull);
    });

    test('「自定义」这一项永远不会被认出来（它是兜底选项）', () {
      expect(providerForBaseUrl(kAiProviders.last.baseUrl), isNull);
      expect(kAiProviders.last.id, 'custom');
    });
  });

  group('预设表本身', () {
    test('id 不重复', () {
      final Set<String> ids = kAiProviders.map((p) => p.id).toSet();
      expect(ids.length, kAiProviders.length);
    });

    test('本地模型不需要 Key', () {
      expect(kAiProviders.firstWhere((p) => p.id == 'ollama').needsKey, isFalse);
      expect(kAiProviders.firstWhere((p) => p.id == 'deepseek').needsKey, isTrue);
    });

    test('除了自定义，都要给出地址和模型名', () {
      for (final AiProvider provider in kAiProviders) {
        if (provider.id == 'custom') continue;
        expect(provider.baseUrl, isNotEmpty, reason: provider.name);
        expect(provider.model, isNotEmpty, reason: provider.name);
      }
    });
  });
}
