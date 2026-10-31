import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_url.dart';
import '../../domain/models/app_settings.dart';
import '../../state/providers.dart';
import '../../state/server_providers.dart';

/// 设备同步的控制台。
///
/// 只有「我连别人」这一个动作：对方的监听可能没开（手机上更常见），
/// 但本机发起时总能连上对方的同步端口。两台设备各自点一次，
/// 数据就两边都有了 —— 合并是双向的，不需要「主设备」。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  late Future<List<String>> _addresses;

  @override
  void initState() {
    super.initState();
    _pin.text = ref.read(currentSettingsProvider).syncPin ?? '';
    _addresses = lanAddresses();
  }

  @override
  void dispose() {
    _address.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _savePin(String value) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    final String text = value.trim();
    await ref.read(settingsRepositoryProvider).save(
          text.isEmpty
              ? settings.copyWith(clearSyncPin: true)
              : settings.copyWith(syncPin: text),
        );
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    await ref.read(syncRunnerProvider.notifier).run(
          _address.text,
          pin: _pin.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ServerRuntime server = ref.watch(syncServerProvider);
    final SyncRunState run = ref.watch(syncRunnerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设备同步')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _card(
                theme,
                '这台设备',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '设备名：${deviceDisplayName(settings)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(server.describe(), style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    FutureBuilder<List<String>>(
                      future: _addresses,
                      builder: (
                        BuildContext context,
                        AsyncSnapshot<List<String>> snapshot,
                      ) {
                        final List<String> list =
                            snapshot.data ?? const <String>[];
                        if (list.isEmpty) {
                          return Text(
                            '没找到局域网地址：先连上 Wi-Fi（手机）或插上网线。',
                            style: theme.textTheme.bodySmall,
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '对方要在「对方的地址」里填其中一条：',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            for (final String ip in list)
                              SelectableText(
                                '$ip:${settings.syncPort}',
                                style: theme.textTheme.titleMedium,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '能不能同步和「我有没有监听」无关：我先连对方，'
                      '数据在对方那里合完之后再传回来。所以只开一台的监听也能同步。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _card(
                theme,
                '连到另一台设备',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: '对方的地址',
                        hintText: '例如 192.168.1.5:8766',
                        prefixIcon: Icon(Icons.lan_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      decoration: const InputDecoration(
                        labelText: '同步口令（两台填一样的）',
                        hintText: '两边都留空就是不校验；回车保存',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                      // 每敲一个字就存会把监听服务反复重启（口令在监听配置里），
                      // 所以和设置页一样只在提交时写。
                      onSubmitted: _savePin,
                      onTapOutside: (_) => _savePin(_pin.text),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: run.busy ? null : _run,
                          icon: const Icon(Icons.sync),
                          label: const Text('开始同步'),
                        ),
                        const SizedBox(width: 12),
                        if (run.busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    if (run.stage != SyncStage.idle) ...<Widget>[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          run.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: run.stage == SyncStage.failed
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _card(
                theme,
                '同步做了什么',
                Text(
                  '把两边的卡片、卡组、答题记录按「谁最后改的谁说了算」合一份：'
                  '内容看修改时间，进度看最后一次复习。删除也会同步过去'
                  '（所以在这台删掉的词，不会同步完又从对面回来）。\n\n'
                  '同步是整库交换，不是增量：现在整库只有几 MB，'
                  '一次传完最省事，也不会有「日志丢了导致对不上」的问题。\n\n'
                  '注意：两台设备要在同一个局域网里。Windows 第一次监听时'
                  '会弹防火墙提示，要选「允许」。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium
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
