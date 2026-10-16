import 'card_language.dart';
import 'card_source.dart';
import 'quiz_direction.dart';

/// 主题偏好。刻意不用 Flutter 的 ThemeMode，保持领域层纯 Dart。
enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.id, this.label);

  final String id;
  final String label;

  static AppThemeMode fromId(Object? value) {
    if (value is String) {
      for (final mode in AppThemeMode.values) {
        if (mode.id == value || mode.name == value) return mode;
      }
    }
    return AppThemeMode.system;
  }
}

/// 答题时「正误」什么时候显示。
///
/// 三种模式对应三种练习场景：
/// - 背单词自测：立刻知道对错，记忆反馈最快
/// - 模拟考试：全程不提示，交卷后统一看每道题
/// - 只想知道水平：连答案都不看，只要一个总分
enum AnswerRevealMode {
  immediate('immediate', '立即显示', '每次作答后立刻标出对错与正确释义'),
  deferred('deferred', '统一显示', '答题过程不提示，结束后统一列出每道题的对错与正确答案'),
  never('never', '不显示', '全程不显示对错与答案，只看最终得分');

  const AnswerRevealMode(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  bool get isImmediate => this == AnswerRevealMode.immediate;

  /// 结束后要不要逐题回顾。
  bool get showsReview => this == AnswerRevealMode.deferred;

  static AnswerRevealMode fromId(Object? value) {
    if (value is String) {
      for (final mode in AnswerRevealMode.values) {
        if (mode.id == value || mode.name == value) return mode;
      }
    }
    return AnswerRevealMode.immediate;
  }
}

/// 复习算法。
///
/// 两套算法**完全独立**：
/// - legacy 是原来那套：按正确率 / 掌握度挑词，不算间隔；
/// - fsrs 用 FSRS-6 的记忆状态（稳定性、难度）决定今天该复习哪些词。
/// 切换算法不会动对方的数据：FSRS 的状态存在独立的表里，
/// 关掉之后原来的掌握度、正确率一个数都不会变。
enum SchedulerMode {
  legacy('legacy', '原有算法', '按正确率与掌握度挑词；FSRS 状态原样保留，不受影响'),
  fsrs('fsrs', 'FSRS-6', '用记忆稳定性与可提取度排复习顺序，只安排今天该复习的词');

  const SchedulerMode(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  bool get isFsrs => this == SchedulerMode.fsrs;

  static SchedulerMode fromId(Object? value) {
    if (value is String) {
      for (final mode in SchedulerMode.values) {
        if (mode.id == value || mode.name == value) return mode;
      }
    }
    return SchedulerMode.legacy;
  }
}

/// 演示模式里选项前面的编号样式。
///
/// 课堂上两种习惯都有：有的班喊「第三个」，有的班喊「C」。
enum OptionLabelStyle {
  number('number', '12345'),
  letter('letter', 'ABCDE');

  const OptionLabelStyle(this.id, this.label);

  final String id;
  final String label;

  /// 第 [index] 个选项（从 0 开始）显示成什么。
  String labelFor(int index) {
    if (this == OptionLabelStyle.letter) {
      return String.fromCharCode(65 + (index % 26));
    }
    return (index + 1).toString();
  }

  static OptionLabelStyle fromId(Object? value) {
    if (value is String) {
      for (final style in OptionLabelStyle.values) {
        if (style.id == value || style.name == value) return style;
      }
    }
    return OptionLabelStyle.number;
  }
}

/// 演示答案 txt 的输出模式。
enum AnswerSheetMode {
  optionOnly('option_only', '只含选项', '每题只写正确答案那一项，适合照着核对'),
  wordAndOption('word_and_option', '单词 + 义项', '每题写单词、音标和正确答案，适合发给学生');

  const AnswerSheetMode(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static AnswerSheetMode fromId(Object? value) {
    if (value is String) {
      for (final mode in AnswerSheetMode.values) {
        if (mode.id == value || mode.name == value) return mode;
      }
    }
    return AnswerSheetMode.wordAndOption;
  }
}

/// 演示模式翻页提示音的来源。
enum PageTurnSoundSource {
  builtin('builtin', '内置提示音'),
  custom('custom', '自选音频');

  const PageTurnSoundSource(this.id, this.label);

