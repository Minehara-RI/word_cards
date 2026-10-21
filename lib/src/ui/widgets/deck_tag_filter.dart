// ignore_for_file: prefer_interpolation_to_compose_strings
//
// 作答页与演示页共用的两个筛选控件：卡组（多选并集）与标签（并集/交集）。
//
// 两个页面各存一份选择，但控件长得一样 —— 同一个应用里「勾卡组」
// 不该有两种交互方式。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/deck.dart';
import '../../state/providers.dart';

/// 卡组多选（并集）。[decks] 由调用方决定候选范围：
/// 作答页不列已挂起的卡组，演示页全都列。
class DeckFilterChips extends StatelessWidget {
  const DeckFilterChips({
    super.key,
    required this.decks,
    required this.selectedIds,
    required this.onToggle,
    this.keyPrefix = 'deck-filter',
    this.emptyHint,
  });

  final List<Deck> decks;
  final List<String> selectedIds;
  final void Function(Deck deck, bool selected) onToggle;
  final String keyPrefix;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    if (decks.isEmpty) {
      return Text(
        emptyHint ?? '还没有卡组。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final Deck deck in decks)
          FilterChip(
            key: Key(keyPrefix + '-' + deck.id),
            label: Text(deck.name),
            selected: selectedIds.contains(deck.id),
            onSelected: (bool on) => onToggle(deck, on),
          ),
      ],
    );
  }
}

/// 标签多选。多个标签怎么组合由设置里的 [TagMatchMode] 决定，
/// 这里只把当前口径显示出来，不重复放开关。
class TagFilterChips extends StatelessWidget {
  const TagFilterChips({
    super.key,
    required this.tags,
    required this.selected,
    required this.onToggle,
    this.keyPrefix = 'tag-filter',
    this.emptyHint,
  });

  final List<String> tags;
  final List<String> selected;
  final void Function(String tag, bool selected) onToggle;
  final String keyPrefix;
  final String? emptyHint;

  bool _isSelected(String tag) =>
      selected.any((String item) => item.toLowerCase() == tag.toLowerCase());

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(
        emptyHint ?? '这个范围里还没有标签。去「加入」页给词打标签，这里就会出现可选。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final String tag in tags)
          FilterChip(
            key: Key(keyPrefix + '-' + tag),
            label: Text(tag),
            selected: _isSelected(tag),
            onSelected: (bool on) => onToggle(tag, on),
          ),
      ],
    );
  }
}

/// 第一次勾标签时问一次「并集还是交集」，问过就不再打扰。
///
/// 只负责问，**不写设置**：调用方要把这次的选择和筛选一起存下去。
/// 否则先存口径、再存筛选，中间从 settingsProvider 读到的可能还是旧值，
/// 会把刚写进去的 tagMatchAsked 又抹回 false。
///
/// 返回用户选的那一档；已经问过、或者用户直接关掉对话框时返回 null。
Future<TagMatchMode?> askTagMatchModeIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final AppSettings settings = ref.read(currentSettingsProvider);
  if (settings.tagMatchAsked) return null;

  final TagMatchMode? mode = await showDialog<TagMatchMode>(
    context: context,
    builder: (BuildContext dialogContext) => SimpleDialog(
      title: const Text('同时选多个标签时'),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text('选一种口径，以后两个页面都按它算；设置里随时能改。'),
        ),
        SimpleDialogOption(
          key: const Key('tag-match-any'),
          onPressed: () => Navigator.of(dialogContext).pop(TagMatchMode.any),
          child: _Option(
            title: TagMatchMode.any.label + '：' + TagMatchMode.any.description,
            subtitle: '例：选了「第四单元」和「高频」，只要带其中任一个就考。',
          ),
        ),
        SimpleDialogOption(
          key: const Key('tag-match-all'),
          onPressed: () => Navigator.of(dialogContext).pop(TagMatchMode.all),
          child: _Option(
            title: TagMatchMode.all.label + '：' + TagMatchMode.all.description,
            subtitle: '例：同时带「第四单元」和「高频」的词才考。',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('先不设'),
            ),
          ),
        ),
      ],
    ),
  );
  return mode;
}

class _Option extends StatelessWidget {
  const _Option({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 2),
        Text(subtitle, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
