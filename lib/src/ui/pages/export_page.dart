// 这些文件里的字符串用 + 拼是刻意的（拼 SQL、拼路径），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/anki/anki_collection.dart';
import '../../data/export/export_service.dart';
import '../../domain/models/answer_record.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../widgets/section_card.dart';

/// 「导出」页：卡片 JSON、答题记录 CSV，以及一份 Anki 能直接打开的数据库。
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  ExportResult? _last;
  String? _error;
  bool _busy = false;

  Future<void> _run(Future<ExportResult> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ExportResult result = await action();
      if (mounted) setState(() => _last = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCards() async {
    final List<WordCard> cards =
        await ref.read(cardRepositoryProvider).getAll();
    await _run(() => ref.read(exportServiceProvider).exportCardsJson(cards));
  }

  Future<void> _exportRecords() async {
    final List<WordCard> cards =
        await ref.read(cardRepositoryProvider).getAll();
    final List<AnswerRecord> records =
        await ref.read(answerRecordRepositoryProvider).getAll();
    await _run(
      () => ref
          .read(exportServiceProvider)
          .exportRecordsCsv(records, cards: cards),
    );
  }

  Future<void> _exportAnki() =>
      _run(() => ref.read(exportServiceProvider).exportAnkiCollection());

  Future<void> _copyJson() async {
    final List<WordCard> cards =
        await ref.read(cardRepositoryProvider).getAll();
    final String text = cards
        .map((WordCard card) => <String, Object?>{
              'word': card.word,
              'definition': card.definition,
              'phonetic': card.phonetic,
              'example': card.example,
              'part_of_speech': card.partOfSpeech,
              'note': card.note,
              'distractors': card.distractors,
            })
        .toList()
        .toString();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('卡片内容已复制到剪贴板。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int total = ref.watch(allCardsProvider).value?.length ?? 0;
    final int records =
        ref.watch(recentRecordsProvider).value?.length ?? 0;
    final AnkiCollection? collection = ref.watch(ankiCollectionProvider);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        SectionCard(
          title: '导出',
          subtitle: '文件会写到系统文档目录下的 word_cards_exports 文件夹。',
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _busy ? null : _exportCards,
                    icon: const Icon(Icons.data_object),
                    label: Text('导出卡片 JSON（' + total.toString() + '）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _exportRecords,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text('导出答题记录 CSV（' + records.toString() + '）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || collection == null ? null : _exportAnki,
                    icon: const Icon(Icons.storage_outlined),
                    label: const Text('导出 Anki 数据库'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _copyJson,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制卡片 JSON'),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_last != null) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '已导出 ' +
                            _last!.items.toString() +
                            ' 条，' +
                            (_last!.bytes / 1024).toStringAsFixed(1) +
                            ' KB',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _last!.path,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_last!.note != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(_last!.note!, style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _last!.path),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制路径'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SectionCard(
          title: '关于数据库',
          subtitle: '本应用存的就是 Anki 的原生数据库，不是私有格式。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const InfoLine(
                label: '格式',
                value: 'Anki collection.anki2（schema 11）',
                icon: Icons.storage_outlined,
              ),
              const InfoLine(
                label: '核心表',
                value: 'col / notes / cards / revlog / graves',
                icon: Icons.table_rows_outlined,
              ),
              if (collection?.path != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('当前库文件', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  collection!.path!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                '「导出 Anki 数据库」会生成一份可以拿 Anki 直接打开的 .anki2 文件：'
                '卡片在 notes/cards 里，复习历史在 revlog 里，牌组在 col.decks 里。'
                '本应用自己的配置与详细答题流水放在 wc_ 开头的表里，Anki 会忽略它们。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