  final String id;
  final String label;

  static PageTurnSoundSource fromId(Object? value) {
    if (value is String) {
      for (final source in PageTurnSoundSource.values) {
        if (source.id == value || source.name == value) return source;
      }
    }
    return PageTurnSoundSource.builtin;
  }
}

/// 用户配置：AI 提供商、限时与反馈方式、投影间隔、界面偏好等。
///
/// 全部存在本机，不随任何请求上传。
class AppSettings {
  const AppSettings({
    this.apiBaseUrl,
    this.apiKey,
    this.apiModel,
    this.apiTimeoutSeconds = 15,
    this.preferManualMode = false,
    this.quizQuestionCount = allQuestions,
    this.studyTagFilter = const <String>[],
    this.questionTimeLimitSeconds = 10,
    this.answerRevealMode = AnswerRevealMode.immediate,
    this.quizDirection = QuizDirection.wordToMeaning,
    this.apiCacheHours = 24,
    this.projectionIntervalSeconds = 5,
    this.projectionShuffle = false,
    this.projectionLoop = true,
    this.projectionOptionLabelStyle = OptionLabelStyle.number,
    this.projectionReshuffleEachRound = true,
    this.projectionAnswerDir,
    this.projectionAnswerMode = AnswerSheetMode.wordAndOption,
    this.projectionBeepEnabled = true,
    this.projectionBeepHz = 3000,
    this.projectionBeepMs = 500,
    this.projectionSoundSource = PageTurnSoundSource.builtin,
    this.projectionSoundPath,
    this.projectionThemeMode = AppThemeMode.system,
    this.themeMode = AppThemeMode.system,
    this.fontScale = 1.0,
    this.activeDeckId,
    this.language = CardLanguage.english,
    this.schedulerMode = SchedulerMode.legacy,
    this.fsrsDesiredRetention = defaultRetention,
    this.promptTemplateId,
    this.homeTab = defaultHomeTab,
    this.apiCallCount = 0,
    this.apiPromptTokens = 0,
    this.apiCompletionTokens = 0,
  });

  /// 「题目数量」里的「全部」：不按数量截断，出筛选之后的整份词表。
  ///
  /// 用 0 而不是写死一个数字，卡组加词之后它会自己跟着长。
  static const int allQuestions = 0;

  /// 限时的合法范围（秒）。没有「不限时」这个选项。
  static const int minTimeLimitSeconds = 1;
  static const int maxTimeLimitSeconds = 600;

  /// 主页面 id。设置里的 `home_tab` 存的就是这几个字符串，
  /// 所以只能往后加，不能改已有的值（改了就认不出上次停在哪一页）。
  static const String addHomeTab = 'add';
  static const String studyHomeTab = 'study';

  /// 课堂投影（演示）。手机端不显示这一页，见 visibleHomeTabs()。
  static const String demoHomeTab = 'demo';

  static const String statsHomeTab = 'stats';
  static const String exportHomeTab = 'export';

  /// 主界面停在哪个页面。应用退出后再打开，还是回到离开时的那一页。
  static const String defaultHomeTab = studyHomeTab;

  /// 桌面端所有可以停留的主页面 id（手机端少一个「演示」）。
  static const List<String> homeTabs = <String>[
    addHomeTab,
    studyHomeTab,
    demoHomeTab,
    statsHomeTab,
    exportHomeTab,
  ];

  /// FSRS 目标保留率的取值范围与默认值。
  static const double minRetention = 0.70;
  static const double maxRetention = 0.97;
  static const double defaultRetention = 0.90;
  static const List<double> retentionPresets = <double>[0.80, 0.85, 0.90, 0.95];

  static double normalizeRetention(double value) =>
      value.clamp(minRetention, maxRetention);

  /// 内置提示音的合法范围。
  static const int minBeepHz = 100;
  static const int maxBeepHz = 15000;
  static const int minBeepMs = 20;
  static const int maxBeepMs = 3000;

  static int normalizeBeepHz(int hz) => hz.clamp(minBeepHz, maxBeepHz);

  static int normalizeBeepMs(int ms) => ms.clamp(minBeepMs, maxBeepMs);

  // ---- 模式 B：API 直连 ----
  final String? apiBaseUrl;
  final String? apiKey;
  final String? apiModel;
  final int apiTimeoutSeconds;
  final int apiCacheHours;

