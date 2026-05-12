import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/voice/voice_providers.dart';
import '../../assistant/application/assistant_controller.dart';
import '../../assistant/application/assistant_state.dart';
import '../../assistant/presentation/assistant_drawer.dart';
import '../../assistant/presentation/widgets/assistant_ball.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../home/presentation/home_page.dart';
import '../application/workbench_tab_provider.dart';

class WorkbenchShellPage extends ConsumerWidget {
  const WorkbenchShellPage({super.key});

  static const List<Widget> _pages = <Widget>[
    DashboardPage(),
    HomePage(),
    _PlaceholderPage(
      title: '资讯',
      subtitle: '这里会放行业资讯、公告和重点消息。',
      icon: Icons.fact_check_outlined,
    ),
    _PlaceholderPage(
      title: '备忘录',
      subtitle: '这里会放便签、灵感草稿和快速记录。',
      icon: Icons.sticky_note_2_outlined,
    ),
    _PlaceholderPage(
      title: '我的',
      subtitle: '这里会放个人信息、偏好设置和账号相关内容。',
      icon: Icons.person_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int currentIndex = ref.watch(workbenchTabIndexProvider);
    void setIndex(int value) =>
        ref.read(workbenchTabIndexProvider.notifier).state = value;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      backgroundColor: const Color(0xFFF6F9FF),
      body: Stack(
        children: <Widget>[
          MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: IndexedStack(index: currentIndex, children: _pages),
          ),
          const AssistantOverlay(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: SizedBox(
          height: 94,
          child: Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFDCE7FF)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x120D47A1),
                        blurRadius: 22,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          children: List<Widget>.generate(2, (int index) {
                            return Expanded(
                              child: _NavButton(
                                item: _navItems[index],
                                selected: currentIndex == index,
                                onTap: () => setIndex(index),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(width: 80),
                      Expanded(
                        child: Row(
                          children: List<Widget>.generate(3, (int offset) {
                            final int index = offset + 2;
                            return Expanded(
                              child: _NavButton(
                                item: _navItems[index],
                                selected: currentIndex == index,
                                onTap: () => setIndex(index),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _AssistantDock(),
            ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              item.icon,
              color: selected
                  ? ScheduleBoardPalette.blueAccent
                  : const Color(0xFF253858),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected
                    ? ScheduleBoardPalette.blueAccent
                    : const Color(0xFF253858),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantDock extends ConsumerWidget {
  const _AssistantDock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AssistantUiState assistantState = ref.watch(
      assistantControllerProvider,
    );
    final AssistantStage stage = assistantState.stage;
    final double countdownProgress = assistantState.followUpRemainingMs <= 0
        ? 0
        : (assistantState.followUpRemainingMs / 5000).clamp(0, 1);
    return GestureDetector(
      onTap: () {
        final AssistantController controller = ref.read(
          assistantControllerProvider.notifier,
        );
        if (assistantState.pendingConfirm != null) {
          controller.openDrawer();
          return;
        }
        if (assistantState.drawerOpen) {
          controller.closeDrawer();
        } else {
          controller.startListening(
            source: AssistantEntrySource.drawerVoice,
            mode: AssistantListeningMode.openMic,
          );
        }
      },
      onLongPressStart: (_) => ref
          .read(assistantControllerProvider.notifier)
          .startListening(
            source: AssistantEntrySource.quickVoice,
            openDrawer: false,
            mode: AssistantListeningMode.pressToTalk,
          ),
      onLongPressEnd: (_) =>
          ref.read(assistantControllerProvider.notifier).stopListening(),
      onLongPressCancel: () =>
          ref.read(assistantControllerProvider.notifier).cancelListening(),
      child: SizedBox(
        width: 68,
        height: 68,
        child: AssistantBall(
          stage: stage,
          size: 68,
          countdownProgress: countdownProgress,
          audioLevel: ref.read(liveAudioLevelProvider),
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDCE7FF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x120D47A1),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 44, color: ScheduleBoardPalette.blueAccent),
                const SizedBox(height: 16),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF22324C),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ScheduleBoardPalette.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const List<_NavItem> _navItems = <_NavItem>[
  _NavItem(label: '看板', icon: Icons.home_filled),
  _NavItem(label: '日程', icon: Icons.event_note_rounded),
  _NavItem(label: '资讯', icon: Icons.check_box_outlined),
  _NavItem(label: '备忘录', icon: Icons.notes_rounded),
  _NavItem(label: '我的', icon: Icons.person_outline_rounded),
];
