// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// 卡片列表：查看、搜索、编辑、删除。
class CardListPage extends ConsumerStatefulWidget {
  const CardListPage({super.key});

  @override
  ConsumerState<CardListPage> createState() => _CardListPageState();
}

class _CardListPageState extends ConsumerState<CardListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WordCard> _filter(List<WordCard> cards) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return cards;
    return cards
        .where((card) =>
            card.word.toLowerCase().contains(query) ||
            card.definition.toLowerCase().contains(query) ||
            card.language.label.contains(query) ||
            card.displayTags.any((String tag) =>
                tag.toLowerCase().contains(query)))
        .toList(growable: false);
  }

  Future<bool> _confirmDelete(WordCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张卡片？'),
        content: Text('「' + card.word + '」及其答题记录会一并从本机删除，不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsProvider);
    final theme = Theme.of(context);
    final all = cardsAsync.value ?? const <WordCard>[];
    final cards = _filter(all);
    final mastered = all.where((card) => card.mastery >= kMasteryLine).length;
    final headerText =
        '共 ' + all.length.toString() + ' 张　已掌握 ' + mastered.toString() + ' 张';

    return Scaffold(
      appBar: AppBar(
        title: const Text('卡片列表'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(headerText, style: theme.textTheme.labelMedium),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索单词或释义',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: switch (cards) {
                  _ when cardsAsync.isLoading => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  _ when all.isEmpty => const _EmptyHint(),
                  _ when cards.isEmpty => const Center(
                      child: Text('没有匹配的卡片'),
                    ),
                  _ => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return _CardTile(
                          card: card,
                          onEdit: () => _showEditDialog(card),
                          onDelete: () async {
                            final ok = await _confirmDelete(card);
                            if (!ok || !mounted) return;
                            await ref
                                .read(cardRepositoryProvider)
                                .deleteById(card.id);
                            ref.invalidate(statsProvider);
                          },
                        );
                      },
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(WordCard card) async {
    final result = await showDialog<WordCard>(
      context: context,
      builder: (context) => _EditCardDialog(card: card),
    );
    if (result == null || !mounted) return;
    await ref.read(cardRepositoryProvider).upsert(result);
    ref.invalidate(statsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存「' + result.word + '」')),
    );
  }
}

/// 和 statistics 里保持一致：掌握度 80% 以上算掌握。
const double kMasteryLine = 0.8;

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.style_outlined, size: 56),
            SizedBox(height: 16),
            Text('还没有卡片，去「导入卡片」粘贴一份 JSON 吧。'),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.onEdit,
    required this.onDelete,
  });

  final WordCard card;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = masteryColor(
      scheme,
      card.mastery,
      reviewCount: card.reviewCount,
    );

    final subtitle = StringBuffer(card.definition);
    if (card.phonetic != null) {
      subtitle.write('　' + card.phonetic!);
    }

    return Dismissible(
      key: ValueKey<String>(card.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(kCardRadius),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            card.word,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          if (card.language != CardLanguage.english)
                            _MiniBadge(
                              text: card.language.label,
                              color: const Color(0xFF7C3AED),
                            ),
                          if (card.language != CardLanguage.english)
                            const SizedBox(width: 6),
                          _SourceBadge(source: card.source),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _metaText(card),
                        style: theme.textTheme.labelSmall,
                      ),
                      if (card.displayTags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: card.displayTags
                              .map(
                                (String tag) => _MiniBadge(
                                  text: tag,
                                  color: scheme.primary,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '编辑',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _metaText(WordCard card) {
    if (card.reviewCount == 0) return '还没练过';
    final percent = (card.mastery * 100).round();
    final accuracy = (card.accuracy * 100).round();
    final averageMs = card.averageReactionMs;
    final averageSeconds = (averageMs / 1000).toStringAsFixed(1);
    return '掌握度 ' +
        percent.toString() +
        '%　练习 ' +
        card.reviewCount.toString() +
        ' 次　正确率 ' +
        accuracy.toString() +
        '%　平均 ' +
        averageSeconds +
        ' 秒';
  }
}

/// 语言 / 标签用的小徽章。
class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final CardSource source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isApi = source == CardSource.api;
    final color = isApi ? const Color(0xFF0EA5E9) : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 编辑卡片内容（不涉及学习状态）。
class _EditCardDialog extends StatefulWidget {
  const _EditCardDialog({required this.card});

  final WordCard card;

  @override
  State<_EditCardDialog> createState() => _EditCardDialogState();
}

class _EditCardDialogState extends State<_EditCardDialog> {
  late final TextEditingController _word;
  late final TextEditingController _phonetic;
  late final TextEditingController _definition;
  late final TextEditingController _distractors;
  late final TextEditingController _example;
  late final TextEditingController _tags;
  late CardLanguage _language;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _language = card.language;
    _tags = TextEditingController(text: card.displayTags.join('，'));
    _word = TextEditingController(text: card.word);
    _phonetic = TextEditingController(text: card.phonetic ?? '');
    _definition = TextEditingController(text: card.definition);
    _distractors = TextEditingController(text: card.distractors.join('\n'));
    _example = TextEditingController(text: card.example ?? '');
  }

  @override
  void dispose() {
    _word.dispose();
    _phonetic.dispose();
    _definition.dispose();
    _distractors.dispose();
    _example.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑卡片'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _word,
                decoration: const InputDecoration(labelText: '单词'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phonetic,
                decoration: const InputDecoration(labelText: '音标（可空）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _definition,
                decoration: const InputDecoration(labelText: '正确释义'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _distractors,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '干扰项（每行一个，建议 4 个）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _example,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '例句（可空）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit-tags-field'),
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: '标签（逗号分隔，可空）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('语言', style: Theme.of(context).textTheme.labelMedium),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CardLanguage.values
                    .map(
                      (CardLanguage item) => ChoiceChip(
                        label: Text(item.label),
                        selected: _language == item,
                        onSelected: (_) => setState(() => _language = item),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final word = _word.text.trim();
    final definition = _definition.text.trim();
    if (word.isEmpty || definition.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('单词和正确释义不能为空')),
      );
      return;
    }
    final distractors = _distractors.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    final phonetic = _phonetic.text.trim();
    final example = _example.text.trim();

    Navigator.of(context).pop(
      widget.card.copyWith(
        word: word,
        definition: definition,
        distractors: distractors,
        phonetic: phonetic.isEmpty ? null : phonetic,
        clearPhonetic: phonetic.isEmpty,
        example: example.isEmpty ? null : example,
        clearExample: example.isEmpty,
        language: _language,
        tags: WordCard.parseTags(_tags.text),
        updatedAt: DateTime.now(),
      ),
    );
  }
}