  /// 用户明确选择“优先使用手动模式”。
  final bool preferManualMode;

  // ---- 测验 ----

  /// 每轮出多少题。取值 [allQuestions]（0）表示出全部，见 [quizAllQuestions]。
  final int quizQuestionCount;

  /// 本轮只出带这些标签的词；多个标签之间是「与」。
  ///
  /// 只在「原有算法」下参与选题（FSRS-6 的复习队列不看它）。
  /// 空列表表示不筛，用当前卡组的全部词。
  final List<String> studyTagFilter;

  /// 每道题的作答限时（秒）。到点没作答就判超时并强制进入下一题。
  ///
  /// 这是一个**硬性**规则：不做「不限时」的开关，
  /// 课堂演示与个人自测都按同一个原则走。
  final int questionTimeLimitSeconds;

  /// 答题过程中什么时候显示正误。
  final AnswerRevealMode answerRevealMode;

  /// 出题方向：看词选义、看义选词，或者每道题在两者之间随机（混合）。
  final QuizDirection quizDirection;

  // ---- 投影模式（仅桌面端）----
  final int projectionIntervalSeconds;
  final bool projectionShuffle;
  final bool projectionLoop;

  /// 选项前面用 12345 还是 ABCDE。
  final OptionLabelStyle projectionOptionLabelStyle;

  /// 循环播放时，每绕一轮都重新打乱选项顺序。
  final bool projectionReshuffleEachRound;

  /// 演示结束后答案 txt 放在哪个目录；为空表示用默认目录。
  final String? projectionAnswerDir;

  /// 答案 txt 写多详细。
  final AnswerSheetMode projectionAnswerMode;

  /// 翻页时播不播提示音。
  final bool projectionBeepEnabled;

  /// 内置提示音的频率（Hz）与时长（毫秒）。默认 3000 Hz / 0.5 秒。
  final int projectionBeepHz;
  final int projectionBeepMs;

  /// 用内置提示音，还是用用户自己挑的音频文件。
  final PageTurnSoundSource projectionSoundSource;

  /// 自选音频的文件路径（[projectionSoundSource] 为 custom 时有效）。
  final String? projectionSoundPath;

  // ---- 词库与语言 ----

  /// 当前卡组。新加入的词都进这个卡组；
  /// 只有用户主动「更换卡组」或「开启新卡组」时它才会变。
  /// 为 null 表示还没选过，用默认卡组。
  final String? activeDeckId;

  /// 新词默认用哪种语言。
  final CardLanguage language;

  // ---- 复习算法 ----

  /// 用原来那套算法，还是用 FSRS-6。
  final SchedulerMode schedulerMode;

  /// FSRS 的目标保留率（0.70–0.97）。
  final double fsrsDesiredRetention;

  // ---- 记忆下来的界面选择 ----

  /// 上次用的 Prompt 模板 id（导入页）。
  final String? promptTemplateId;

  /// 上次停在主界面的哪一页。
  final String homeTab;

  // ---- 界面 ----
  final AppThemeMode themeMode;

  /// 演示模式（全屏投影）单独的一套深浅色，和主界面互不影响。
  final AppThemeMode projectionThemeMode;

  final double fontScale;

  /// 当前是否在用 FSRS 调度。
  bool get usesFsrs => schedulerMode.isFsrs;

  /// 「题目数量」是不是「全部」。
  bool get quizAllQuestions => quizQuestionCount <= allQuestions;

  /// 夹到合法区间后的目标保留率。
  double get retention => normalizeRetention(fsrsDesiredRetention);

  // ---- 用量统计 ----
  final int apiCallCount;
  final int apiPromptTokens;
  final int apiCompletionTokens;

  bool get hasApiCredentials =>
      (apiBaseUrl?.trim().isNotEmpty ?? false) &&
      (apiKey?.trim().isNotEmpty ?? false) &&
      (apiModel?.trim().isNotEmpty ?? false);

  /// 当前推荐的默认生成方式。
  CardSource get preferredSource =>
      preferManualMode || !hasApiCredentials ? CardSource.manualImport : CardSource.api;

