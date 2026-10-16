// 这里用 + 拼字符串是刻意的（拼路径、拼提示文案），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/export/answer_sheet_service.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../state/projection_controller.dart';
import '../../state/providers.dart';
import '../fonts.dart';
import '../platform_target.dart';
import '../presentation/presentation_launcher.dart';
import '../presentation/presentation_window.dart';
import '../theme.dart';
import '../widgets/number_field.dart';
import '../widgets/section_card.dart';
import 'presentation_page.dart';

/// 「演示」页：课堂投影的参数设置。
///
/// 演示不是背诵，是**把题放大到全屏给学生答**：和测验一样一个单词五个选项，
/// 只是屏幕上点不了，节奏由每题的停留限时控制；全程不显示答案，
/// 答案在结束后写进一份 txt。
///
/// 这一页只有桌面端会显示（手机端连入口都没有，见 home_shell.dart 的
/// visibleHomeTabs），所以页面里不再为手机留分支。
class ProjectionPage extends ConsumerStatefulWidget {
  const ProjectionPage({super.key, required this.onGoToAdd});

  final VoidCallback onGoToAdd;

  @override
  ConsumerState<ProjectionPage> createState() => _ProjectionPageState();
}

class _ProjectionPageState extends ConsumerState<ProjectionPage> {
  final TextEditingController _answerDir = TextEditingController();
  final FocusNode _answerDirFocus = FocusNode();

  /// 独立演示窗口的管理器（桌面端）。
  final PresentationWindowLauncher _window = PresentationWindowLauncher();
  StreamSubscription<void>? _windowsSub;

  /// 演示窗口现在开着吗。
  bool _windowOpen = false;
  String? _windowError;

  @override
  void initState() {
    super.initState();
    // 用户直接点演示窗口的关闭按钮时，onWindowsChanged 会响，
    // 我们借此把演示停下来（照样会写答案 txt）。
    if (supportsPresentationWindow()) {
      _windowsSub =
          presentationWindowChanges().listen((_) => unawaited(_checkWindow()));
    }
  }

  @override
  void dispose() {
    _windowsSub?.cancel();
    _answerDir.dispose();
    _answerDirFocus.dispose();
    super.dispose();
  }

  Future<void> _checkWindow() async {
    if (!_windowOpen) return;
    if (await _window.isStillOpen()) return;
    _windowOpen = false;
    if (mounted) setState(() {});
    ref.read(projectionControllerProvider.notifier).stop();
  }

  /// 演示窗口里的按键回传到这里，动作还是主窗口执行。
  void _handleControl(String action) {
    final ProjectionController controller =
        ref.read(projectionControllerProvider.notifier);
    switch (action) {
      case kControlPrevious:
        controller.previous();
      case kControlNext:
        controller.next();
      case kControlPause:
        controller.togglePause();
      case kControlExit:
        unawaited(_stopPresentation());
    }
  }

  /// 结束演示：停控制器（会写答案 txt）并关掉演示窗口。
  Future<void> _stopPresentation() async {
    ref.read(projectionControllerProvider.notifier).stop();
    _windowOpen = false;
    await _window.close();
    if (mounted) setState(() {});
  }

  /// 把当前一帧推给演示窗口。
  void _pushFrame() {
    if (!_windowOpen) return;
    final ProjectionState state = ref.read(projectionControllerProvider);
    final AppSettings settings = ref.read(currentSettingsProvider);
    unawaited(_window.push(projectionFrameOf(state, settings).frame));
  }

  Future<void> _save(AppSettings next) =>
      ref.read(settingsRepositoryProvider).save(next);

  String _deckNameNow() {
    final String? deckId = ref.read(selectedDeckProvider);
    if (deckId == null) return '全部词库';
    final List<Deck> decks = ref.read(decksProvider).value ?? const <Deck>[];
    for (final Deck deck in decks) {
      if (deck.id == deckId) return deck.name;
    }
    return Deck.defaultDeckName;
  }

