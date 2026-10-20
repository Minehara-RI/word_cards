// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/api_client.dart';
import '../../data/ai/generation_service.dart';
import '../../data/ai/prompt_templates.dart';
import '../../data/import/card_parser.dart';
import '../../data/import/import_service.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../widgets/deck_picker.dart';
import '../../state/quiz_controller.dart';
import 'quiz_page.dart';

/// 输入框里最多放多少字符。
///
/// Flutter 的输入框会把整段文本排一次版：实测把 37 万字符的 JSON 粘进来，
/// 内存涨 250 MB、UI 线程卡两秒多；而「导出整库的 JSON → 再粘回导入框」
/// 这种操作（1 MB 上下）就是 GB 级内存和几十秒卡死，Windows 直接判定窗口
/// 「未响应」，用户看到的就是「粘贴的时候崩溃」。所以超长的原文不放进输入框。
const int _maxFieldChars = 24000;

/// 手动导入页：复制 Prompt -> 去网页聊天拿 JSON -> 粘贴 -> 校验 -> 入库。
///
/// 这是「模式 A」的完整独立能力，全程不需要任何网络。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final TextEditingController _wordsController = TextEditingController();
  final TextEditingController _jsonController = TextEditingController();
  /// 整批单词共用的标签（给这一批词一起打标签）。
  final TextEditingController _batchTagsController = TextEditingController();

  // Prompt 模板和语言都记在设置里：下次打开还是上次那套。
  PromptTemplate _template = kPromptTemplates.first;
  bool _restored = false;

  /// 这批词用哪种语言（跟着设置走，选完就记住）。
  CardLanguage _resolvedLanguage() =>
      ref.read(currentSettingsProvider).language;

  void _selectLanguage(CardLanguage language, AppSettings settings) {
    ref
        .read(settingsRepositoryProvider)
        .save(settings.copyWith(language: language));
  }
  ParseResult? _result;
  Timer? _debounce;
  bool _importing = false;

  /// 太长而没放进输入框的原文；此时输入框是空的，解析与导入仍用这份原文。
  String? _oversizeText;

  /// 当前用哪种模式：false = 网页聊天导入（模式 A），true = API 直连（模式 B）。
  bool _apiMode = false;
  bool _generating = false;

  /// 最近一次模式 B 的结果（成功或失败都留着，用来画结果条）。
  GenerationOutcome? _generation;
  int? _lastLatencyMs;

  @override
  void initState() {
    super.initState();
    _jsonController.addListener(_onJsonChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _jsonController.removeListener(_onJsonChanged);
    _wordsController.dispose();
    _jsonController.dispose();
    _batchTagsController.dispose();
    super.dispose();
  }

  /// 粘贴框实时校验：防抖 250ms，用户还在打字时不做无谓解析。
  void _onJsonChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final text = _jsonController.text;
      if (text.trim().isEmpty) {
        // 输入框被清空：超长原文还在就留着它，否则回到空状态
        if (_oversizeText == null) setState(() => _result = null);
        return;
      }
      setState(() {
        // 用户自己动了输入框，以输入框为准
        _oversizeText = null;
        _result = const CardParser().parse(text);
      });
    });
  }

  /// 现在真正要导入的原文：优先输入框，输入框空着时用 [_oversizeText]。
  String get _jsonText {
    final String typed = _jsonController.text;
    return typed.trim().isEmpty ? (_oversizeText ?? '') : typed;
  }

  /// 写入待解析的原文；超过 [_maxFieldChars] 的只记在状态里，不进输入框。
  void _setJsonText(String text) {
    if (text.length <= _maxFieldChars) {
      if (_oversizeText != null) setState(() => _oversizeText = null);
      _jsonController.text = text;
      return;
    }
    _jsonController.clear();
    _debounce?.cancel();
    setState(() {
      _oversizeText = text;
      _result = const CardParser().parse(text);
    });
  }

  void _clearJson() {
    _debounce?.cancel();
    _jsonController.clear();
    setState(() {
      _oversizeText = null;
      _result = null;
    });
  }

  /// 防止把超长文本塞进输入框：拦下这次输入，原文交给 [_setJsonText]。
  ///
  /// 键盘粘贴（Ctrl+V）和右键菜单的「粘贴」都会经过 inputFormatters，
  /// 所以两种入口在这里一起挡住。
  late final TextInputFormatter _oversizeGuard =
      TextInputFormatter.withFunction((oldValue, newValue) {
    if (newValue.text.length <= _maxFieldChars) return newValue;
    final String text = newValue.text;
    // 格式化器运行在输入法回调里，延后一拍再改状态，避免重入
    scheduleMicrotask(() {
      if (mounted) _setJsonText(text);
    });
    return oldValue;
  });

  /// 单词列表没有「不进输入框也照用」的余地，超长就直接拒绝并提示。
  late final TextInputFormatter _wordsOversizeGuard =
      TextInputFormatter.withFunction((oldValue, newValue) {
    if (newValue.text.length <= _maxFieldChars) return newValue;
    scheduleMicrotask(() {
      if (mounted) {
        _toast('粘贴内容太长了（一次最多 $_maxFieldChars 字符），请分批粘贴');
      }
    });
    return oldValue;
  });

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyPrompt() async {
    final words = _wordsController.text.trim();
    if (words.isEmpty) {
      _toast(_template.isBatch ? '请先输入单词列表（每行一个）' : '请先输入要学的单词');
      return;
    }
    final prompt = _template.build(words, language: _resolvedLanguage());
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    _toast('Prompt 已复制，去 ChatGPT / Claude / DeepSeek 粘贴发送');
  }

  /// 直接加入卡组。
  ///
  /// [createNewDeck] 为 true 时先让用户给新卡组起个名字，这一批词就落到新卡组里；
  /// 否则合并进当前卡组。两个选择都摆在按钮上，用户自己决定。
  Future<void> _import({required bool createNewDeck}) async {
    final text = _jsonText;
    if (text.trim().isEmpty) return;

    final CardLanguage language = _resolvedLanguage();
    final List<String> tags = WordCard.parseTags(_batchTagsController.text);

    String deckId = ref.read(activeDeckIdProvider);
    if (createNewDeck) {
      final Deck? deck = await showNewDeckDialog(context, ref);
      if (deck == null) return;
      deckId = deck.id;
    }
    if (!mounted) return;

    setState(() => _importing = true);
    final service = ref.read(importServiceProvider);

    ImportReport report;
    try {
      report = await service.importJson(
        text,
        deckId: deckId,
        tags: tags,
        language: language,
        cardSource: _apiMode ? CardSource.api : CardSource.manualImport,
      );
    } finally {
      // 先停掉按钮上的转圈，再弹结果框：转圈和对话框不要叠在一起
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;

    final goQuiz = await _showReport(report);
    if (!mounted) return;

    if (goQuiz) {
      final controller = ref.read(quizControllerProvider.notifier);
      await controller.start(deckId: deckId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const QuizPage()),
      );
    } else if (report.importedCount > 0) {
      _clearJson();
    }
  }

  Future<bool> _showReport(ImportReport report) async {
    final imported = report.importedCount;
    final duplicates = report.duplicateCount;
    final failed = report.failedCount;
    final scheme = Theme.of(context).colorScheme;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(imported > 0 ? '导入完成' : '没有导入任何卡片'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ResultLine(
                  icon: Icons.check_circle_outline,
                  color: imported > 0 ? const Color(0xFF16A34A) : scheme.outline,
                  text: '成功导入 $imported 张',
                ),
                if (duplicates > 0)
                  _ResultLine(
                    icon: Icons.content_copy_outlined,
                    color: const Color(0xFFF59E0B),
                    text: '跳过 $duplicates 张（本地已有同名单词）',
                  ),
                if (failed > 0)
                  _ResultLine(
                    icon: Icons.error_outline,
                    color: scheme.error,
                    text: '有 $failed 处问题未导入',
                  ),
                if (report.duplicates.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('跳过的单词', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    report.duplicates.join('、'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (report.errors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('具体问题', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  ...report.errors.map(
                    (issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '· ' + issue.display,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ),
                ],
                if (report.warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('提醒', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  ...report.warnings.map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('· ' + warning,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续导入'),
          ),
          if (imported > 0)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('立即测验'),
            ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 切换模式；顺带记进设置（preferManualMode），下次打开还是这个模式。
  void _setMode(bool apiMode, AppSettings settings) {
    setState(() => _apiMode = apiMode);
    ref
        .read(settingsRepositoryProvider)
        .save(settings.copyWith(preferManualMode: !apiMode));
  }

  /// 模式 B：一次请求 → 原文写进粘贴框 → 后面走和模式 A 完全一样的解析与入库。
  ///
  /// 失败也把原文（如果有）填进粘贴框：这就是「降级回模式 A」的那一步。
  Future<void> _generate() async {
    final String words = _wordsController.text.trim();
    if (words.isEmpty) {
      _toast(_template.isBatch ? '请先输入单词列表（每行一个）' : '请先输入要学的单词');
      return;
    }
    final AppSettings settings = ref.read(currentSettingsProvider);
    setState(() {
      _generating = true;
      _generation = null;
    });

    final Stopwatch watch = Stopwatch()..start();
    final GenerationOutcome outcome =
        await ref.read(generationServiceProvider).generate(
              words: words,
              template: _template,
              language: _resolvedLanguage(),
              settings: settings,
            );
    watch.stop();
    if (!mounted) return;

    setState(() {
      _generating = false;
      _generation = outcome;
      _lastLatencyMs = watch.elapsedMilliseconds;
    });
    // 模型偶尔会吐很长的原文，同样不能直接塞进输入框
    if (outcome.hasRawResponse) _setJsonText(outcome.response);

    if (!outcome.ok) return;

    if (!outcome.fromCache) {
      // 只有真的发出请求才算调用次数与 token；缓存命中不花钱。
      unawaited(
        ref.read(settingsRepositoryProvider).save(
              settings.addApiUsage(
                calls: 1,
                promptTokens: outcome.promptTokens,
                completionTokens: outcome.completionTokens,
              ),
            ),
      );
    }
    final String prefix = outcome.fromCache ? '命中缓存：' : '生成完成：';
    _toast('$prefix${outcome.cardCount} 张卡片已填进粘贴框');
  }

  void _fillSample() {
    _wordsController.text = 'abandon\nmeticulous';
    _setJsonText(kSampleJson);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AsyncValue<AppSettings> settingsAsync =
        ref.watch(settingsProvider);
    final AppSettings settings = settingsAsync.value ?? const AppSettings();
    // 设置是异步读出来的：读到之后恢复上次选的模板（只做一次）。
    if (!_restored && settingsAsync.hasValue) {
      _restored = true;
      _template = promptTemplateById(settings.promptTemplateId);
      // 上次用什么模式，这次还用什么模式。
      _apiMode = settings.preferredSource == CardSource.api;
    }
    final result = _result;
    final canImport = result != null && result.hasCards && !_importing;

    return Scaffold(
      appBar: AppBar(title: const Text('导入卡片')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: <Widget>[
              const DeckBar(),
              const SizedBox(height: 16),
              _StepCard(
                index: 1,
                title: _apiMode ? '直接生成卡片' : '复制 Prompt 给大模型',
                subtitle: _apiMode
                    ? '应用直接调 API，把返回的 JSON 写进下面的粘贴框；'
                        '解析、去重、入库和模式 A 完全一样。'
                    : '应用不联网也能用：把下面这段发给任意网页版大模型，让它返回 JSON。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SegmentedButton<bool>(
                      key: const Key('import-mode-switch'),
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('网页聊天导入'),
                          icon: Icon(Icons.content_paste_outlined),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('API 直连'),
                          icon: Icon(Icons.bolt_outlined),
                        ),
                      ],
                      selected: <bool>{_apiMode},
                      onSelectionChanged: (Set<bool> value) =>
                          _setMode(value.first, settings),
                    ),
                    if (_apiMode && !settings.hasApiCredentials) ...<Widget>[
                      const SizedBox(height: 12),
                      const _ModeHint(
                        text: '还没有配好 API：去「设置 → AI 生成（模式 B）」'
                            '选一家提供商、填地址和密钥；也可以继续用网页聊天导入。',
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kPromptTemplates
                          .map(
                            (template) => ChoiceChip(
                              label: Text(template.name),
                              selected: template.id == _template.id,
                              onSelected: (_) {
                                setState(() => _template = template);
                                ref.read(settingsRepositoryProvider).save(
                                      settings.copyWith(
                                        promptTemplateId: template.id,
                                      ),
                                    );
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    Text(_template.description, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('import-words-field'),
                      controller: _wordsController,
                      inputFormatters: <TextInputFormatter>[
                        _wordsOversizeGuard,
                      ],
                      minLines: 1,
                      maxLines: _template.isBatch ? 5 : 1,
                      decoration: InputDecoration(
                        labelText: _template.isBatch ? '单词列表（每行一个）' : '要学的单词',
                        hintText: _template.isBatch ? 'abandon\nmeticulous' : 'abandon',
                        prefixIcon: const Icon(Icons.spellcheck_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        if (_apiMode)
                          FilledButton.icon(
                            onPressed: _generating ? null : _generate,
                            icon: _generating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.bolt_outlined),
                            label: Text(_generating ? '生成中…' : '生成卡片'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _copyPrompt,
                            icon: const Icon(Icons.copy_all_outlined),
                            label: const Text('复制 Prompt'),
                          ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _fillSample,
                          child: const Text('填入示例数据'),
                        ),
                      ],
                    ),
                    if (_generation != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _GenerationPanel(
                        outcome: _generation!,
                        latencyMs: _lastLatencyMs,
                        onRetry: _generating ? null : _generate,
                        onFallback: () => _setMode(false, settings),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        _apiMode ? '预览将要发送的内容' : '预览将要复制的内容',
                      ),
                      children: <Widget>[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: schemeOf(context).surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            _template.build(
                              _wordsController.text.trim().isEmpty
                                  ? 'abandon'
                                  : _wordsController.text.trim(),
                              language: _resolvedLanguage(),
                            ),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _StepCard(
                index: 2,
                title: '粘贴模型返回的内容',
                subtitle: '直接整段粘贴即可：代码块、前后闲聊、中文字段名都能识别。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_oversizeText != null) ...<Widget>[
                      _OversizeNotice(
                        chars: _oversizeText!.length,
                        cardCount: result?.cards.length ?? 0,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: const Key('import-json-field'),
                      controller: _jsonController,
                      inputFormatters: <TextInputFormatter>[_oversizeGuard],
                      minLines: 8,
                      maxLines: 16,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '[{"word": "abandon", "definition": "v. 放弃；抛弃", "distractors": [...]}]',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ValidationPanel(result: result),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 300,
                          child: TextField(
                            key: const Key('import-tags-field'),
                            controller: _batchTagsController,
                            decoration: const InputDecoration(
                              labelText: '整批标签（逗号分隔，可留空）',
                              hintText: '例如：考研，第四单元',
                              isDense: true,
                              prefixIcon: Icon(Icons.sell_outlined, size: 18),
                            ),
                          ),
                        ),
                        Text('语言', style: theme.textTheme.labelMedium),
                        for (final CardLanguage language in CardLanguage.values)
                          ChoiceChip(
                            label: Text(language.label),
                            selected: _resolvedLanguage() == language,
                            onSelected: (_) => _selectLanguage(language, settings),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '整批标签会和每张卡片自己的标签合并；语言决定这批词按哪种语言处理。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '直接加入哪个卡组？',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: canImport
                              ? () => _import(createNewDeck: false)
                              : null,
                          icon: _importing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.playlist_add_outlined),
                          label: Text(
                            result != null && result.hasCards
                                ? '合并到当前卡组（' +
                                    result.cards.length.toString() +
                                    ' 张）'
                                : '合并到当前卡组',
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: canImport
                              ? () => _import(createNewDeck: true)
                              : null,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('放入新卡组…'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed:
                              _jsonText.trim().isEmpty ? null : _clearJson,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ColorScheme schemeOf(BuildContext context) => Theme.of(context).colorScheme;
}

/// 把字符数说成好读的量级（原文动辄几十万字符）。
String _humanChars(int n) {
  if (n >= 10000) return (n / 10000).toStringAsFixed(1) + ' 万字符';
  if (n >= 1000) return (n / 1000).toStringAsFixed(1) + ' 千字符';
  return n.toString() + ' 字符';
}

/// 超长原文的说明条：原文没进输入框，但照样会参与解析与导入。
class _OversizeNotice extends StatelessWidget {
  const _OversizeNotice({required this.chars, required this.cardCount});

  final int chars;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String limit = (_maxFieldChars / 10000).toStringAsFixed(1);
    final String countNote = cardCount > 0 ? '（$cardCount 张卡片）' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.content_paste_off_outlined,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '已读取 ' + _humanChars(chars) + ' 原文' + countNote + '，没有放进输入框',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '输入框只放得下 ' + limit + ' 万字符以内的原文，更长的会把窗口卡死。'
                  '这份原文会完整参与解析与导入，直接点下面的按钮就行；'
                  '想重新粘贴就先点「清空」。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行灰色提示（比如「还没配 API」）。
class _ModeHint extends StatelessWidget {
  const _ModeHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// 模式 B 的结果条：成功给用量，失败给「怎么办」+ 一键降级回模式 A。
class _GenerationPanel extends StatelessWidget {
  const _GenerationPanel({
    required this.outcome,
    this.latencyMs,
    this.onRetry,
    this.onFallback,
  });

  final GenerationOutcome outcome;
  final int? latencyMs;
  final VoidCallback? onRetry;
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AiApiFailure? failure = outcome.failure;
    final Color color = failure == null ? const Color(0xFF16A34A) : scheme.error;
    final String usage = '解析出 ${outcome.cardCount} 张卡片'
        '${outcome.fromCache ? '' : ' · 用时 ${latencyMs ?? 0} 毫秒'}'
        '${outcome.totalTokens > 0 ? ' · token 输入 ${outcome.promptTokens} / 输出 ${outcome.completionTokens}' : ''}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                failure == null
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failure == null
                      ? (outcome.fromCache
                          ? '命中缓存，这次没有请求 API、也没有花钱'
                          : '生成成功')
                      : failure.message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (failure == null) ...<Widget>[
            Text(usage, style: theme.textTheme.bodySmall),
            if (outcome.truncated)
              Text(
                '注意：输出被模型的长度上限截断了，可能有卡片没生成完整。',
                style: theme.textTheme.bodySmall,
              ),
          ],
          if (failure != null) ...<Widget>[
            if (failure.hint != null)
              Text(failure.hint!, style: theme.textTheme.bodySmall),
            if (outcome.hasRawResponse)
              Text(
                '模型原文已经填进下面的粘贴框，可以直接手改。',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                if (onFallback != null)
                  TextButton.icon(
                    onPressed: onFallback,
                    icon: const Icon(Icons.content_paste_outlined, size: 18),
                    label: const Text('改用网页聊天导入'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// 实时校验结果面板：成功给预览，失败给到「第几张卡片、缺什么字段」。
class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.result});

  final ParseResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = result;

    if (current == null) {
      return _Shell(
        color: scheme.surfaceContainerHighest,
        borderColor: scheme.outlineVariant,
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 18, color: scheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '粘贴后会自动校验格式，并告诉你能导入几张。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    if (current.hasCards) {
      final previewCount = current.cards.length > 5 ? 5 : current.cards.length;
      final preview = current.cards.take(previewCount).toList(growable: false);
      final more = current.cards.length - previewCount;
      final countText = '解析成功：' + current.cards.length.toString() + ' 张卡片';

      return _Shell(
        color: const Color(0xFF16A34A).withValues(alpha: 0.08),
        borderColor: const Color(0xFF16A34A).withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.check_circle_outline,
                    size: 18, color: Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    countText,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (current.repaired)
                  const _Tag(text: '已自动修复格式', color: Color(0xFFF59E0B)),
              ],
            ),
            const SizedBox(height: 10),
            ...preview.map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 130,
                      child: Text(
                        card.word,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        card.definition,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      card.distractors.length.toString() + ' 干扰项',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            if (more > 0)
              Text('…还有 $more 张', style: theme.textTheme.bodySmall),
            // 部分成功的情况：把没导入进去的那几条也明明白白列出来
            if (current.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '另外有 ' +
                    current.issues.length.toString() +
                    ' 处问题没有导入：',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              ...current.issues.map(
                (issue) => Text(
                  '· ' + issue.display,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ],
            if (current.warnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              // 一条提醒一行，几百张卡时能列出上千行、把页面顶出上万像素，
              // 所以只显示前几条，其余合并成一句。
              ...current.warnings.take(3).map(
                    (warning) => Text(
                      '提醒：' + warning,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFFB45309)),
                    ),
                  ),
              if (current.warnings.length > 3)
                Text(
                  '…还有 ' +
                      (current.warnings.length - 3).toString() +
                      ' 条提醒（不影响导入）',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFB45309)),
                ),
            ],
          ],
        ),
      );
    }

    final issues = current.issues;
    final issueCount = issues.length.toString();
    return _Shell(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      borderColor: scheme.error.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '暂时无法导入（$issueCount 处问题）',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...issues.take(8).map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· ' + issue.display,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          if (issues.length > 8)
            Text('…还有 ' + (issues.length - 8).toString() + ' 处',
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.child,
    required this.color,
    required this.borderColor,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final int index;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    index.toString(),
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// 「填入示例数据」用的内容。
///
/// 故意包了一层 Markdown 代码块并加了前后闲聊，顺便演示解析器的容错能力。
const String kSampleJson = '''好的，下面是你要的单词卡片：

```json
[
  {
    "word": "abandon",
    "phonetic": "/əˈbændən/",
    "partOfSpeech": "verb",
    "definition": "v. 放弃；抛弃",
    "distractors": ["v. 遵守；坚持", "v. 维持；供养", "v. 增加；扩大", "v. 分配；指派"],
    "example": "He abandoned his car in the snow."
  },
  {
    "单词": "meticulous",
    "音标": "/məˈtɪkjələs/",
    "词性": "adjective",
    "释义": "adj. 一丝不苟的；极其仔细的",
    "干扰项": ["adj. 漫不经心的", "adj. 慷慨大方的", "adj. 沉默寡言的", "adj. 固执己见的"],
    "例句": "She kept meticulous records of every experiment."
  },
  {
    "word": "resilient",
    "phonetic": "/rɪˈzɪliənt/",
    "definition": "adj. 有韧性的；能迅速恢复的",
    "distractors": ["adj. 易碎的", "adj. 冷淡的", "adj. 奢侈的", "adj. 含糊的"]
  }
]
```

需要我再补几个词吗？''';