  /// 粗暴的成本估算：按每 100 万 token 1 美元计，只用来给用户一个量级感。
  double get estimatedCostUsd =>
      (apiPromptTokens + apiCompletionTokens) / 1000000 * 1.0;

  /// 超时与缓存时长的合法区间。
  static const int minApiTimeoutSeconds = 5;
  static const int maxApiTimeoutSeconds = 300;
  static const int minApiCacheHours = 0;

  /// 0 表示不缓存；上限 30 天，再长就没有意义了。
  static const int maxApiCacheHours = 24 * 30;

  static int normalizeApiTimeout(int seconds) =>
      seconds.clamp(minApiTimeoutSeconds, maxApiTimeoutSeconds);

  static int normalizeApiCacheHours(int hours) =>
      hours.clamp(minApiCacheHours, maxApiCacheHours);

  /// 累计一次 API 用量（模式 B）。
  AppSettings addApiUsage({
    int calls = 0,
    int promptTokens = 0,
    int completionTokens = 0,
  }) =>
      copyWith(
        apiCallCount: apiCallCount + calls,
        apiPromptTokens: apiPromptTokens + promptTokens,
        apiCompletionTokens: apiCompletionTokens + completionTokens,
      );

  /// 清空用量统计（换 Key 或想重新看账单时用）。
  AppSettings resetApiUsage() => copyWith(
        apiCallCount: 0,
        apiPromptTokens: 0,
        apiCompletionTokens: 0,
      );

  /// 把任意输入夹到合法限时区间。
  static int normalizeTimeLimit(int seconds) =>
      seconds.clamp(minTimeLimitSeconds, maxTimeLimitSeconds);

