// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/ai/api_client.dart';
import '../../data/ai/card_completion.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../widgets/deck_picker.dart';
import '../widgets/section_card.dart';
import 'anki_import_page.dart';
import 'card_list_page.dart';
import 'import_page.dart';

/// 「加入」页：手动加一张卡，或者去批量导入 / 管理卡片。
///
/// 所有加进来的词都进**当前卡组**；只有用户在「更换卡组 / 开启新卡组」
/// 时才会换卡组。标签既可以给单张卡打，也可以在批量导入时整批打。
class AddPage extends ConsumerStatefulWidget {
  const AddPage({super.key});

  @override
  ConsumerState<AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<AddPage> {
  final TextEditingController _word = TextEditingController();
  final TextEditingController _definition = TextEditingController();
  final TextEditingController _phonetic = TextEditingController();
  final TextEditingController _partOfSpeech = TextEditingController();
  final TextEditingController _example = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _distractors = TextEditingController();
  final TextEditingController _tags = TextEditingController();

  // 语言选择跟着设置走：选完就记住，加入页 / 导入页 / 设置页看到的是同一个。
  bool _saving = false;
  bool _completing = false;
  String? _error;

  /// 必填项齐了才允许用 AI 补全：没有单词和释义，模型也无从补起。
  bool get _canComplete =>
      _word.text.trim().isNotEmpty && _definition.text.trim().isNotEmpty;

  @override
  void dispose() {
    _word.dispose();
    _definition.dispose();
    _phonetic.dispose();
    _partOfSpeech.dispose();
    _example.dispose();
    _note.dispose();
    _distractors.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// 干扰项可以按换行、逗号、分号、顿号混着写。
  static List<String> parseDistractors(String raw) => raw
      .split(RegExp(r'[\n,，;；、]+'))
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);

  Future<void> _save(String deckId, CardLanguage language) async {
    final String word = _word.text.trim();
    final String definition = _definition.text.trim();
    if (word.isEmpty || definition.isEmpty) {
      setState(() => _error = '单词和释义都必须填。');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(cardRepositoryProvider);
      final WordCard? existing =
          await repository.findByWord(word, deckId: deckId);
      final DateTime now = DateTime.now();
      final List<String> distractors = await _resolveDistractors(
        parseDistractors(_distractors.text),
        definition,
        deckId,
      );

      final WordCard card = WordCard(
        id: existing?.id ?? newId(),
        word: word,
        definition: definition,
        distractors: distractors,
        phonetic: _blankToNull(_phonetic.text),
        example: _blankToNull(_example.text),
        partOfSpeech: _blankToNull(_partOfSpeech.text),
        note: _blankToNull(_note.text),
        deckId: deckId,
        language: language,
        tags: WordCard.parseTags(_tags.text),
        source: CardSource.manualImport,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        reviewCount: existing?.reviewCount ?? 0,
        correctCount: existing?.correctCount ?? 0,
        wrongCount: existing?.wrongCount ?? 0,
        totalReactionMs: existing?.totalReactionMs ?? 0,
        mastery: existing?.mastery ?? 0,
        lastReviewedAt: existing?.lastReviewedAt,
        nextReviewAt: existing?.nextReviewAt,
        intervalDays: existing?.intervalDays ?? 0,
        easeFactor: existing?.easeFactor ?? 2.5,
        fsrs: existing?.fsrs,
      );
      await repository.upsert(card);

      if (!mounted) return;
      _clearForm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? '已加入「' + word + '」' : '「' + word + '」已存在，已更新内容'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 干扰项不够 4 个时，从同一卡组里别的卡片借几个释义凑数。
  Future<List<String>> _resolveDistractors(
    List<String> current,
    String definition,
    String deckId,
  ) async {
    final List<String> result = <String>[...current];
    if (result.length >= WordCard.targetDistractorCount) return result;

    final List<WordCard> cards =
        await ref.read(cardRepositoryProvider).getAll(deckId: deckId);
    final String target = definition.trim();
    for (final WordCard card in cards) {
      if (result.length >= WordCard.targetDistractorCount) break;
      final String candidate = card.definition.trim();
      if (candidate.isEmpty || candidate == target) continue;
      if (result.contains(candidate)) continue;
      result.add(candidate);
    }
    return result;
  }

  /// AI 补全：把单词 + 释义发给模型，只补空着的非必填项。
  ///
  /// 用户自己填过的字段一律不动 —— 「补全」不是「覆盖」。
  Future<void> _aiComplete(CardLanguage language) async {
    if (!_canComplete) {
      _toast('先填好单词和释义，再用 AI 补全。这两项是必填的。');
      return;
    }
    final AppSettings settings = ref.read(currentSettingsProvider);
    if (!settings.hasApiCredentials) {
      _toast('AI 补全要先在设置页配好 API（地址、模型、密钥）。'
          '这个功能只走 API，不提供复制 Prompt 到网页的做法。');
      return;
    }

    setState(() {
      _completing = true;
      _error = null;
    });

    try {
      final outcome = await ref.read(cardCompletionServiceProvider).complete(
            word: _word.text.trim(),
            definition: _definition.text.trim(),
            language: language,
            settings: settings,
            existingPhonetic: _blankToNull(_phonetic.text),
            existingPartOfSpeech: _blankToNull(_partOfSpeech.text),
            existingExample: _blankToNull(_example.text),
            existingNote: _blankToNull(_note.text),
            existingDistractors: parseDistractors(_distractors.text),
          );
      if (!mounted) return;

      // 花了 token 就记一笔，不管解析成没成（缓存命中不算）。
      if (!outcome.fromCache &&
          (outcome.promptTokens > 0 || outcome.completionTokens > 0)) {
        await ref.read(settingsRepositoryProvider).save(
              ref.read(currentSettingsProvider).addApiUsage(
                    calls: 1,
                    promptTokens: outcome.promptTokens,
                    completionTokens: outcome.completionTokens,
                  ),
            );
      }

      final AiApiFailure? failure = outcome.failure;
      if (failure != null) {
        _toast(failure.hint == null
            ? failure.message
            : failure.message + '：' + failure.hint!);
        return;
      }

      final CardCompletion completion = outcome.completion!;
      final List<String> filled = <String>[];
      if (completion.phonetic != null && _phonetic.text.trim().isEmpty) {
        _phonetic.text = completion.phonetic!;
        filled.add('音标');
      }
      if (completion.partOfSpeech != null &&
          _partOfSpeech.text.trim().isEmpty) {
        _partOfSpeech.text = completion.partOfSpeech!;
        filled.add('词性');
      }
      if (completion.example != null && _example.text.trim().isEmpty) {
        _example.text = completion.example!;
        filled.add('例句');
      }
      if (completion.note != null && _note.text.trim().isEmpty) {
        _note.text = completion.note!;
        filled.add('备注');
      }
      final List<String> existing = parseDistractors(_distractors.text);
      if (completion.distractors.isNotEmpty &&
          existing.length < WordCard.targetDistractorCount) {
        final List<String> merged = List<String>.of(existing);
        for (final String item in completion.distractors) {
          if (merged.length >= WordCard.targetDistractorCount) break;
          if (merged.any(
            (String have) => have.toLowerCase() == item.toLowerCase(),
          )) {
            continue;
          }
          if (item.trim() == _definition.text.trim()) continue;
          merged.add(item);
        }
        if (merged.length != existing.length) {
          _distractors.text = merged.join('\n');
          filled.add('干扰项');
        }
      }
      if (!mounted) return;
      setState(() {});
      _toast(filled.isEmpty
          ? 'AI 没有带来新的补充（已经填过的一律保留）。'
          : 'AI 补全完成：' + filled.join('、'));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm() {
    _word.clear();
    _definition.clear();
    _phonetic.clear();
    _partOfSpeech.clear();
    _example.clear();
    _note.clear();
    _distractors.clear();
    // 标签刻意保留：一次给一批词打同一个标签时不用重复输入。
  }

  static String? _blankToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final String deckId = ref.watch(activeDeckIdProvider);
    final Deck? activeDeck = ref.watch(activeDeckProvider);
    final String? selectedDeck = ref.watch(selectedDeckProvider);
    final int total = ref.watch(allCardsProvider).value?.length ?? 0;
    final List<WordCard> deckCards = ref.watch(deckCardsProvider);
    final List<String> knownTags = _knownTags(deckCards);
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ThemeData theme = Theme.of(context);
    final CardLanguage language =
        ref.watch(currentSettingsProvider).language;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        DeckBar(),
        const SizedBox(height: 16),
        SectionCard(
          title: '手动添加一张卡片',
          subtitle:
              '单词和释义是必填，其它都可以留空；干扰项不够会自动从同一卡组补齐。',
          trailing: Text('库里共 ' + total.toString() + ' 张',
              style: theme.textTheme.labelMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _Field(
                    controller: _word,
                    label: '单词 *',
                    width: 240,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Field(
                    controller: _definition,
                    label: '释义 *',
                    width: 340,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Field(controller: _phonetic, label: '音标', width: 200),
                  _Field(controller: _partOfSpeech, label: '词性', width: 140),
                  _Field(controller: _example, label: '例句', width: 340),
                  _Field(controller: _note, label: '备注', width: 200),
                  _Field(
                    controller: _distractors,
                    label: '干扰项（每行一个，可留空）',
                    width: 340,
                    maxLines: 3,
                  ),
                  _Field(
                    controller: _tags,
                    label: '标签（逗号分隔，可留空）',
                    width: 340,
                    fieldKey: const Key('add-tags-field'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('语言', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CardLanguage.values
                    .map(
                      (CardLanguage item) => ChoiceChip(
                        label: Text(item.label),
                        selected: language == item,
                        onSelected: (_) => ref
                            .read(settingsRepositoryProvider)
                            .save(settings.copyWith(language: item)),
                      ),
                    )
                    .toList(growable: false),
              ),
              if (knownTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('这个卡组里已有的标签（点一下加上）',
                    style: theme.textTheme.labelSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: knownTags
                      .map(
                        (String tag) => ActionChip(
                          label: Text(tag),
                          onPressed: () => _appendTag(tag),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('add-ai-complete'),
                    // 必填项没填时按钮是灰的，但仍然可点：点一下要告诉用户差什么，
                    // 而不是按下去毫无反应。
                    onPressed: _completing ? null : () => _aiComplete(language),
                    style: _canComplete
                        ? null
                        : OutlinedButton.styleFrom(
                            foregroundColor: theme.disabledColor,
                            side: BorderSide(color: theme.disabledColor),
                          ),
                    icon: _completing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(_completing ? '正在补全…' : 'AI 补全'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _save(deckId, language),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(
                      selectedDeck == null
                          ? '加入「' + (activeDeck?.name ?? Deck.defaultDeckName) + '」'
                          : '加入卡片',
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'AI 补全：把必填的单词和释义发给设置里配好的模型，'
                '自动补齐音标、词性、例句、备注和干扰项（优先给容易混淆的）。'
                '只走 API，不提供复制 Prompt 到网页的做法；已经填过的格子不会被覆盖。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SectionCard(
          title: '批量加入',
          subtitle: '把 AI 生成的 JSON 粘进来，或者在同一页切到 API 直连让它自己生成；'
              '批量导入时可以给整批词打同一个标签。',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportPage()),
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('粘贴 JSON 批量导入'),
              ),
              OutlinedButton.icon(
                key: const Key('add-anki-import'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AnkiImportPage(),
                  ),
                ),
                icon: const Icon(Icons.library_books_outlined),
                label: const Text('导入 Anki 库（.anki2）'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CardListPage(),
                  ),
                ),
                icon: const Icon(Icons.list_alt_outlined),
                label: Text('卡片管理（' + total.toString() + '）'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 卡组里已经用过的标签，按出现次数排序，方便整批复用。
  static List<String> _knownTags(List<WordCard> cards) {
    final Map<String, int> counts = <String, int>{};
    for (final WordCard card in cards) {
      for (final String tag in card.displayTags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final List<String> tags = counts.keys.toList();
    tags.sort((String a, String b) {
      final int byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return tags.take(12).toList(growable: false);
  }

  void _appendTag(String tag) {
    final List<String> tags = WordCard.parseTags(_tags.text);
    if (tags.contains(tag)) return;
    tags.add(tag);
    _tags.text = tags.join('，');
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.width,
    this.maxLines = 1,
    this.fieldKey,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final int maxLines;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
