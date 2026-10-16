import '../../domain/models/card_language.dart';

/// 模板适用的场景。
enum PromptKind {
  /// 一次生成一张卡片。
  single('single', '单张'),

  /// 一次生成多张卡片（用户给单词列表）。
  batch('batch', '批量');

  const PromptKind(this.id, this.label);

  final String id;
  final String label;
}

/// 一条内置的 Prompt 模板。
///
/// 模板正文里用「{words}」占位，用户点“复制”时替换成真实单词。
/// 不同大模型对同一个 Prompt 的服从度不一样，所以这里保留多套，
/// 用户可以在导入页里切换。
class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.body,
  });

  final String id;
  final String name;
  final String description;
  final PromptKind kind;

  /// 模板正文，「{words}」为占位符。
  final String body;

  bool get isBatch => kind == PromptKind.batch;

  /// 把占位符替换成用户输入；多个单词用换行分隔。
  ///
  /// [language] 决定模板里「英语词汇教研员」「美式音标」「英文例句」
  /// 这些说法怎么替换，所以同一套模板也能生成法语 / 日语 / 韩语 / 俄语的卡片。
  String build(String words, {CardLanguage language = CardLanguage.english}) {
    return body
        .replaceAll('{words}', _normalizeWords(words))
        .replaceAll('{langName}', language.label)
        .replaceAll('{phoneticHint}', language.phoneticHint)
        .replaceAll('{exampleLang}', language.exampleLanguage);
  }

  /// 批量模板 + 单词列表的便捷入口。
  String buildFromList(
    List<String> words, {
    CardLanguage language = CardLanguage.english,
  }) =>
      build(words.join('\n'), language: language);

  static String _normalizeWords(String words) {
    final lines = words
        .split(RegExp(r'[\n,，;；]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.join('\n');
  }
}

/// 应用内置的模板集合。顺序即界面展示顺序。
const List<PromptTemplate> kPromptTemplates = <PromptTemplate>[
  PromptTemplate(
    id: 'standard',
    name: '标准模板（推荐）',
    description: '生成单个单词的卡片，对干扰项的混淆性有明确要求。',
    kind: PromptKind.single,
    body: '''你是一位资深{langName}词汇教研员，正在为单词测验编写题目。

目标单词：{words}

请为这个单词输出一张测验卡片，要求：
1. definition 写最常用的中文释义，并带词性缩写，例如「v. 放弃；抛弃」。多个义项用「；」分隔，整条不超过 20 个字。
2. distractors 必须给 4 条干扰释义，并且满足：
   - 与正确释义词性相同；
   - 字数与常见程度接近，不能一眼看出是错的；
   - 与正确释义含义不同，也不能是它的近义词；
   - 不要出现「以上都对」「以上都不对」这类选项。
3. phonetic 给{phoneticHint}。
4. example 造一个地道、长度适中的{exampleLang}例句，能体现该词的用法。
5. 只输出一个 JSON 对象。不要输出解释，不要输出 Markdown 代码块，不要输出任何多余文字。

输出格式（字段名必须完全一致）：
{
  "word": "{words}",
  "phonetic": "/.../",
  "partOfSpeech": "verb",
  "definition": "v. 中文释义",
  "distractors": ["...", "...", "...", "..."],
  "example": "English example sentence."
}''',
  ),
  PromptTemplate(
    id: 'batch',
    name: '批量模板',
    description: '一次给多个单词，模型返回 JSON 数组，适合提前批量准备词库。',
    kind: PromptKind.batch,
    body: '''你是一位资深{langName}词汇教研员，正在为单词测验批量编写题目。

单词列表（每行一个，请按顺序一一对应，不要遗漏也不要增加）：
{words}

请为列表里的每个单词生成一张测验卡片。每张卡片的要求：
1. definition 为最常用的中文释义，带词性缩写，例如「v. 放弃；抛弃」，不超过 20 个字。
2. distractors 给 4 条干扰释义，词性、字数、常见程度都要与正确释义接近，具备真实的混淆性，且不能与正确释义同义。
3. phonetic 为{phoneticHint}。
4. example 为能体现该词用法的{exampleLang}例句。
5. 只输出一个 JSON 数组，不要输出任何解释文字，不要输出 Markdown 代码块。

输出格式（每个元素的字段名必须完全一致）：
[
  {
    "word": "abandon",
    "phonetic": "/əˈbændən/",
    "partOfSpeech": "verb",
    "definition": "v. 放弃；抛弃",
    "distractors": ["v. 遵守；坚持", "v. 维持；供养", "v. 增加；扩大", "v. 分配；指派"],
    "example": "He abandoned his car in the snow."
  }
]''',
  ),
  PromptTemplate(
    id: 'strict',
    name: '严格精简模板',
    description: '有些模型爱加废话或代码块，用这套更短的指令强制它只吐 JSON。',
    kind: PromptKind.single,
    body: '''只做一件事：为下面的单词输出 JSON 卡片，除此之外不要输出任何字符。

目标语言：{langName}
单词：{words}

规则：
- definition：1 条正确的中文释义，带词性，不超过 20 字；
- phonetic：{phoneticHint}；
- distractors：4 条错误的中文释义，词性与字数要和正确释义接近；
- 只输出 JSON。不要代码块，不要注释，不要解释，不要空行。

格式：
{"word":"...","phonetic":"/.../","partOfSpeech":"...","definition":"...","distractors":["...","...","...","..."],"example":"..."}''',
  ),
];

/// 按 id 取模板；找不到时退回第一个。
PromptTemplate promptTemplateById(String? id) {
  for (final template in kPromptTemplates) {
    if (template.id == id) return template;
  }
  return kPromptTemplates.first;
}