  AppSettings copyWith({
    String? apiBaseUrl,
    String? apiKey,
    String? apiModel,
    int? apiTimeoutSeconds,
    bool? preferManualMode,
    int? quizQuestionCount,
    List<String>? studyTagFilter,
    int? questionTimeLimitSeconds,
    AnswerRevealMode? answerRevealMode,
    QuizDirection? quizDirection,
    int? apiCacheHours,
    int? projectionIntervalSeconds,
    bool? projectionShuffle,
    bool? projectionLoop,
    OptionLabelStyle? projectionOptionLabelStyle,
    bool? projectionReshuffleEachRound,
    String? projectionAnswerDir,
    bool clearProjectionAnswerDir = false,
    AnswerSheetMode? projectionAnswerMode,
    bool? projectionBeepEnabled,
    int? projectionBeepHz,
    int? projectionBeepMs,
    PageTurnSoundSource? projectionSoundSource,
    String? projectionSoundPath,
    bool clearProjectionSoundPath = false,
    AppThemeMode? themeMode,
    AppThemeMode? projectionThemeMode,
    double? fontScale,
    String? activeDeckId,
    bool clearActiveDeckId = false,
    CardLanguage? language,
    SchedulerMode? schedulerMode,
    double? fsrsDesiredRetention,
    String? promptTemplateId,
    String? homeTab,
    int? apiCallCount,
    int? apiPromptTokens,
    int? apiCompletionTokens,
    bool clearApiKey = false,
  }) {
    return AppSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      apiModel: apiModel ?? this.apiModel,
      apiTimeoutSeconds: apiTimeoutSeconds ?? this.apiTimeoutSeconds,
      preferManualMode: preferManualMode ?? this.preferManualMode,
      quizQuestionCount: quizQuestionCount ?? this.quizQuestionCount,
      studyTagFilter: studyTagFilter ?? this.studyTagFilter,
      questionTimeLimitSeconds:
          questionTimeLimitSeconds ?? this.questionTimeLimitSeconds,
      answerRevealMode: answerRevealMode ?? this.answerRevealMode,
      quizDirection: quizDirection ?? this.quizDirection,
      apiCacheHours: apiCacheHours ?? this.apiCacheHours,
      projectionIntervalSeconds:
          projectionIntervalSeconds ?? this.projectionIntervalSeconds,
      projectionShuffle: projectionShuffle ?? this.projectionShuffle,
      projectionLoop: projectionLoop ?? this.projectionLoop,
      projectionOptionLabelStyle:
          projectionOptionLabelStyle ?? this.projectionOptionLabelStyle,
      projectionReshuffleEachRound:
          projectionReshuffleEachRound ?? this.projectionReshuffleEachRound,
      projectionAnswerDir: clearProjectionAnswerDir
          ? null
          : (projectionAnswerDir ?? this.projectionAnswerDir),
      projectionAnswerMode:
          projectionAnswerMode ?? this.projectionAnswerMode,
      projectionBeepEnabled:
          projectionBeepEnabled ?? this.projectionBeepEnabled,
      projectionBeepHz: projectionBeepHz ?? this.projectionBeepHz,
      projectionBeepMs: projectionBeepMs ?? this.projectionBeepMs,
      projectionSoundSource:
          projectionSoundSource ?? this.projectionSoundSource,
      projectionSoundPath: clearProjectionSoundPath
          ? null
          : (projectionSoundPath ?? this.projectionSoundPath),
      themeMode: themeMode ?? this.themeMode,
      projectionThemeMode: projectionThemeMode ?? this.projectionThemeMode,
      fontScale: fontScale ?? this.fontScale,
      activeDeckId:
          clearActiveDeckId ? null : (activeDeckId ?? this.activeDeckId),
      language: language ?? this.language,
      schedulerMode: schedulerMode ?? this.schedulerMode,
      fsrsDesiredRetention:
          fsrsDesiredRetention ?? this.fsrsDesiredRetention,
      promptTemplateId: promptTemplateId ?? this.promptTemplateId,
      homeTab: homeTab ?? this.homeTab,
      apiCallCount: apiCallCount ?? this.apiCallCount,
      apiPromptTokens: apiPromptTokens ?? this.apiPromptTokens,
      apiCompletionTokens: apiCompletionTokens ?? this.apiCompletionTokens,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'api_base_url': apiBaseUrl,
        'api_key': apiKey,
        'api_model': apiModel,
        'api_timeout_seconds': apiTimeoutSeconds,
        'prefer_manual_mode': preferManualMode ? 1 : 0,
        'quiz_question_count': quizQuestionCount,
        'study_tag_filter': studyTagFilter,
        'question_time_limit_seconds': questionTimeLimitSeconds,
        'answer_reveal_mode': answerRevealMode.id,
        'quiz_direction': quizDirection.id,
        'api_cache_hours': apiCacheHours,
        'projection_interval_seconds': projectionIntervalSeconds,
        'projection_shuffle': projectionShuffle ? 1 : 0,
        'projection_loop': projectionLoop ? 1 : 0,
        'projection_option_label_style': projectionOptionLabelStyle.id,
        'projection_reshuffle_each_round':
            projectionReshuffleEachRound ? 1 : 0,
        'projection_answer_dir': projectionAnswerDir,
        'projection_answer_mode': projectionAnswerMode.id,
        'projection_beep_enabled': projectionBeepEnabled ? 1 : 0,
        'projection_beep_hz': projectionBeepHz,
        'projection_beep_ms': projectionBeepMs,
        'projection_sound_source': projectionSoundSource.id,
        'projection_sound_path': projectionSoundPath,
        'theme_mode': themeMode.id,
        'projection_theme_mode': projectionThemeMode.id,
        'font_scale': fontScale,
        'active_deck_id': activeDeckId,
        'language': language.id,
        'scheduler_mode': schedulerMode.id,
        'fsrs_desired_retention': fsrsDesiredRetention,
        'prompt_template_id': promptTemplateId,
        'home_tab': homeTab,
        'api_call_count': apiCallCount,
        'api_prompt_tokens': apiPromptTokens,
        'api_completion_tokens': apiCompletionTokens,
      };

