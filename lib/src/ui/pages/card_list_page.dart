// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/card_filler.dart';
import '../../domain/models/app_settings.dart';
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

  /// 正在补全的那张卡（按钮上转圈用）。同一时间只补一张，
  /// 免得用户连点把模型的限流打满。
  String? _fillingId;

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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _recordUsage(CardFillOutcome outcome) async {
    if (outcome.fromCache ||
        (outcome.promptTokens == 0 && outcome.completionTokens == 0)) {
      return;
    }
    final AppSettings settings = ref.read(currentSettingsProvider);
    await ref.read(settingsRepositoryProvider).save(
          settings.addApiUsage(
            calls: 1,
            promptTokens: outcome.promptTokens,
            completionTokens: outcome.completionTokens,
          ),
        );
  }

  /// 一张卡的一键补全：只填空着的字段，改完立刻落库。
  Future<void> _fillOne(WordCard card) async {
    if (_fillingId != null) return;
    final AppSettings settings = ref.read(currentSettingsProvider);
    if (!settings.hasApiCredentials) {
      _toast('AI 补全要先在设置页配好 API（地址、模型、密钥）。');
      return;
    }
    setState(() => _fillingId = card.id);
    try {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: ref.read(cardCompletionServiceProvider),
        settings: settings,
        card: card,
      );
      if (!mounted) return;
      if (outcome.changed) {
        await ref.read(cardRepositoryProvider).upsert(outcome.card);
        await _recordUsage(outcome);
        ref.invalidate(statsProvider);
      }
      _toast(outcome.message);
    } finally {
      if (mounted) setState(() => _fillingId = null);
    }
  }

  /// 批量补全当前列表里的卡片：先问范围，再逐张跑。
  Future<void> _batchFill(List<WordCard> cards) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    if (!settings.hasApiCredentials) {
      _toast('AI 补全要先在设置页配好 API（地址、模型、密钥）。');
      return;
    }
    final _FillScope? scope = await showDialog<_FillScope>(
      context: context,
      builder: (_) => _ScopeDialog(cards: cards),
    );
    if (scope == null || !mounted) return;

    final List<WordCard> targets =
        cards.where(scope.matches).toList(growable: false);
    if (targets.isEmpty) {
      _toast('当前列表里没有' + scope.label + '的卡');
      return;
    }
    final _FillSummary? summary = await showDialog<_FillSummary>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchFillDialog(cards: targets),
    );
    if (summary == null || !mounted) return;
    ref.invalidate(statsProvider);
    _toast(summary.message);
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
          IconButton(
            key: const Key('card-batch-fill'),
            tooltip: '批量补全缺项（AI）',
            onPressed: _fillingId == null && cards.isNotEmpty
                ? () => _batchFill(cards)
                : null,
            icon: const Icon(Icons.auto_fix_high),
          ),
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
                          filling: _fillingId == card.id,
                          onFill: () => _fillOne(card),
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
    required this.filling,
    required this.onFill,
    required this.onEdit,
    required this.onDelete,
  });

  final WordCard card;

  /// 这张正在补全：按钮换成转圈。
  final bool filling;

  final VoidCallback onFill;
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
                  key: Key('card-fill-' + card.id),
                  tooltip: 'AI 补全这张（只补空着的项）',
                  onPressed: filling ? null : onFill,
                  icon: filling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.auto_fix_high,
                          size: 20,
                          color: needsAiFill(card) ? scheme.primary : null,
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
///
/// 对话框里也能一键补全：只填还空着的项，补完先落在输入框里，
/// 用户看过再点「保存」—— 不要在对话框里直接改库。
class _EditCardDialog extends ConsumerStatefulWidget {
  const _EditCardDialog({required this.card});

  final WordCard card;

  @override
  ConsumerState<_EditCardDialog> createState() => _EditCardDialogState();
}

