// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/import/anki_import.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/deck.dart';
import '../../state/providers.dart';
import '../widgets/section_card.dart';

/// 从 Anki 导出的 .anki2 直接导入：选文件 → 预览 → 入库。
///
/// 不碰源文件（只读打开），也不改动 Anki 那边的东西。
class AnkiImportPage extends ConsumerStatefulWidget {
  const AnkiImportPage({super.key});

  @override
  ConsumerState<AnkiImportPage> createState() => _AnkiImportPageState();
}

class _AnkiImportPageState extends ConsumerState<AnkiImportPage> {
  AnkiCollectionPreview? _preview;
  String? _error;
  bool _busy = false;
  bool _importing = false;

  AnkiDeckMode _deckMode = AnkiDeckMode.perAnkiDeck;
  bool _importTags = true;
  bool _overwrite = false;

  Future<void> _pick() async {
    const XTypeGroup group = XTypeGroup(
      label: 'Anki 库',
      // 只给扩展名：安卓的选文件器按 MIME 过滤，而 .anki2 没有注册的 MIME，
      // 写死 application/octet-stream 反而会让文件在部分机型上灰掉。
      extensions: <String>['anki2', 'anki21', 'collection'],
    );

    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    } catch (error) {
      if (mounted) setState(() => _error = '打不开文件选择器：' + error.toString());
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });

    try {
      final Uint8List bytes = await file.readAsBytes();
      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readBytes(bytes, fileName: file.name);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on AnkiImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '读不了这个文件：' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final AnkiCollectionPreview? preview = _preview;
    if (preview == null || !preview.hasNotes) return;

    final AppSettings settings = ref.read(currentSettingsProvider);
    final Deck? active = ref.read(activeDeckProvider);
    final String activeDeckId = ref.read(activeDeckIdProvider);

    setState(() {
      _importing = true;
      _error = null;
    });

    AnkiImportReport? report;
    try {
      report = await ref.read(ankiImportServiceProvider).import(
            preview,
            AnkiImportOptions(
              deckMode: _deckMode,
              targetDeckId: _deckMode == AnkiDeckMode.singleDeck
                  ? activeDeckId
                  : null,
              targetDeckName: _deckMode == AnkiDeckMode.singleDeck
                  ? (active?.name ?? Deck.defaultDeckName)
                  : null,
              importTags: _importTags,
              overwriteExisting: _overwrite,
              language: settings.language,
            ),
          );
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：' + error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }

    if (!mounted || report == null) return;
    await _showReport(report);
  }

  Future<void> _showReport(AnkiImportReport report) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          title: Text(report.imported > 0 ? '导入完成' : '没有导入任何卡片'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('成功导入 ' + report.imported.toString() + ' 张'),
                  if (report.createdDecks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '新建卡组：' + report.createdDecks.join('、'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (report.skippedDuplicates > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '跳过 ' +
                            report.skippedDuplicates.toString() +
                            ' 张（本地已有同名单词）',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (report.duplicateWords.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        report.duplicateWords.take(30).join('、') +
                            (report.duplicateWords.length > 30 ? ' …' : ''),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (report.warnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    ...report.warnings.map(
                      (String warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('· ' + warning,
                            style: theme.textTheme.bodySmall),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('好'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AnkiCollectionPreview? preview = _preview;
    final AppSettings settings = ref.watch(currentSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('从 Anki 导入')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: <Widget>[
              SectionCard(
                title: '选择 Anki 数据库',
                subtitle: '在 Anki 里「导出 → Anki 集合（.anki2）」得到这个文件；'
                    '.apkg 是压缩包，要先解压出里面的 collection.anki2。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        FilledButton.icon(
                          key: const Key('anki-pick-file'),
                          onPressed: _busy ? null : _pick,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.folder_open_outlined),
                          label: Text(_busy ? '读取中…' : '选择 .anki2 文件'),
                        ),
                        if (preview != null)
                          Text(
                            preview.fileName,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.error),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.error_outline,
                                size: 18, color: theme.colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (preview != null) ...<Widget>[
                SectionCard(
                  title: '预览',
                  subtitle: '只读取，不改动 Anki 文件；导入后这里的词归本应用管。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 24,
                        runSpacing: 10,
                        children: <Widget>[
                          _Metric(
                            label: '文件里的笔记',
                            value: preview.totalNotes.toString(),
                          ),
                          _Metric(
                            label: '可导入',
                            value: preview.importableCount.toString(),
                          ),
                          _Metric(
                            label: '跳过',
                            value: preview.skipped.toString(),
                          ),
                          _Metric(
                            label: '卡组',
                            value: preview.deckNames.length.toString(),
                          ),
                        ],
                      ),
                      if (preview.deckNames.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Text('会落到这些卡组', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: preview.deckNames
                              .map((String name) => Chip(label: Text(name)))
                              .toList(growable: false),
                        ),
                      ],
                      if (preview.mappings.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Text('字段对应关系', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        ...preview.mappings.map(
                          (AnkiFieldMapping mapping) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('· ' + mapping.summary,
                                style: theme.textTheme.bodySmall),
                          ),
                        ),
                      ],
                      if (preview.warnings.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        ...preview.warnings.map(
                          (String warning) => Text(
                            '提醒：' + warning,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SectionCard(
                  title: '导入选项',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('放到哪个卡组', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      SegmentedButton<AnkiDeckMode>(
                        key: const Key('anki-deck-mode'),
                        segments: AnkiDeckMode.values
                            .map(
                              (AnkiDeckMode mode) => ButtonSegment<AnkiDeckMode>(
                                value: mode,
                                label: Text(mode.label),
                              ),
                            )
                            .toList(growable: false),
                        selected: <AnkiDeckMode>{_deckMode},
                        onSelectionChanged: (Set<AnkiDeckMode> value) =>
                            setState(() => _deckMode = value.first),
                      ),
                      if (_deckMode == AnkiDeckMode.singleDeck)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '会放进当前卡组「' +
                                (ref.watch(activeDeckProvider)?.name ??
                                    Deck.defaultDeckName) +
                                '」。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _importTags,
                        onChanged: (bool value) =>
                            setState(() => _importTags = value),
                        title: const Text('带上 Anki 里的标签'),
                        subtitle: const Text('语言标签（lang::xx）会自动转成卡片语言。'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _overwrite,
                        onChanged: (bool value) =>
                            setState(() => _overwrite = value),
                        title: const Text('覆盖本地同名单词'),
                        subtitle: const Text('不覆盖时跳过重复的词；覆盖只换内容，不动本机学习进度。'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          FilledButton.icon(
                            key: const Key('anki-import-button'),
                            onPressed: _importing || !preview.hasNotes
                                ? null
                                : _import,
                            icon: _importing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_done_outlined),
                            label: Text(
                              _importing
                                  ? '导入中…'
                                  : '导入 ' +
                                      preview.importableCount.toString() +
                                      ' 张卡片',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '语言：' + settings.language.label,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