  factory AppSettings.fromMap(Map<String, Object?> map) {
    // 老版本（还没有 study_tag_filter 这个键）的「每轮题数」默认值是 10，
    // 现在默认改成「全部」（[allQuestions]），所以把那个旧的默认值重新解释一次；
    // 用户主动选过的 5 / 20 等具体数字照旧尊重。保存过一次设置之后新键就在了，
    // 这件事不会再来第二次。
    final bool legacyBlob = !map.containsKey('study_tag_filter');
    final int storedQuestionCount =
        (map['quiz_question_count'] as num?)?.toInt() ??
            legacyDefaultQuestionCount;
    final int questionCount =
        legacyBlob && storedQuestionCount == legacyDefaultQuestionCount
            ? allQuestions
            : storedQuestionCount;

    return AppSettings(
        apiBaseUrl: (map['api_base_url'] as String?)?.trim(),
        apiKey: (map['api_key'] as String?)?.trim(),
        apiModel: (map['api_model'] as String?)?.trim(),
        apiTimeoutSeconds: (map['api_timeout_seconds'] as num?)?.toInt() ?? 15,
        preferManualMode: (map['prefer_manual_mode'] as num?)?.toInt() == 1,
        quizQuestionCount: questionCount,
        studyTagFilter: _tagList(map['study_tag_filter']),
        questionTimeLimitSeconds:
            (map['question_time_limit_seconds'] as num?)?.toInt() ?? 10,
        answerRevealMode: AnswerRevealMode.fromId(map['answer_reveal_mode']),
        quizDirection: QuizDirection.fromId(map['quiz_direction']),
        apiCacheHours: (map['api_cache_hours'] as num?)?.toInt() ?? 24,
        projectionIntervalSeconds:
            (map['projection_interval_seconds'] as num?)?.toInt() ?? 5,
        projectionShuffle: (map['projection_shuffle'] as num?)?.toInt() == 1,
        projectionLoop: (map['projection_loop'] as num?)?.toInt() != 0,
        projectionOptionLabelStyle:
            OptionLabelStyle.fromId(map['projection_option_label_style']),
        projectionReshuffleEachRound:
            (map['projection_reshuffle_each_round'] as num?)?.toInt() != 0,
        projectionAnswerDir:
            (map['projection_answer_dir'] as String?)?.trim().isEmpty ?? true
                ? null
                : (map['projection_answer_dir'] as String).trim(),
        projectionAnswerMode:
            AnswerSheetMode.fromId(map['projection_answer_mode']),
        projectionBeepEnabled:
            (map['projection_beep_enabled'] as num?)?.toInt() != 0,
        projectionBeepHz:
            (map['projection_beep_hz'] as num?)?.toInt() ?? 3000,
        projectionBeepMs:
            (map['projection_beep_ms'] as num?)?.toInt() ?? 500,
        projectionSoundSource:
            PageTurnSoundSource.fromId(map['projection_sound_source']),
        projectionSoundPath:
            (map['projection_sound_path'] as String?)?.trim().isEmpty ?? true
                ? null
                : (map['projection_sound_path'] as String).trim(),
        themeMode: AppThemeMode.fromId(map['theme_mode']),
        projectionThemeMode: AppThemeMode.fromId(map['projection_theme_mode']),
        fontScale: (map['font_scale'] as num?)?.toDouble() ?? 1.0,
        activeDeckId:
            (map['active_deck_id'] as String?)?.trim().isEmpty ?? true
                ? null
                : (map['active_deck_id'] as String).trim(),
        language: CardLanguage.fromId(map['language']),
        schedulerMode: SchedulerMode.fromId(map['scheduler_mode']),
        promptTemplateId:
            (map['prompt_template_id'] as String?)?.trim().isEmpty ?? true
                ? null
                : (map['prompt_template_id'] as String).trim(),
        homeTab: homeTabs.contains(map['home_tab'])
            ? map['home_tab']! as String
            : defaultHomeTab,
        fsrsDesiredRetention:
            normalizeRetention((map['fsrs_desired_retention'] as num?)?.toDouble() ?? defaultRetention),
        apiCallCount: (map['api_call_count'] as num?)?.toInt() ?? 0,
        apiPromptTokens: (map['api_prompt_tokens'] as num?)?.toInt() ?? 0,
        apiCompletionTokens: (map['api_completion_tokens'] as num?)?.toInt() ?? 0,
      );
  }

  /// 老版本「每轮题数」的默认值。现在的新默认是 [allQuestions]。
  static const int legacyDefaultQuestionCount = 10;

  /// 把存下来的标签列表读干净：去空白、去重、丢掉空项。
  static List<String> _tagList(Object? value) {
    if (value is! List) return const <String>[];
    final List<String> result = <String>[];
    for (final Object? item in value) {
      final String tag = (item ?? '').toString().trim();
      if (tag.isEmpty || result.contains(tag)) continue;
      result.add(tag);
    }
    return result;
  }
}
