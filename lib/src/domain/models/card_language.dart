// ignore_for_file: prefer_interpolation_to_compose_strings

/// 单词的目标语言。
///
/// 应用本身只负责「记单词」，具体记哪国语言由用户选。语言决定三件事：
/// - 出题与统计按语言分组
/// - 演示模式的字体回退顺序（日语假名、韩语谚文、俄语西里尔字母）
/// - 复制给大模型的 Prompt 里要说明是哪种语言
///
/// 语言以 Anki 标签（lang::en 这样）的形式写在 notes.tags 里，
/// 这样在 Anki 里也一眼能看出这张卡是哪国语言的词。
enum CardLanguage {
  english('en', '英语', 'English'),
  french('fr', '法语', 'Français'),
  japanese('ja', '日语', '日本語'),
  korean('ko', '韩语', '한국어'),
  russian('ru', '俄语', 'Русский');

  const CardLanguage(this.id, this.label, this.nativeLabel);

  /// 持久化与 Anki 标签里用的稳定标识。
  final String id;

  /// 界面上的中文名。
  final String label;

  /// 该语言自己的写法，界面上跟中文并排显示。
  final String nativeLabel;

  /// 语言标签的前缀。
  static const String tagPrefix = 'lang::';

  /// 写进 Anki 标签的形式。
  String get tag => tagPrefix + id;

  /// 界面上「英语 English」这样的展示名。
  String get displayName => label + ' ' + nativeLabel;

  /// 复制给大模型时用的说明。
  String get promptLabel => label + '（' + nativeLabel + '）';

  /// 例句该用哪种语言写（中文说「英文例句」）。
  String get exampleLanguage => switch (this) {
        CardLanguage.english => '英文',
        CardLanguage.french => '法文',
        CardLanguage.japanese => '日文',
        CardLanguage.korean => '韩文',
        CardLanguage.russian => '俄文',
      };

  /// 「音标」这一栏该怎么填——不同语言的注音方式差别很大。
  ///
  /// 只有英语要再分英式 / 美式（[accent]）：同一本词典里两种标法都在，
  /// 混着写会让一套卡片的音标前后不一致。法语、俄语用国际音标，日语用假名，
  /// 都不存在口音之别，这一档对它们没有影响。
  String phoneticHint({PhoneticAccent accent = PhoneticAccent.american}) =>
      switch (this) {
        CardLanguage.english => accent.promptHint,
        CardLanguage.french => '国际音标，用方括号包起来，例如 [a.bɑ̃.dɔ.ne]',
        CardLanguage.japanese => '平假名读音，放在【】里，例如【すいえい】',
        CardLanguage.korean => '罗马字转写，放在方括号里，例如 [sagwa]',
        CardLanguage.russian => '国际音标，用方括号包起来，例如 [ɐtkɐˈzatʲsə]',
      };

  static CardLanguage fromId(Object? value) {
    if (value is String) {
      final String key = value.trim().toLowerCase();
      for (final language in CardLanguage.values) {
        if (language.id == key || language.name.toLowerCase() == key) {
          return language;
        }
      }
    }
    return CardLanguage.english;
  }

  /// 从一串标签里读出语言；没有语言标签时返回 null。
  static CardLanguage? fromTags(Iterable<String> tags) {
    for (final String raw in tags) {
      final String tag = raw.trim().toLowerCase();
      if (tag.startsWith(tagPrefix)) {
        return fromId(tag.substring(tagPrefix.length));
      }
    }
    return null;
  }

  /// 这个标签是不是语言标签（语言标签不算用户自定义标签）。
  static bool isLanguageTag(String tag) =>
      tag.trim().toLowerCase().startsWith(tagPrefix);
}

/// 英语音标用英式还是美式。
///
/// 两种体系对同一个词的标法确实不同（water：英 /ˈwɔːtə/、美 /ˈwɔːtɚ/），
/// 一套词卡里混着写会让人以为某个词有两种读法。这个选择只影响
/// **让 AI 生成音标时怎么提要求**：已经进库的音标不会被改写
/// （那是用户自己的卡片，静默改数据比标法不统一更糟）。
enum PhoneticAccent {
  british(
    'british',
    '英式',
    'DJ 音标',
    '/ˈwɔːtə/',
    '英式音标，用斜杠包起来，例如 /ˈwɔːtə/；按英式发音写，不要写成美式的卷舌音',
  ),
  american(
    'american',
    '美式',
    'KK 音标',
    '/ˈwɔːtɚ/',
    '美式音标，用斜杠包起来，例如 /ˈwɔːtɚ/；按美式发音写，注意卷舌音',
  );

  const PhoneticAccent(
    this.id,
    this.label,
    this.system,
    this.example,
    this.promptHint,
  );

  /// 持久化用的稳定标识。
  final String id;

  /// 界面上的简称。
  final String label;

  /// 音标体系的名字，界面上跟在简称后面。
  final String system;

  /// 一个两种标法明显不同的例词（water），设置页拿它说明差别。
  final String example;

  /// 写进 Prompt 的完整说法（拼在「phonetic 给……」后面）。
  final String promptHint;

  /// 界面上「英式 · DJ 音标」这样的展示名。
  String get displayName => label + ' · ' + system;

  static PhoneticAccent fromId(Object? value) {
    if (value is String) {
      for (final accent in PhoneticAccent.values) {
        if (accent.id == value || accent.name == value) return accent;
      }
    }
    return PhoneticAccent.american;
  }
}
