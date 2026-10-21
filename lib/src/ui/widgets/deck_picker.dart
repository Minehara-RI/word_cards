// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../domain/models/deck.dart';
import '../../state/providers.dart';

/// 「当前卡组」这一行：显示现在往哪个卡组里加词，并提供更换 / 新建。
///
/// 加词永远只进当前卡组，只有用户在这里主动换卡组或开新卡组时才会变，
/// 所以这个组件出现在加入页、导入页、设置页，保证三处看到的是同一个状态。
class DeckBar extends ConsumerWidget {
  const DeckBar({super.key, this.compact = false});

  /// 紧凑模式：只显示名字和按钮，用来塞进窄一点的布局。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final String? selected = ref.watch(selectedDeckProvider);
    final Deck? active = ref.watch(activeDeckProvider);
    final String name = selected == null
        ? '全部词库（新词进「' + (active?.name ?? Deck.defaultDeckName) + '」）'
        : (active?.name ?? '默认词库');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.style_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('当前卡组', style: theme.textTheme.labelSmall),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (!compact)
                  Text(
                    '共 ' + decks.length.toString() + ' 个卡组；新加入的词都进这个卡组。',
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showDeckPicker(context, ref),
            child: const Text('更换卡组'),
          ),
          FilledButton.tonal(
            onPressed: () => showNewDeckDialog(context, ref),
            child: const Text('开启新卡组'),
          ),
        ],
      ),
    );
  }
}

/// 选一个卡组作为当前卡组。返回选中的 id（取消则为 null）。
Future<String?> showDeckPicker(BuildContext context, WidgetRef ref) async {
  final List<Deck> decks = ref.read(decksProvider).value ?? const <Deck>[];
  final String? selected = ref.read(selectedDeckProvider);

  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => SimpleDialog(
      title: const Text('选择卡组'),
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(kAllDecksValue),
          child: Row(
            children: <Widget>[
              Icon(
                selected == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              const SizedBox(width: 10),
              const Text('全部词库'),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final Deck deck in decks)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(deck.id),
            child: Row(
              children: <Widget>[
                Icon(
                  selected == deck.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // 挂起的卡组在「加入」页仍然可以选（新词还是要能加进去），
                    // 但标出来，免得用户忘了它在作答页消失是因为挂起了。
                    deck.suspended ? deck.name + '（已挂起）' : deck.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(kNewDeckValue),
          child: const Row(
            children: <Widget>[
              Icon(Icons.add, size: 18),
              SizedBox(width: 10),
              Text('开启新卡组…'),
            ],
          ),
        ),
      ],
    ),
  );

  if (result == null) return null;
  if (result == kNewDeckValue) {
    if (!context.mounted) return null;
    return (await showNewDeckDialog(context, ref))?.id;
  }
  if (result == kAllDecksValue) {
    ref.read(selectedDeckProvider.notifier).select(null);
    return null;
  }
  ref.read(selectedDeckProvider.notifier).select(result);
  return result;
}

/// 让用户给新卡组起个名字；确定后立刻建成并设为当前卡组。
Future<Deck?> showNewDeckDialog(BuildContext context, WidgetRef ref) async {
  // 输入框控制器交给对话框自己管：showDialog 返回时退场动画还在跑，
  // 在这里 dispose 会踩到「controller used after being disposed」。
  final String? name = await showDialog<String>(
    context: context,
    builder: (_) => const _NewDeckDialog(),
  );
  if (name == null || name.trim().isEmpty) return null;

  final Deck deck = Deck(
    id: newId(),
    name: name.trim(),
    createdAt: DateTime.now(),
  );
  await ref.read(deckRepositoryProvider).upsert(deck);
  ref.read(selectedDeckProvider.notifier).select(deck.id);
  return deck;
}

/// 新卡组命名对话框。自己持有输入框控制器，退场时再销毁。
class _NewDeckDialog extends StatefulWidget {
  const _NewDeckDialog();

  @override
  State<_NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<_NewDeckDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('开启新卡组'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('新卡组里的词和别的卡组互不打扰；以后加词都先加到这个卡组。'),
            const SizedBox(height: 14),
            TextField(
              key: const Key('new-deck-name'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '卡组名称',
                hintText: '例如：考研核心词 / 日语 N2',
              ),
              onSubmitted: (String value) =>
                  Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 「全部词库」在对话框里的返回值。
const String kAllDecksValue = '__all_decks__';

/// 「开启新卡组」在对话框里的返回值。
const String kNewDeckValue = '__new_deck__';
