import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_ports.dart';
import '../../data/sync/sync_url.dart';
import '../../domain/models/app_settings.dart';
import '../../state/providers.dart';
import '../../state/server_providers.dart';
import 'section_card.dart';

/// 「导出与同步」页里的设备同步面板。
///
/// 为什么放在导出页而不是设置页：同步是「我这边的数据要拿到那边去」，
/// 和导出是同一种心事（把数据从这台设备搬走），放在一起顺手；
/// 设置页留给那些「改一次就不再动」的偏好。
class SyncPanel extends ConsumerStatefulWidget {
  const SyncPanel({super.key});

  @override
  ConsumerState<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends ConsumerState<SyncPanel> {
  late final TextEditingController _name;
  late final TextEditingController _pin;
  final TextEditingController _peer = TextEditingController();
  late Future<List<String>> _addresses;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = ref.read(currentSettingsProvider);
    _name = TextEditingController(text: settings.syncDeviceName ?? '');
    _pin = TextEditingController(text: settings.syncPin ?? '');
    _addresses = lanAddresses();
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _peer.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings Function(AppSettings current) change) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    await ref.read(settingsRepositoryProvider).save(change(settings));
  }

  void _commitName() {
    final String text = _name.text.trim();
    _save((AppSettings s) => s.copyWith(syncDeviceName: text));
  }

  void _commitPin() {
    final String text = _pin.text.trim();
    _save(
      (AppSettings s) =>
          text.isEmpty ? s.copyWith(clearSyncPin: true) : s.copyWith(syncPin: text),
    );
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    await ref.read(syncRunnerProvider.notifier).run(
          _peer.text,
          pin: _pin.text.trim(),
        );
  }

  String _lastSyncLabel(AppSettings settings) {
    final int? at = settings.syncLastAt;
    if (at == null) return '还没同步过';
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(at);
    String two(int value) => value.toString().padLeft(2, '0');
    final String date = '${time.year}-${two(time.month)}-${two(time.day)}';
    final String clock = '${two(time.hour)}:${two(time.minute)}';
    return '上次同步：$date $clock';
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ServerRuntime server = ref.watch(syncServerProvider);
    final SyncRunState run = ref.watch(syncRunnerProvider);
    final ThemeData theme = Theme.of(context);
    final bool pinEmpty = (settings.syncPin ?? '').isEmpty;

    return SectionCard(
      title: '设备同步',
      subtitle: '手机 ↔ 电脑、手机 ↔ 手机、电脑 ↔ 电脑：把两边的卡片、卡组、'
          '答题记录整库合一份，再各自写回去。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            key: const Key('sync-server-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('在这台设备上监听'),
            subtitle: Text(server.describe()),
            value: settings.syncEnabled,
            onChanged: (bool value) =>
                _save((AppSettings s) => s.copyWith(syncEnabled: value)),
          ),
          if (settings.syncEnabled) ...<Widget>[
            const SizedBox(height: 4),
            Text('端口固定 $kSyncPort', style: theme.textTheme.labelLarge),
            const SizedBox(height: 10),
            TextField(
              key: const Key('sync-device-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: '设备名',
                helperText: '对方界面上显示的名字，回车保存',
                prefixIcon: Icon(Icons.computer_outlined),
                isDense: true,
              ),
              onSubmitted: (_) => _commitName(),
              onTapOutside: (_) => _commitName(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sync-pin'),
              controller: _pin,
              decoration: InputDecoration(
                labelText: '同步口令（两台填一样的，可留空）',
                helperText: pinEmpty
                    ? '留空 = 同一个局域网里谁都能连上来同步你的词库'
                    : '对方要填同一个口令才连得上；回车保存',
                prefixIcon: const Icon(Icons.password_outlined),
                isDense: true,
              ),
              onSubmitted: (_) => _commitPin(),
              onTapOutside: (_) => _commitPin(),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
              future: _addresses,
              builder: (
                BuildContext context,
                AsyncSnapshot<List<String>> snapshot,
              ) {
                final List<String> list = snapshot.data ?? const <String>[];
                if (list.isEmpty) {
                  return Text(
                    '没找到局域网地址：这台设备现在没连 Wi-Fi / 网线。',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('对方要填的地址（任选其一）：',
                        style: theme.textTheme.bodySmall),
                    for (final String ip in list)
                      SelectableText(
                        '$ip:$kSyncPort',
                        style: theme.textTheme.titleMedium,
                      ),
                  ],
                );
              },
            ),
          ],
          const Divider(height: 28),
          Text('连到另一台设备', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            key: const Key('sync-peer'),
            controller: _peer,
            decoration: InputDecoration(
              labelText: '对方的地址',
              hintText: '例如 192.168.1.5（端口固定 $kSyncPort）',
              prefixIcon: const Icon(Icons.lan_outlined),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _run(),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.icon(
                key: const Key('sync-run'),
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
              const Spacer(),
              Text(_lastSyncLabel(settings), style: theme.textTheme.bodySmall),
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
          const SizedBox(height: 10),
          Text(
            '只开一台的监听也能同步：发起方先把数据推上去，对方合并完再传回来，'
            '一次往返两端就一样。两台设备要在同一个局域网里；'
            'Windows 第一次监听会弹防火墙提示，要允许。'
            '应用切到后台被系统冻结后端口就不再响应。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
