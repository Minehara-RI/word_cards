import 'package:flutter/material.dart';

import '../help/help_content.dart';
import '../platform_target.dart';

/// 页面最底部的「说明」按钮。
///
/// **只在手机端出现**：电脑上有完整的 docs/，窗口里再放一份说明只是占地方，
/// 所以这里按平台决定画不画。测试可以传 [target] 假装自己在手机上。
class HelpButton extends StatelessWidget {
  const HelpButton({
    super.key,
    required this.topic,
    this.target,
    this.compact = false,
  });

  /// 说明的 key（与 help_content.dart 里的词条对应）。
  final String topic;

  /// 用哪个平台的样子画；不传就按当前平台判断。
  final PlatformTarget? target;

  /// 紧凑模式：贴在某个设置小节里，不加页面底部那段留白。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!(target ?? detectPlatformTarget()).isMobile) {
      return const SizedBox.shrink();
    }
    final Widget button = TextButton.icon(
      key: Key('help-button-$topic'),
      onPressed: () => showHelpDialog(context, topic),
      icon: const Icon(Icons.help_outline, size: 18),
      label: const Text('说明'),
    );
    if (compact) {
      return Align(alignment: Alignment.centerLeft, child: button);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Center(child: button),
    );
  }
}

/// 弹出某个页面的说明。没有对应词条时什么都不做（不弹空框）。
Future<void> showHelpDialog(BuildContext context, String topic) async {
  final HelpTopic? help = helpTopicFor(topic);
  if (help == null) return;
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => HelpDialog(help: help),
  );
}

/// 说明弹窗：标题 + 小节，可滚动。
///
/// 刻意不渲染 Markdown：说明是应用里的短文案，不是网页；
/// 上一个小型 Markdown 渲染器只会给「离线可用」添一个依赖。
class HelpDialog extends StatelessWidget {
  const HelpDialog({super.key, required this.help});

  final HelpTopic help;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(help.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HelpSection section in help.sections) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Text(
                    section.heading,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  section.body,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
