// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
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
  String? _error;

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
                  _Field(controller: _word, label: '单词 *', width: 240),
                  _Field(controller: _definition, label: '释义 *', width: 340),
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
              Row(
                children: <Widget>[
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
                  if (_error != null) ...<Widget>[
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ],
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
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final int maxLines;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