  Future<void> _pickAudio(AppSettings settings) async {
    const XTypeGroup group = XTypeGroup(
      label: '音频文件',
      extensions: <String>['wav', 'mp3', 'm4a', 'aac', 'ogg'],
      mimeTypes: <String>['audio/*'],
    );
    try {
      final XFile? file =
          await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;
      await _save(settings.copyWith(
        projectionSoundSource: PageTurnSoundSource.custom,
        projectionSoundPath: file.path,
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择音频文件失败：$error')),
      );
    }
  }

  Future<void> _pickAnswerDir(AppSettings settings) async {
    try {
      final String? path = await getDirectoryPath();
      if (path == null) return;
      _answerDir.text = path;
      await _save(settings.copyWith(projectionAnswerDir: path));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('这个平台不支持弹出选目录，直接手填路径即可：$error')),
      );
    }
  }

  void _commitAnswerDir(AppSettings settings) {
    final String value = _answerDir.text.trim();
    if (value == (settings.projectionAnswerDir ?? '')) return;
    _save(settings.copyWith(
      projectionAnswerDir: value.isEmpty ? null : value,
      clearProjectionAnswerDir: value.isEmpty,
    ));
  }

  Future<void> _start() async {
    final List<WordCard> cards = await ref
        .read(cardRepositoryProvider)
        .getAll(deckId: ref.read(selectedDeckProvider));
    if (!mounted) return;
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可演示的卡片，先去「加入」页加几张。')),
      );
      return;
    }
    final AppSettings settings = ref.read(currentSettingsProvider);
    final String deckName = _deckNameNow();
    ref.read(projectionControllerProvider.notifier).start(
          cards,
          intervalSeconds: settings.projectionIntervalSeconds,
          deckName: deckName,
          shuffle: settings.projectionShuffle,
          loop: settings.projectionLoop,
          reshuffleEachRound: settings.projectionReshuffleEachRound,
          announcePageTurns: settings.projectionBeepEnabled,
        );

    // 另开一个最大化的演示窗口；开不出来（插件不可用，比如在测试里）
    // 就退回应用内全屏页，功能不打折。
    if (supportsPresentationWindow()) {
      final ProjectionFrameData data = projectionFrameOf(
        ref.read(projectionControllerProvider),
        settings,
      );
      final bool opened = await _window.open(
        frame: data.frame,
        themeMode: settings.projectionThemeMode,
        onControl: _handleControl,
      );
      if (!mounted) return;

      if (opened) {
        setState(() {
          _windowOpen = true;
          _windowError = null;
        });
        return;
      }
      _windowError = _window.lastError;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PresentationPage()),
    );
    // 从演示页回来才停：放在这里而不是 dispose 里，
    // 因为 Riverpod 不允许在 widget 生命周期里改 provider。
    if (!mounted) return;
    ref.read(projectionControllerProvider.notifier).stop();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final int total = ref.watch(allCardsProvider).value?.length ?? 0;

    // 演示窗口开着的时候，控制器每跳一次就把新的一帧推过去；
    // 控制器一旦结束（放完 / 中途停），顺手把窗口也关掉。
    ref.listen<ProjectionState>(
      projectionControllerProvider,
      (ProjectionState? previous, ProjectionState next) {
        if (!_windowOpen) return;
        if (next.status == ProjectionStatus.running) {
          _pushFrame();
        } else {
          unawaited(_stopPresentation());
        }
      },
    );
    final AnswerSheetStatus answerStatus = ref.watch(lastAnswerSheetProvider);
    final ThemeData theme = Theme.of(context);

    final String? soundPath = settings.projectionSoundPath;
    final bool customSoundMissing =
        settings.projectionSoundSource == PageTurnSoundSource.custom &&
            (soundPath == null ||
                soundPath.isEmpty ||
                !File(soundPath).existsSync());

    final String answerDirText = settings.projectionAnswerDir ?? '';
    if (!_answerDirFocus.hasFocus && _answerDir.text != answerDirText) {
      _answerDir.text = answerDirText;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        SectionCard(
          title: '课堂演示（投影）',
          subtitle: '把题放大到全屏给学生答：一个单词五个选项，屏幕上点不了，'
              '每题停留固定秒数，到点自动换下一题；全程不显示答案。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InfoLine(
                label: '可演示卡片',
                value: total.toString() + ' 张',
                icon: Icons.style_outlined,
              ),
              InfoLine(
                label: '每题停留',
                value: settings.projectionIntervalSeconds.toString() + ' 秒',
                icon: Icons.timer_outlined,
              ),
              const SizedBox(height: 12),
              NumberField(
                fieldKey: const Key('projection-interval-field'),
                label: '每题停留（秒）',
                helper: '1 - 600 秒',
                suffix: '秒',
                value: settings.projectionIntervalSeconds,
                min: AppSettings.minTimeLimitSeconds,
                max: AppSettings.maxTimeLimitSeconds,
                onCommit: (int seconds) => _save(
                  settings.copyWith(projectionIntervalSeconds: seconds),
                ),
              ),
              const SizedBox(height: 16),
              Text('选项编号', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<OptionLabelStyle>(
                segments: <ButtonSegment<OptionLabelStyle>>[
                  ButtonSegment<OptionLabelStyle>(
                    value: OptionLabelStyle.number,
                    label: Text(OptionLabelStyle.number.label),
                  ),
                  ButtonSegment<OptionLabelStyle>(
                    value: OptionLabelStyle.letter,
                    label: Text(OptionLabelStyle.letter.label),
                  ),
                ],
                selected: <OptionLabelStyle>{
                  settings.projectionOptionLabelStyle,
                },
                onSelectionChanged: (Set<OptionLabelStyle> value) => _save(
                  settings.copyWith(projectionOptionLabelStyle: value.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '学生按编号喊答案时用哪个都行；编号只是显示，不影响出题。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SectionCard(
          title: '演示外观',
          subtitle: '演示模式单独一套深浅色：教室灯亮选浅色，投影偏暗或要压低亮度选深色。'
              '主界面该是什么样还是什么样。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
                onSelectionChanged: (Set<AppThemeMode> value) => _save(
                  settings.copyWith(projectionThemeMode: value.first),
                ),
              ),
              const SizedBox(height: 12),
              _ProjectionPreview(mode: settings.projectionThemeMode),
            ],
          ),
        ),

        SectionCard(
          title: '播放方式',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('随机顺序'),
                subtitle: const Text('每轮开始时打乱出题顺序'),
                value: settings.projectionShuffle,
                onChanged: (bool value) =>
                    _save(settings.copyWith(projectionShuffle: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('循环播放'),
                subtitle: const Text('关掉的话，放完最后一题就结束'),
                value: settings.projectionLoop,
                onChanged: (bool value) =>
                    _save(settings.copyWith(projectionLoop: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每轮重新打乱选项'),
                subtitle: const Text('循环到下一轮时，五个选项的顺序重新排一次，避免学生记位置'),
                value: settings.projectionReshuffleEachRound,
                onChanged: (bool value) => _save(
                  settings.copyWith(projectionReshuffleEachRound: value),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: '翻页提示音',
          subtitle: '每次翻页（自动或手动）都会响一次，用来提示换题了。',
          trailing: TextButton.icon(
            onPressed: () => ref.read(pageTurnSoundProvider).playPageTurn(),
            icon: const Icon(Icons.volume_up_outlined, size: 18),
            label: const Text('试听'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开启提示音'),
                value: settings.projectionBeepEnabled,
                onChanged: (bool value) =>
                    _save(settings.copyWith(projectionBeepEnabled: value)),
              ),
              const SizedBox(height: 4),
              SegmentedButton<PageTurnSoundSource>(
                segments: <ButtonSegment<PageTurnSoundSource>>[
                  ButtonSegment<PageTurnSoundSource>(
                    value: PageTurnSoundSource.builtin,
                    label: Text(PageTurnSoundSource.builtin.label),
                    icon: const Icon(Icons.graphic_eq, size: 18),
                  ),
                  ButtonSegment<PageTurnSoundSource>(
                    value: PageTurnSoundSource.custom,
                    label: Text(PageTurnSoundSource.custom.label),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                  ),
                ],
                selected: <PageTurnSoundSource>{settings.projectionSoundSource},
                onSelectionChanged: (Set<PageTurnSoundSource> value) =>
                    _save(settings.copyWith(projectionSoundSource: value.first)),
              ),
              const SizedBox(height: 14),
              if (settings.projectionSoundSource == PageTurnSoundSource.builtin)
                Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: <Widget>[
                    NumberField(
                      label: '频率',
                      helper: '100 - 15000 Hz',
                      suffix: 'Hz',
                      value: settings.projectionBeepHz,
                      min: AppSettings.minBeepHz,
                      max: AppSettings.maxBeepHz,
                      onCommit: (int hz) =>
                          _save(settings.copyWith(projectionBeepHz: hz)),
                    ),
                    NumberField(
                      label: '时长',
                      helper: '20 - 3000 毫秒',
                      suffix: '毫秒',
                      value: settings.projectionBeepMs,
                      min: AppSettings.minBeepMs,
                      max: AppSettings.maxBeepMs,
                      onCommit: (int ms) =>
                          _save(settings.copyWith(projectionBeepMs: ms)),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('自选音频文件', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    SelectableText(
                      soundPath == null || soundPath.isEmpty
                          ? '还没有选择文件'
                          : soundPath,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (customSoundMissing) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '这个文件现在读不到（被删了或被清理了），演示时会自动退回内置提示音。',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _pickAudio(settings),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('选择音频文件…'),
                        ),
                        if (soundPath != null)
                          TextButton.icon(
                            onPressed: () => _save(settings.copyWith(
                              clearProjectionSoundPath: true,
                            )),
                            icon: const Icon(Icons.clear, size: 18),
                            label: const Text('清除'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '支持 wav / mp3 / m4a / aac / ogg。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ),
        SectionCard(
          title: '演示答案文件',
          subtitle: '演示结束时（或者中途退出时）把这一轮出过的题和答案写成一份 txt，'
              '文件名带时间和卡组名。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('输出模式', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<AnswerSheetMode>(
                segments: <ButtonSegment<AnswerSheetMode>>[
                  for (final AnswerSheetMode mode in AnswerSheetMode.values)
                    ButtonSegment<AnswerSheetMode>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                ],
                selected: <AnswerSheetMode>{settings.projectionAnswerMode},
                onSelectionChanged: (Set<AnswerSheetMode> value) => _save(
                  settings.copyWith(projectionAnswerMode: value.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                settings.projectionAnswerMode.description,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('输出目录', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 460,
                    child: TextField(
                      key: const Key('answer-dir-field'),
                      controller: _answerDir,
                      focusNode: _answerDirFocus,
                      decoration: const InputDecoration(
                        hintText: '留空就用默认目录',
                        isDense: true,
                        prefixIcon: Icon(Icons.folder_outlined, size: 18),
                      ),
                      onSubmitted: (_) => _commitAnswerDir(settings),
                      onEditingComplete: () => _commitAnswerDir(settings),
                      onTapOutside: (_) => _commitAnswerDir(settings),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickAnswerDir(settings),
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                    label: const Text('选择目录…'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _answerDir.text = '';
                      _save(settings.copyWith(clearProjectionAnswerDir: true));
                    },
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('用默认目录'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '默认目录：系统文档目录下的 '
                + AnswerSheetService.defaultFolderName
                + '（Windows 上就是「文档」文件夹里）。',
                style: theme.textTheme.bodySmall,
              ),
              if (answerStatus.error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '上次写答案文件失败：' + answerStatus.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (answerStatus.sheet != null) ...<Widget>[
                const SizedBox(height: 14),
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
                        '上次写出的答案：' +
                            answerStatus.sheet!.questions.toString() +
                            ' 题',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        answerStatus.sheet!.path,
                        style: theme.textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: answerStatus.sheet!.path),
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
          title: '开始',
          child: Column(
            children: <Widget>[
              if (_windowOpen) ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.cast_connected_outlined,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '演示已在另一个窗口播放',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '那个窗口是独立窗口，已经强制最大化、且不能缩回小窗；'
                        '按键（空格 / 左右方向键 / Esc）在主窗口这边处理。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_stopPresentation()),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止演示'),
                  ),
                ),
              ] else ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: total == 0 ? null : _start,
                    icon: const Icon(Icons.slideshow_outlined),
                    label: const Text('开始演示'),
                  ),
                ),
                if (_windowError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '没能打开独立演示窗口（' +
                        _windowError! +
                        '），已经退回应用内全屏演示。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '按下开始后会另开一个最大化的演示窗口：空格暂停/继续，'
                  '左右方向键上一题/下一题，Esc 退出。屏幕上不能点选，'
                  '学生口头作答；全程不显示答案。窗口开不出来时会退回'
                  '应用内全屏演示页。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (total == 0) ...<Widget>[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: widget.onGoToAdd,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('去加入卡片'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 预览一小段演示画面，让用户当场看到深浅色和字体的效果。
class _ProjectionPreview extends StatelessWidget {
  const _ProjectionPreview({required this.mode});

  final AppThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final ThemeData projection = buildProjectionTheme(brightness);
    final Color ink = projection.colorScheme.onSurface;
    final Color faint = ink.withValues(alpha: 0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        color: projection.scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('预览 · 第 2/8 题', style: projectionStyle(context, size: 13, weight: FontWeight.w600, color: faint)),
                const Spacer(),
                Text('3', style: projectionStyle(context, size: 20, weight: FontWeight.w700, color: ink)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '游泳',
              style: projectionStyle(
                context,
                size: ProjectionText.wordSmall,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '日语【すいえい】 · 韩语 수영 · 俄语 плавание',
              style: projectionStyle(context, size: 14, weight: FontWeight.w400, color: faint),
            ),
            const SizedBox(height: 14),
            for (final String option in <String>['A. 游泳', 'B. 跑步', 'C. 骑车'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  option,
                  style: projectionStyle(context, size: ProjectionText.optionSmall, color: ink),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '深色 / 浅色只影响演示全屏画面，主界面不受影响。',
              style: projectionStyle(context, size: 12, weight: FontWeight.w400, color: faint),
            ),
          ],
        ),
      ),
    );
  }
}
