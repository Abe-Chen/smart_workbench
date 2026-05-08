import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../assistant/data/xunfei_tts_client.dart';
import '../application/about_info_provider.dart';
import '../application/app_settings_controller.dart';
import '../domain/app_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue settingsAsync = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      body: Column(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  ScheduleBoardPalette.headerStart,
                  ScheduleBoardPalette.headerEnd,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Row(
                  children: <Widget>[
                    Material(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(16),
                        child: const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '设置',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '把提醒、显示策略和本地能力说明统一放在这里。',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: settingsAsync.when(
              data: (settings) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: <Widget>[
                  _SettingsCard(
                    title: '显示与提醒',
                    subtitle: '这些开关会直接影响主页和各视图的展示方式。',
                    child: Column(
                      children: <Widget>[
                        SwitchListTile(
                          title: const Text(
                            '定时提醒',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text(
                            'V1 只做本地提醒，不接入云端推送',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: settings.remindersEnabled,
                          onChanged: (bool value) {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .setRemindersEnabled(value);
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text(
                            '显示已完成',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text(
                            '关闭后，已完成任务会从各视图隐藏',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: settings.showCompleted,
                          onChanged: (bool value) {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .setShowCompleted(value);
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text(
                            '显示农历 / 节假日',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text(
                            '仅做展示，不进入提醒和排序逻辑',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: settings.showLunar,
                          onChanged: (bool value) {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .setShowLunar(value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsCard(
                    title: '语音播报',
                    subtitle: '控制小治什么时候出声、用什么音色和语速。',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _TtsPlaybackModeSection(settings: settings),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 20),
                        _TtsSpeedSection(settings: settings),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 20),
                        _TtsVoiceSection(settings: settings),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsCard(
                    title: '能力边界',
                    subtitle: '把一期与后续阶段的边界写清楚，避免误解。',
                    child: Column(
                      children: const <Widget>[
                        ListTile(
                          leading: Icon(Icons.mic_none_outlined),
                          title: Text(
                            '录音备注',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'V1 仅保留本地录音与本地播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.language_outlined),
                          title: Text(
                            '语言',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'V1 先保留中文界面，英文后续补齐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsCard(
                    title: '关于',
                    subtitle: '版本号和设备信息，方便提交反馈或排查问题。',
                    child: const _AboutSection(),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '设置加载失败，请稍后重试。',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TtsVoiceSection extends ConsumerStatefulWidget {
  const _TtsVoiceSection({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_TtsVoiceSection> createState() => _TtsVoiceSectionState();
}

class _TtsVoiceSectionState extends ConsumerState<_TtsVoiceSection> {
  late String _selectedCode = normalizeTtsVoiceCode(widget.settings.ttsVoice);

  @override
  void didUpdateWidget(covariant _TtsVoiceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String incoming = normalizeTtsVoiceCode(widget.settings.ttsVoice);
    if (incoming != _selectedCode) {
      _selectedCode = incoming;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TtsVoiceOption selected = ttsVoiceOptionFor(_selectedCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '当前音色：${selected.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          selected.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '参数：${selected.code}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(selected.code),
          initialValue: selected.code,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '播报音色',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: kTtsVoiceOptions
              .map(
                (TtsVoiceOption option) => DropdownMenuItem<String>(
                  value: option.code,
                  child: Text(
                    '${option.label} · ${option.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            final String normalized = normalizeTtsVoiceCode(value);
            if (normalized == _selectedCode) {
              return;
            }
            setState(() {
              _selectedCode = normalized;
            });
            ref
                .read(appSettingsControllerProvider.notifier)
                .setTtsVoice(normalized);
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _previewVoice(context, ref, selected),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              '试听当前音色',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '切换后下一次播报会直接使用你选中的音色；如果报未授权，请到讯飞控制台确认该发音人还在当前账号下可用。',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
      ],
    );
  }

  Future<void> _previewVoice(
    BuildContext context,
    WidgetRef ref,
    TtsVoiceOption option,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '正在试听 ${option.label}（${option.code}）',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final double rate = ref.read(currentTtsSpeedProvider);
      await ref
          .read(xunfeiTtsClientProvider)
          .speak(
            '你好，我是小治。现在试听的是${option.label}。当前参数是${option.code}。',
            voice: option.code,
            xunfeiSpeed: xunfeiSpeedForRate(rate),
          );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '试听失败：$error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }
}

class _TtsPlaybackModeSection extends ConsumerWidget {
  const _TtsPlaybackModeSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TtsPlaybackMode mode = settings.ttsPlaybackMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '播报模式：${mode.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          mode.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TtsPlaybackMode>(
          key: ValueKey<String>(mode.code),
          initialValue: mode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '播报模式',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: TtsPlaybackMode.values
              .map(
                (TtsPlaybackMode option) =>
                    DropdownMenuItem<TtsPlaybackMode>(
                      value: option,
                      child: Text(
                        '${option.label} · ${option.description}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              )
              .toList(),
          onChanged: (TtsPlaybackMode? value) {
            if (value == null || value == mode) return;
            ref
                .read(appSettingsControllerProvider.notifier)
                .setTtsPlaybackMode(value);
          },
        ),
      ],
    );
  }
}

class _TtsSpeedSection extends ConsumerWidget {
  const _TtsSpeedSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double speed = settings.ttsSpeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '播报语速：${ttsSpeedLabel(speed)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '只对小治的回答播报生效，不影响系统其它语音。',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<double>(
          key: ValueKey<double>(speed),
          initialValue: speed,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '播报语速',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: kTtsSpeedOptions
              .map(
                (double option) => DropdownMenuItem<double>(
                  value: option,
                  child: Text(
                    ttsSpeedLabel(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (double? value) {
            if (value == null || value == speed) return;
            ref
                .read(appSettingsControllerProvider.notifier)
                .setTtsSpeed(value);
          },
        ),
      ],
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AboutInfo> info = ref.watch(aboutInfoProvider);
    return info.when(
      data: (AboutInfo data) => Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('应用名称'),
            subtitle: Text(
              data.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本号'),
            subtitle: Text(
              data.versionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tablet_android_outlined),
            title: const Text('设备型号'),
            subtitle: Text(
              data.deviceModel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.system_security_update_good_outlined),
            title: const Text('系统版本'),
            subtitle: Text(
              data.platformLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '设备信息读取失败',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ScheduleBoardPalette.mutedText,
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120E1F36),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ScheduleBoardPalette.mutedText,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
