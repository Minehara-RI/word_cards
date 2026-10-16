/// 支持的 API 提供商。
///
/// 全部走 OpenAI 兼容的 `POST /chat/completions`，所以「多提供商」在这里
/// 只是**几组预设**：点一下把地址和模型填好，用户还可以改成任意别的值。
/// 真正决定请求长什么样的只有地址、密钥、模型三个字段。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.note = '',
    this.needsKey = true,
  });

  final String id;
  final String name;

  /// 建议填写的地址；程序会自动补 `/chat/completions`。
  final String baseUrl;

  /// 建议填写的模型名。
  final String model;

  /// 界面上的一句说明。
  final String note;

  /// 要不要 API Key。本地跑模型不需要。
  final bool needsKey;

  bool get isLocal => !needsKey;
}

/// 内置的提供商列表；顺序即设置页里的展示顺序。最后一项固定是「自定义」。
const List<AiProvider> kAiProviders = <AiProvider>[
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    note: '国内可直连，价格低，中文释义质量稳',
  ),
  AiProvider(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    note: '官方接口；国内直连一般要走代理',
  ),
  AiProvider(
    id: 'moonshot',
    name: 'Moonshot Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
    note: '长上下文，中文友好',
  ),
  AiProvider(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
    note: 'flash 档有免费额度',
  ),
  AiProvider(
    id: 'dashscope',
    name: '通义千问（阿里百炼）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
    note: '走百炼的 OpenAI 兼容模式',
  ),
  AiProvider(
    id: 'siliconflow',
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2.5-7B-Instruct',
    note: '开源模型聚合，模型名带斜杠',
  ),
  AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-4o-mini',
    note: '一个 Key 调多家模型',
  ),
  AiProvider(
    id: 'ollama',
    name: '本地 Ollama',
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'qwen2.5:7b',
    note: '完全本机运行，不联网、不用 Key',
    needsKey: false,
  ),
  AiProvider(
    id: 'lmstudio',
    name: '本地 LM Studio',
    baseUrl: 'http://127.0.0.1:1234/v1',
    model: 'local-model',
    note: '本机加载 GGUF 模型，端口按 LM Studio 里的设置填',
    needsKey: false,
  ),
  AiProvider(
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    model: '',
    note: '任何 OpenAI 兼容接口都能用（自建网关、公司内网…）',
  ),
];

/// 去掉首尾空白与结尾多余的斜杠。
String normalizeApiBaseUrl(String? raw) {
  String url = (raw ?? '').trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// 真正的请求地址：填 `https://x/v1` 或直接填完整端点都可以。
String chatCompletionsUrl(String baseUrl) {
  final String url = normalizeApiBaseUrl(baseUrl);
  if (url.isEmpty) return '';
  if (url.endsWith('/chat/completions')) return url;
  return '$url/chat/completions';
}

/// 按地址反查是哪家提供商；认不出来返回 null（设置页就会显示「自定义」）。
AiProvider? providerForBaseUrl(String? baseUrl) {
  final String url = normalizeApiBaseUrl(baseUrl);
  if (url.isEmpty) return null;
  for (final AiProvider provider in kAiProviders) {
    if (provider.id == 'custom') continue;
    if (normalizeApiBaseUrl(provider.baseUrl) == url) return provider;
  }
  return null;
}