class _EditCardDialogState extends ConsumerState<_EditCardDialog> {
  late final TextEditingController _word;
  late final TextEditingController _phonetic;
  late final TextEditingController _definition;
  late final TextEditingController _partOfSpeech;
  late final TextEditingController _example;
  late final TextEditingController _note;
  late final TextEditingController _distractors;
  late final TextEditingController _tags;
  late CardLanguage _language;
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _language = card.language;
    _tags = TextEditingController(text: card.displayTags.join('，'));
    _word = TextEditingController(text: card.word);
    _phonetic = TextEditingController(text: card.phonetic ?? '');
    _definition = TextEditingController(text: card.definition);
    _partOfSpeech = TextEditingController(text: card.partOfSpeech ?? '');
    _example = TextEditingController(text: card.example ?? '');
    _note = TextEditingController(text: card.note ?? '');
    _distractors = TextEditingController(text: card.distractors.join('\n'));
  }

  @override
  void dispose() {
    _word.dispose();
    _phonetic.dispose();
    _definition.dispose();
    _partOfSpeech.dispose();
    _example.dispose();
    _note.dispose();
    _distractors.dispose();
    _tags.dispose();
    super.dispose();
  }

  static String? _blankToNull(String value) {
    final String text = value.trim();
    return text.isEmpty ? null : text;
  }

  /// 把输入框里现在的内容拼成一张卡。补全和保存都用它，
  /// 保证「看到的」就是「会被补全 / 保存的」。
  WordCard _draft() {
    final String word = _word.text.trim();
    final String definition = _definition.text.trim();
    return widget.card.copyWith(
      word: word.isEmpty ? widget.card.word : word,
      definition: definition.isEmpty ? widget.card.definition : definition,
      phonetic: _blankToNull(_phonetic.text),
      clearPhonetic: _blankToNull(_phonetic.text) == null,
      partOfSpeech: _blankToNull(_partOfSpeech.text),
      clearPartOfSpeech: _blankToNull(_partOfSpeech.text) == null,
      example: _blankToNull(_example.text),
      clearExample: _blankToNull(_example.text) == null,
      note: _blankToNull(_note.text),
      clearNote: _blankToNull(_note.text) == null,
      distractors: _distractors.text
          .split('\n')
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty)
          .toList(growable: false),
      language: _language,
      tags: WordCard.parseTags(_tags.text),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _aiFill() async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    if (!settings.hasApiCredentials) {
      _toast('AI 补全要先在设置页配好 API（地址、模型、密钥）。');
      return;
    }
    setState(() => _filling = true);
    try {
      final CardFillOutcome outcome = await fillCardWithAi(
        service: ref.read(cardCompletionServiceProvider),
        settings: settings,
        card: _draft(),
      );
      if (!mounted) return;
      if (outcome.fromCache == false &&
          (outcome.promptTokens > 0 || outcome.completionTokens > 0)) {
        await ref.read(settingsRepositoryProvider).save(
              ref.read(currentSettingsProvider).addApiUsage(
                    calls: 1,
                    promptTokens: outcome.promptTokens,
                    completionTokens: outcome.completionTokens,
                  ),
            );
      }
      if (!outcome.changed) {
        _toast(outcome.message);
        return;
      }
      final WordCard card = outcome.card;
      if (card.phonetic != null) _phonetic.text = card.phonetic!;
      if (card.partOfSpeech != null) _partOfSpeech.text = card.partOfSpeech!;
      if (card.example != null) _example.text = card.example!;
      if (card.note != null) _note.text = card.note!;
      _distractors.text = card.distractors.join('\n');
      _toast(outcome.message);
    } finally {
      if (mounted) setState(() => _filling = false);
    }
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
                controller: _partOfSpeech,
                decoration: const InputDecoration(labelText: '词性（可空）'),
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
                controller: _note,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '备注（可空）',
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
        TextButton.icon(
          key: const Key('edit-card-ai-fill'),
          onPressed: _filling ? null : _aiFill,
          icon: _filling
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high, size: 18),
          label: Text(_filling ? '正在补全…' : 'AI 补全'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final WordCard card = _draft();
    if (card.word.trim().isEmpty || card.definition.trim().isEmpty) {
      _toast('单词和正确释义不能为空');
      return;
    }
    Navigator.of(context).pop(card.copyWith(updatedAt: DateTime.now()));
  }
}

/// 批量补全的范围。
enum _FillScope {
  phonetic('缺音标'),
  distractors('缺干扰项'),
  any('有任一缺项');

  const _FillScope(this.label);

  final String label;

  bool matches(WordCard card) => switch (this) {
        _FillScope.phonetic => missingPhonetic(card),
        _FillScope.distractors => missingDistractors(card),
        _FillScope.any => needsAiFill(card),
      };
}

