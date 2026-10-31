// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_version.dart';
import '../../core/server_ports.dart';
import '../../data/ai/ai_providers.dart';
import '../../data/ai/api_client.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../../state/server_providers.dart';
import '../fonts.dart';
import '../platform_target.dart';
import '../widgets/deck_picker.dart';
import '../widgets/number_field.dart';

/// 设置页只放「全局的、跟一次答题无关的」东西：
/// 外观、卡组、默认语言、AI 配置、数据与关于。
///
/// 每轮题数 / 每题限时 / 正误显示 / 复习算法这些跟一次作答直接相关的选项
/// 全部搬到「作答」页里，改完立刻生效，不用来回跳页面。
///
/// 演示模式那一套深浅色只在桌面端出现：手机端不做投屏，压根没有「演示」
/// 这个入口，这一块跟着整块不画。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.target});

  /// 用哪个平台的样子画。平时不传（按 detectPlatformTarget() 判断），
  /// 测试里传 PlatformTarget.mobile 就能装作自己跑在手机上。
  final PlatformTarget? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ThemeData theme = Theme.of(context);
    final bool isDesktop = (target ?? detectPlatformTarget()).isDesktop;

    Future<void> update(AppSettings next) =>
        ref.read(settingsRepositoryProvider).save(next);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _Section(
                title: '外观',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('主界面', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<AppThemeMode>(
                      segments: AppThemeMode.values
                          .map(
                            (AppThemeMode mode) => ButtonSegment<AppThemeMode>(
                              value: mode,
                              label: Text(mode.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <AppThemeMode>{settings.themeMode},
                      onSelectionChanged: (Set<AppThemeMode> selection) =>
                          update(settings.copyWith(themeMode: selection.first)),
                    ),
                    const SizedBox(height: 18),
                    // 手机端没有课堂投影，演示模式这一套设置也就没有意义。
                    if (isDesktop) ...<Widget>[
                      Text(
                        '演示模式（全屏投影）',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '演示时的底色单独设置，和主界面互不影响：'
                        '教室灯亮就选浅色，投影仪偏暗或者要压低屏幕亮度就选深色。',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<AppThemeMode>(
                        segments: AppThemeMode.values
                            .map(
                              (AppThemeMode mode) => ButtonSegment<AppThemeMode>(
                                value: mode,
                                label: Text(mode.label),
                              ),
                            )
                            .toList(growable: false),
                        selected: <AppThemeMode>{settings.projectionThemeMode},
                        onSelectionChanged: (Set<AppThemeMode> selection) =>
                            update(
                          settings.copyWith(
                            projectionThemeMode: selection.first,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      '字号缩放：' +
                          (settings.fontScale * 100).round().toString() +
                          '%',
                      style: theme.textTheme.labelLarge,
                    ),
                    Slider(
                      value: settings.fontScale,
                      min: 0.8,
                      max: 1.4,
                      divisions: 6,
                      label: (settings.fontScale * 100).round().toString() +
                          '%',
                      onChanged: (double value) =>
                          update(settings.copyWith(fontScale: value)),
                    ),
                    Text(
                      '只缩放界面文字；演示模式有自己的一套大字号。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _Section(
                title: '卡组',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const DeckBar(),
                    const SizedBox(height: 10),
                    Text(
                      '所有加进来的词都存在当前卡组里。只有你主动「更换卡组」'
                      '或「开启新卡组」时，新词才会进到别的卡组，'
                      '旧词不会自动搬家。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text('管理卡组', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      '「挂起」= 暂时不学它：作答页选不到这个卡组，'
                      '学习概览也不算它的词；演示照样能放，再点「恢复」就回来了。'
                      '「重置」只清学习进度（复习次数、掌握度、答题记录），词都留着；'
                      '「删除」会把卡组和里面的词一起删掉，不能恢复。'
                      '默认词库可以重置，不能删除。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    const _DeckManager(),
                  ],
                ),
              ),
              _Section(
                title: '筛选',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('多个标签怎么组合', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '「作答」页与「演示」页的标签筛选共用这一档；'
                      '第一次勾标签时也会问一次，选过就不再问。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<TagMatchMode>(
                      segments: TagMatchMode.values
                          .map(
                            (TagMatchMode mode) => ButtonSegment<TagMatchMode>(
                              value: mode,
                              label: Text(mode.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <TagMatchMode>{settings.tagMatchMode},
                      onSelectionChanged: (Set<TagMatchMode> selection) => update(
                        settings.copyWith(
                          tagMatchMode: selection.first,
                          tagMatchAsked: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      settings.tagMatchMode.description +
                          '。卡组筛选永远是并集（勾几个就考几个）。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _Section(
                title: '语言',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('新词默认语言', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '决定新加入的词按哪种语言处理（出题、统计、'
                      '复制给大模型的 Prompt）。加入单张卡或批量导入时可以单独改。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CardLanguage.values
                          .map(
                            (CardLanguage language) => ChoiceChip(
                              label: Text(language.displayName),
                              selected: settings.language == language,
                              onSelected: (_) => update(
                                settings.copyWith(language: language),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    Text('英语音标用哪种', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '只影响 AI 生成卡片和「AI 补全」时索要的音标：'
                      '同一套词卡里标法要一致。已经进库的音标不会被改写；'
                      '其它语言的注音方式与口音无关。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<PhoneticAccent>(
                      key: const Key('phonetic-accent'),
                      segments: PhoneticAccent.values
                          .map(
                            (PhoneticAccent accent) =>
                                ButtonSegment<PhoneticAccent>(
                              value: accent,
                              label: Text(accent.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <PhoneticAccent>{settings.phoneticAccent},
                      onSelectionChanged: (Set<PhoneticAccent> selection) =>
                          update(
                        settings.copyWith(phoneticAccent: selection.first),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${settings.phoneticAccent.system}：'
                      '例如 water 记作 ${settings.phoneticAccent.example}。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '界面统一使用无衬线字体，日文假名、韩文谚文、俄文西里尔'
                      '都有专门的字体兜底。下面这行能直接看出有没有掉字形：',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      kFontSampleText,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const _ApiSection(),
              const _AnkiConnectSection(),
              _Section(
                title: '数据',
                child: Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('清空全部卡片'),
                      subtitle: const Text('同时清空答题统计，不可恢复'),
                      onTap: () => _clearCards(context, ref),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.restore_outlined),
                      title: const Text('清空答题记录'),
                      subtitle: const Text('保留卡片，只重置学习进度'),
                      onTap: () => _clearRecords(context, ref),
                    ),
                  ],
                ),
              ),
              _Section(
                title: '关于',
                child: Text(
                  // kAppVersion 由 scripts\gen_version.ps1 从 pubspec.yaml 生成
                  'word_flashcards ' +
                      kAppVersion +
                      '\n'
                  '所有卡片、答题记录与配置都只保存在这台设备上，'
                  '不联网、不上传、不需要账号。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearCards(BuildContext context, WidgetRef ref) async {
    final bool ok =
        await confirmDangerous(context, '清空全部卡片？', '所有卡片和答题记录都会被删除。');
    if (!ok) return;
    await ref.read(cardRepositoryProvider).deleteAll();
    await ref.read(answerRecordRepositoryProvider).deleteAll();
    ref.invalidate(statsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空')));
  }

  Future<void> _clearRecords(BuildContext context, WidgetRef ref) async {
    final bool ok = await confirmDangerous(
        context,
        '清空答题记录？',
        '卡片会保留，但练习次数与掌握度会被重置。',
      );
    if (!ok) return;
    await ref.read(answerRecordRepositoryProvider).deleteAll();
    ref.invalidate(statsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空答题记录')));
  }

}

/// 危险操作的二次确认：红按钮 + 「确定 / 取消」。
Future<bool> confirmDangerous(
  BuildContext context,
  String title,
  String message,
) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 卡组管理：每个卡组一行，带词数、重置、删除。
///
/// 「重置」= 清学习进度（复习次数 / 掌握度 / 答题记录 / FSRS），词留着；
/// 「删除」= 连词一起删。默认词库是兜底卡组，只能重置不能删。
class _DeckManager extends ConsumerWidget {
  const _DeckManager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final List<WordCard> cards =
        ref.watch(allCardsProvider).value ?? const <WordCard>[];
    final String? selected = ref.watch(selectedDeckProvider);

    if (decks.isEmpty) {
      return Text('还没有卡组。', style: theme.textTheme.bodySmall);
    }

    return Column(
      children: <Widget>[
        for (final Deck deck in decks)
          _deckRow(context, ref, theme, deck, cards, selected),
      ],
    );
  }

  Widget _deckRow(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Deck deck,
    List<WordCard> cards,
    String? selected,
  ) {
    final int count =
        cards.where((WordCard card) => card.deckId == deck.id).length;
    final bool isDefault = deck.id == Deck.defaultDeckId;
    final ButtonStyle compact = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return ListTile(
      key: Key('deck-row-' + deck.id),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        deck.suspended
            ? Icons.pause_circle_outline
            : (selected == deck.id
                ? Icons.radio_button_checked
                : Icons.style_outlined),
        size: 18,
        color: deck.suspended ? theme.colorScheme.outline : null,
      ),
      title: Text(
        deck.name,
        overflow: TextOverflow.ellipsis,
        style: deck.suspended
            ? TextStyle(color: theme.colorScheme.outline)
            : null,
      ),
      subtitle: Text(
        (count == 0 ? '空卡组' : count.toString() + ' 个词') +
            (deck.suspended ? ' · 已挂起，不作答' : ''),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextButton(
            key: Key('deck-suspend-' + deck.id),
            style: compact,
            onPressed: () => _toggleSuspended(context, ref, deck),
            child: Text(deck.suspended ? '恢复' : '挂起'),
          ),
          TextButton(
            key: Key('deck-reset-' + deck.id),
            style: compact,
            onPressed:
                count == 0 ? null : () => _resetDeck(context, ref, deck, count),
            child: const Text('重置'),
          ),
          if (!isDefault)
            TextButton(
              key: Key('deck-delete-' + deck.id),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _deleteDeck(context, ref, deck, count),
              child: const Text('删除'),
            ),
        ],
      ),
    );
  }

  /// 挂起 / 恢复：只改一个标记，词、进度、设置全都不动。
  ///
  /// 挂起当前卡组时**不改当前卡组**：用户可能只是暂时搁置，
  /// 点一下恢复就回到原来的状态，比偷偷把当前卡组切走更可预期。
  Future<void> _toggleSuspended(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
  ) async {
    final bool next = !deck.suspended;
    await ref.read(deckRepositoryProvider).upsert(
          deck.copyWith(suspended: next),
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? '已挂起「' + deck.name + '」：作答与学习概览都不再算它'
              : '已恢复「' + deck.name + '」',
        ),
      ),
    );
  }

  Future<void> _resetDeck(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
    int count,
  ) async {
    final bool ok = await confirmDangerous(
      context,
      '重置「' + deck.name + '」？',
      '这个词库里的 ' + count.toString() + ' 个词会保留，但复习次数、掌握度、'
          '答题记录和 FSRS 进度全部清零，不能恢复。',
    );
    if (!ok) return;
    await ref.read(cardRepositoryProvider).resetProgress(deckId: deck.id);
    ref.invalidate(statsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已重置「' + deck.name + '」')),
    );
  }

  Future<void> _deleteDeck(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
    int count,
  ) async {
    final bool ok = await confirmDangerous(
      context,
      '删除卡组「' + deck.name + '」？',
      count == 0
          ? '这个卡组是空的，删掉不影响任何词。'
          : '里面的 ' + count.toString() + ' 个词会跟着一起删掉，不能恢复。',
    );
    if (!ok) return;
    await ref.read(cardRepositoryProvider).deleteAll(deckId: deck.id);
    await ref.read(deckRepositoryProvider).delete(deck.id);
    if (ref.read(selectedDeckProvider) == deck.id) {
      ref.read(selectedDeckProvider.notifier).select(null);
    }
    ref.invalidate(statsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除「' + deck.name + '」')),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}


/// 「AI 生成（模式 B：API 直连）」这一块。
///
/// 是 StatefulWidget：地址 / 模型 / 密钥三个输入框有自己的 controller，
/// 保存走 onChanged（改一个字符就存一次，和「所有设定都会被记住」一致）。
class _ApiSection extends ConsumerStatefulWidget {
  const _ApiSection();

  @override
  ConsumerState<_ApiSection> createState() => _ApiSectionState();
}

class _ApiSectionState extends ConsumerState<_ApiSection> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _key;
  late final TextEditingController _model;

  bool _showKey = false;
  bool _testing = false;
  String? _testOk;
  AiApiFailure? _testFailure;
  int _cacheCount = 0;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = ref.read(currentSettingsProvider);
    _baseUrl = TextEditingController(text: settings.apiBaseUrl ?? '');
    _key = TextEditingController(text: settings.apiKey ?? '');
    _model = TextEditingController(text: settings.apiModel ?? '');
    _refreshCache();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings Function(AppSettings current) change) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    await ref.read(settingsRepositoryProvider).save(change(settings));
  }

  Future<void> _refreshCache() async {
    final int count = await ref.read(apiCacheRepositoryProvider).count();
    if (!mounted) return;
    setState(() => _cacheCount = count);
  }

  /// 点提供商 = 把地址和模型填好；用户随后还能自己改。
  void _pickProvider(AiProvider provider) {
    if (provider.id == 'custom') return;
    _baseUrl.text = provider.baseUrl;
    _model.text = provider.model;
    setState(() {
      _testOk = null;
      _testFailure = null;
    });
    _save(
      (AppSettings s) => s.copyWith(
        apiBaseUrl: provider.baseUrl,
        apiModel: provider.model,
      ),
    );
  }

  /// 测试连接：发一条最短的请求。成功也给用户看一眼模型到底回了什么。
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testOk = null;
      _testFailure = null;
    });
    final AppSettings settings = ref.read(currentSettingsProvider);
    final AiApiClient client = ref.read(aiApiClientProvider);
    final Stopwatch watch = Stopwatch()..start();
    try {
      final AiCompletion completion = await client.complete(
        AiRequest(
          baseUrl: settings.apiBaseUrl ?? '',
          apiKey: settings.apiKey ?? '',
          model: settings.apiModel ?? '',
          prompt: '请只回复两个字：正常',
          timeoutSeconds: settings.apiTimeoutSeconds,
          maxTokens: 16,
        ),
      );
      watch.stop();
      await _save(
        (AppSettings s) => s.addApiUsage(
          calls: 1,
          promptTokens: completion.promptTokens,
          completionTokens: completion.completionTokens,
        ),
      );
      if (!mounted) return;
      final String reply = completion.content.trim().split('\n').first;
      setState(() {
        _testing = false;
        _testOk = '连接正常：' + watch.elapsedMilliseconds.toString() +
            ' 毫秒，模型回了「' + reply + '」';
      });
    } on AiApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testFailure = failure;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testFailure = AiApiFailure(AiFailureKind.network, '测试失败：$error');
      });
    }
  }

  Future<void> _clearCache() async {
    await ref.read(apiCacheRepositoryProvider).clear();
    if (!mounted) return;
    setState(() => _cacheCount = 0);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空生成缓存')));
  }

  Future<void> _resetUsage() => _save((AppSettings s) => s.resetApiUsage());

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ThemeData theme = Theme.of(context);
    final AiProvider? current = providerForBaseUrl(settings.apiBaseUrl);
    final String providerNote = current == null
        ? '当前是自定义地址：任何 OpenAI 兼容接口都可以。'
        : current.name + '：' + current.note;

    return _Section(
      title: 'AI 生成（模式 B：API 直连）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '填好之后在「加入」页可以直接生成卡片，不用再去网页聊天。'
            '请求由这台设备直接发给你选的提供商，不经任何中转。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Text('提供商', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kAiProviders
                .map(
                  (AiProvider provider) => ChoiceChip(
                    label: Text(provider.name),
                    selected: current?.id == provider.id,
                    onSelected: (_) => _pickProvider(provider),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 6),
          Text(providerNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(
            key: const Key('api-base-url'),
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: 'API 地址',
              hintText: 'https://api.deepseek.com/v1',
              helperText: '填到 /v1 即可，程序会自动补 /chat/completions',
              prefixIcon: Icon(Icons.link_outlined),
            ),
            onChanged: (String value) =>
                _save((AppSettings s) => s.copyWith(apiBaseUrl: value.trim())),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('api-model'),
            controller: _model,
            decoration: const InputDecoration(
              labelText: '模型名',
              hintText: 'deepseek-chat',
              prefixIcon: Icon(Icons.smart_toy_outlined),
            ),
            onChanged: (String value) =>
                _save((AppSettings s) => s.copyWith(apiModel: value.trim())),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('api-key'),
            controller: _key,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: '本地模型可以留空',
              helperText: '只存在这台设备的数据库里，不会上传',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _showKey ? '隐藏' : '显示',
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (String value) => _save(
              (AppSettings s) => value.trim().isEmpty
                  ? s.copyWith(clearApiKey: true)
                  : s.copyWith(apiKey: value.trim()),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: <Widget>[
              NumberField(
                fieldKey: const Key('api-timeout'),
                label: '超时（秒）',
                value: settings.apiTimeoutSeconds,
                min: AppSettings.minApiTimeoutSeconds,
                max: AppSettings.maxApiTimeoutSeconds,
                helper: '本地大模型可以调大',
                onCommit: (int value) => _save(
                  (AppSettings s) => s.copyWith(apiTimeoutSeconds: value),
                ),
              ),
              NumberField(
                fieldKey: const Key('api-cache-hours'),
                label: '缓存时长（小时）',
                value: settings.apiCacheHours,
                min: AppSettings.minApiCacheHours,
                max: AppSettings.maxApiCacheHours,
                width: 220,
                helper: '0 = 不缓存；相同 Prompt 在缓存期内不重复请求',
                onCommit: (int value) => _save(
                  (AppSettings s) => s.copyWith(apiCacheHours: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cable_outlined),
                label: Text(_testing ? '正在连接…' : '测试连接'),
              ),
              TextButton.icon(
                onPressed: _cacheCount == 0 ? null : _clearCache,
                icon: const Icon(Icons.delete_outline),
                label: Text('清空生成缓存（$_cacheCount 条）'),
              ),
            ],
          ),
          if (_testOk != null) ...<Widget>[
            const SizedBox(height: 12),
            _ApiNotice(
              icon: Icons.check_circle_outline,
              color: const Color(0xFF16A34A),
              title: _testOk!,
            ),
          ],
          if (_testFailure != null) ...<Widget>[
            const SizedBox(height: 12),
            _ApiNotice(
              icon: Icons.error_outline,
              color: theme.colorScheme.error,
              title: _testFailure!.message,
              detail: _testFailure!.hint,
            ),
          ],
          const SizedBox(height: 16),
          Text('用量（只统计这台设备，按每 100 万 token 约 1 美元估算）',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '调用 ' + settings.apiCallCount.toString() + ' 次 · 输入 ' +
                      settings.apiPromptTokens.toString() + ' · 输出 ' +
                      settings.apiCompletionTokens.toString() + ' tokens · 约 ' +
                      settings.estimatedCostUsd.toStringAsFixed(4) + ' 美元',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: settings.apiCallCount == 0 ? null : _resetUsage,
                child: const Text('重置用量'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一行提示（连接成功 / 失败）。
class _ApiNotice extends StatelessWidget {
  const _ApiNotice({
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              if (detail != null)
                Text(detail!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// 默认卡组名，方便别处引用。
String get kDefaultDeckLabel => Deck.defaultDeckName;

/// 「外部写入」这一块：AnkiConnect 兼容的服务。
///
/// 它和上面的「AI 生成」是反方向：AI 生成是本应用去调别人，
/// 这里是被别人调 —— Yomitan、脚本、AI agent 把词直接写进来。
class _AnkiConnectSection extends ConsumerStatefulWidget {
  const _AnkiConnectSection();

  @override
  ConsumerState<_AnkiConnectSection> createState() =>
      _AnkiConnectSectionState();
}

class _AnkiConnectSectionState extends ConsumerState<_AnkiConnectSection> {
  late final TextEditingController _key;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(
      text: ref.read(currentSettingsProvider).apiServerKey ?? '',
    );
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings Function(AppSettings current) change) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    await ref.read(settingsRepositoryProvider).save(change(settings));
  }

  Future<void> _saveKey(String value) async {
    final String text = value.trim();
    await _save(
      (AppSettings s) => text.isEmpty
          ? s.copyWith(clearApiServerKey: true)
          : s.copyWith(apiServerKey: text),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 ' + text)));
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ServerRuntime status = ref.watch(ankiConnectServerProvider);
    final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final ThemeData theme = Theme.of(context);
    final String url = 'http://127.0.0.1:$kApiServerPort/';
    final bool keyEmpty = (settings.apiServerKey ?? '').isEmpty;
    // 锁定的卡组可能已经被删掉：这时下拉框要退回「跟随客户端」，
    // 否则 DropdownButton 会因为当前值不在候选项里直接抛断言。
    final String selectedDeckId = decks.any(
      (Deck deck) => deck.id == settings.apiServerDeckId,
    )
        ? settings.apiServerDeckId!
        : '';

    return _Section(
      title: '外部写入（AnkiConnect 兼容）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '开了之后，这个应用就像一个 Anki 的 AnkiConnect 插件：'
            '浏览器划词工具（Yomitan）、脚本、AI agent 都能把词直接写进来。'
            '写进来的词和手动加的一样进当前卡组、参与测验，也会跟着设备同步。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '只写词，不改你已有的卡片；不提供「浏览 / 编辑 / 媒体 / 挂起」'
            '这些动作 —— 那些按钮客户端会自动藏起来。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            key: const Key('api-server-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('启用'),
            subtitle: Text(status.describe()),
            value: settings.apiServerEnabled,
            onChanged: (bool value) =>
                _save((AppSettings s) => s.copyWith(apiServerEnabled: value)),
          ),
          if (settings.apiServerEnabled) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  '端口固定 $kApiServerPort',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _copy(url),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(url),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '客户端里就填这个地址（Yomitan：设置 → Anki → 自定义 AnkiConnect URL）。'
              '端口固定是 $kApiServerPort：8765 留给 Anki 官方插件，两边同时装不会抢端口。',
              style: theme.textTheme.bodySmall,
            ),
            SwitchListTile(
              key: const Key('api-server-lan'),
              contentPadding: EdgeInsets.zero,
              title: const Text('允许局域网访问'),
              subtitle: const Text('关着只听 127.0.0.1；手机上没有浏览器插件，要用就开它'),
              value: settings.apiServerAllowLan,
              onChanged: (bool value) => _save(
                (AppSettings s) => s.copyWith(apiServerAllowLan: value),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('api-server-key'),
              controller: _key,
              decoration: InputDecoration(
                labelText: '访问口令（可留空）',
                helperText: settings.apiServerAllowLan && keyEmpty
                    ? '开着局域网又没设口令：同网段任何人都能往你的词库里写词'
                    : '填了之后客户端要带上同一个 key 才写得进来',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
              ),
              onChanged: _saveKey,
            ),
            const SizedBox(height: 12),
            Text('写进哪个卡组', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              '默认跟随客户端：客户端说进哪个卡组就进哪个，没说就进当前卡组。'
              '锁死之后外部写入一律进这一个卡组，不管客户端怎么填 —— '
              '不想让插件把词分散到十几个卡组里时用。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // 换 key 是为了让下拉框跟着新值重建：FormField 的 initialValue
              // 只在第一次建 State 时生效，改完设置不重建的话显示会停在旧值。
              key: Key('api-server-deck-' + selectedDeckId),
              initialValue: selectedDeckId,
              decoration: const InputDecoration(
                labelText: '目标卡组',
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('跟随客户端（默认）'),
                ),
                for (final Deck deck in decks)
                  DropdownMenuItem<String>(
                    value: deck.id,
                    child: Text(deck.name),
                  ),
              ],
              onChanged: (String? value) => _save(
                (AppSettings s) => (value == null || value.isEmpty)
                    ? s.copyWith(clearApiServerDeckId: true)
                    : s.copyWith(apiServerDeckId: value),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('api-server-autocomplete'),
              contentPadding: EdgeInsets.zero,
              title: const Text('顺手用 AI 补全干扰项'),
              subtitle: const Text(
                '外部写入常常只给「词 + 释义」，补不足 4 个干扰项就没法出五选一。'
                '关着时先从同卡组借，借不够挂「待补全」标签；开着时再加一次 AI 补全',
              ),
              value: settings.apiServerAutoComplete,
              onChanged: (bool value) => _save(
                (AppSettings s) => s.copyWith(apiServerAutoComplete: value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
