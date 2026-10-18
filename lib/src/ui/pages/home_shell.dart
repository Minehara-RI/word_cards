import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_settings.dart';
import '../../state/providers.dart';
import '../platform_target.dart';
import 'add_page.dart';
import 'export_page.dart';
import 'projection_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'study_page.dart';

/// 主界面上要显示哪几个页面入口。
///
/// 两端都是五个（加入 / 作答 / 演示 / 统计 / 导出）。桌面端的「演示」
/// 另开一个独立窗口，手机端是应用内全屏 —— 讲台上把手机横过来、
/// 或者手机接投影线，都是真实用法，所以入口不再按平台砍掉。
List<String> visibleHomeTabs(PlatformTarget target) => AppSettings.homeTabs;

/// 主界面：上面一排页面入口，下面是当前页。
///
/// 桌面端的入口顺序和 Anki 的习惯一致：加入 -> 作答 -> 演示 -> 统计 -> 导出。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.target});

  /// 用哪个平台的样子画。平时不传（按 detectPlatformTarget() 判断），
  /// 测试里传 PlatformTarget.mobile 就能装作自己跑在手机上。
  final PlatformTarget? target;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.hint);

  final IconData icon;
  final String label;
  final String hint;
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// 每个主页面长什么样，按页面 id 查。
  static const Map<String, _NavItem> _navItems = <String, _NavItem>{
    AppSettings.addHomeTab:
        _NavItem(Icons.add_circle_outline, '加入', '手动加词或粘贴导入'),
    AppSettings.studyHomeTab:
        _NavItem(Icons.play_circle_outline, '作答', '限时选择题'),
    AppSettings.demoHomeTab:
        _NavItem(Icons.slideshow_outlined, '演示', '课堂投影，自动翻页'),
    AppSettings.statsHomeTab:
        _NavItem(Icons.insights_outlined, '统计', '正确率与掌握度'),
    AppSettings.exportHomeTab:
        _NavItem(Icons.ios_share_outlined, '导出', 'JSON / CSV / Anki 库'),
  };

  // 默认停在「作答」，没卡片时作答页会把人引到「加入」。
  // 真实值在第一次读到设置时恢复（记住上次停在哪一页）。
  //
  // 记的是页面 id 而不是下标：手机端少一个入口，下标会整体错位，
  // 而设置里存的本来就是 id。
  String _tab = AppSettings.defaultHomeTab;
  bool _restored = false;

  /// 已经打开过的页面才真正构建，避免一进应用就同时加载所有页面。
  final Set<String> _visited = <String>{AppSettings.defaultHomeTab};

  void _select(String id, AppSettings settings) {
    if (id != _tab) {
      setState(() {
        _tab = id;
        _visited.add(id);
      });
    }
    // 记住这一页：下次打开应用还停在这里。
    ref.read(settingsRepositoryProvider).save(
          settings.copyWith(homeTab: id),
        );
  }

  Widget _sectionAt(String id, AppSettings settings, PlatformTarget target) {
    switch (id) {
      case AppSettings.addHomeTab:
        return const AddPage();
      case AppSettings.studyHomeTab:
        return StudyPage(
          onGoToAdd: () => _select(AppSettings.addHomeTab, settings),
        );
      case AppSettings.demoHomeTab:
        return ProjectionPage(
          target: target,
          onGoToAdd: () => _select(AppSettings.addHomeTab, settings),
        );
      case AppSettings.statsHomeTab:
        return const StatsPage();
      default:
        return const ExportPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlatformTarget target = widget.target ?? detectPlatformTarget();
    final AsyncValue<AppSettings> settingsAsync =
        ref.watch(settingsProvider);
    final AppSettings settings = settingsAsync.value ?? const AppSettings();
    final List<String> tabs = visibleHomeTabs(target);

    // 设置是异步读出来的，读到之后把上次那一页恢复回来（只做一次）。
    // 上次那一页在本平台不存在时（手机上记着「演示」）退回默认页。
    if (!_restored && settingsAsync.hasValue) {
      _restored = true;
      final String restored = tabs.contains(settings.homeTab)
          ? settings.homeTab
          : AppSettings.defaultHomeTab;
      if (restored != _tab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _tab = restored;
            _visited.add(restored);
          });
        });
      }
    }
    final double maxWidth = target.isDesktop ? 1040.0 : 620.0;
    final int currentTab = tabs.indexOf(_tab);
    final int selected = currentTab < 0 ? 0 : currentTab;

    return Scaffold(
      appBar: AppBar(
        title: const Text('word_flashcards'),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          _TopNav(
            items: <_NavItem>[
              for (final String id in tabs) _navItems[id]!,
            ],
            index: selected,
            onSelect: (int index) => _select(tabs[index], settings),
            maxWidth: maxWidth,
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: IndexedStack(
                  index: selected,
                  children: <Widget>[
                    for (final String id in tabs)
                      _visited.contains(id)
                          ? _sectionAt(id, settings, target)
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.items,
    required this.index,
    required this.onSelect,
    required this.maxWidth,
  });

  final List<_NavItem> items;
  final int index;
  final void Function(int) onSelect;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) => _NavButton(
              item: items[i],
              selected: i == index,
              onTap: () => onSelect(i),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: item.hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