/// 先问清楚补哪一档：一次请求就是一次 token，不能让用户糊里糊涂点下去。
class _ScopeDialog extends StatelessWidget {
  const _ScopeDialog({required this.cards});

  final List<WordCard> cards;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('批量补全'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '当前列表里有 ' +
                  cards.length.toString() +
                  ' 张卡。补全只会填空着的字段，你写过的音标、例句不会被改掉。'
                  '每张卡一次模型请求（命中缓存不重复计费）。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final _FillScope scope in _FillScope.values)
              ListTile(
                key: Key('fill-scope-' + scope.name),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(scope.label),
                trailing: Text(
                  cards.where(scope.matches).length.toString(),
                  style: theme.textTheme.labelLarge,
                ),
                onTap: cards.where(scope.matches).isEmpty
                    ? null
                    : () => Navigator.of(context).pop(scope),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _FillSummary {
  const _FillSummary({
    required this.total,
    required this.changed,
    required this.failed,
    required this.cancelled,
    this.firstError,
  });

  final int total;
  final int changed;
  final int failed;
  final bool cancelled;
  final String? firstError;

  String get message {
    final StringBuffer buffer = StringBuffer();
    buffer.write(cancelled ? '已停止：' : '补全完成：');
    buffer.write('处理 ' + (changed + failed).toString() + '/' + total.toString());
    if (changed > 0) buffer.write('，补好 ' + changed.toString() + ' 张');
    if (failed > 0) {
      buffer.write('，失败 ' + failed.toString() + ' 张');
      if (firstError != null) buffer.write('（' + firstError! + '）');
    }
    if (changed == 0 && failed == 0) buffer.write('，没有缺项');
    return buffer.toString();
  }
}

/// 逐张跑补全。刻意串行：并发一把打上去只会撞限流，还会让进度条乱跳。
class _BatchFillDialog extends ConsumerStatefulWidget {
  const _BatchFillDialog({required this.cards});

  final List<WordCard> cards;

  @override
  ConsumerState<_BatchFillDialog> createState() => _BatchFillDialogState();
}

class _BatchFillDialogState extends ConsumerState<_BatchFillDialog> {
  int _index = 0;
  int _changed = 0;
  int _failed = 0;
  int _promptTokens = 0;
  int _completionTokens = 0;
  int _calls = 0;
  String? _firstError;
  bool _cancelled = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // 弹窗先出来，再开始跑：不然第一张慢的时候界面是空的。
    Future<void>.microtask(_run);
  }

  Future<void> _run() async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    for (final WordCard card in widget.cards) {
      if (_cancelled || !mounted) break;
      final CardFillOutcome outcome = await fillCardWithAi(
        service: ref.read(cardCompletionServiceProvider),
        settings: settings,
        card: card,
      );
      if (!mounted) return;
      if (outcome.failure != null) {
        _failed++;
        _firstError ??= outcome.failure!.message;
      } else {
        if (outcome.changed) {
          await ref.read(cardRepositoryProvider).upsert(outcome.card);
          _changed++;
        }
        if (!outcome.fromCache) {
          _calls++;
          _promptTokens += outcome.promptTokens;
          _completionTokens += outcome.completionTokens;
        }
      }
      setState(() => _index++);
    }

    if (_calls > 0 && mounted) {
      final AppSettings latest = ref.read(currentSettingsProvider);
      await ref.read(settingsRepositoryProvider).save(
            latest.addApiUsage(
              calls: _calls,
              promptTokens: _promptTokens,
              completionTokens: _completionTokens,
            ),
          );
    }
    if (!mounted) return;
    _finished = true;
    Navigator.of(context).pop(
      _FillSummary(
        total: widget.cards.length,
        changed: _changed,
        failed: _failed,
        cancelled: _cancelled,
        firstError: _firstError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = widget.cards.length;
    final int done = _index.clamp(0, total);
    return AlertDialog(
      title: const Text('正在补全'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
            ),
            const SizedBox(height: 12),
            Text('$done / $total', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '补好 ' + _changed.toString() + ' 张' +
                  (_failed > 0 ? '　失败 ' + _failed.toString() + ' 张' : ''),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '补全期间每张卡都会写库；中途点停止，已经补好的会保留。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _finished
              ? null
              : () {
                  setState(() => _cancelled = true);
                },
          child: const Text('停止'),
        ),
      ],
    );
  }
}
