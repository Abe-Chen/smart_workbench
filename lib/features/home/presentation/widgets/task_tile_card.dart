import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/task_preview.dart';
import '../../../../core/voice/voice_player_service.dart';
import '../../../../core/voice/voice_providers.dart';

class TaskTileCard extends ConsumerWidget {
  const TaskTileCard({
    required this.task,
    required this.onToggleComplete,
    this.onTap,
    super.key,
  });

  final TaskPreview task;
  final VoidCallback onToggleComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final ({Color background, Color border, Color text}) palette =
        switch (task.state) {
          TaskVisualState.active => (
            background: Colors.white,
            border: ScheduleBoardPalette.boardBorder,
            text: colorScheme.onSurface,
          ),
          TaskVisualState.completed => (
            background: const Color(0xFFF3F4F6),
            border: const Color(0xFFD9DCDD),
            text: const Color(0xFF58606B),
          ),
          TaskVisualState.overdue => (
            background: const Color(0xFFFFF5F0),
            border: const Color(0xFFF5C7B1),
            text: colorScheme.onSurface,
          ),
        };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C0E1F36),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const Icon(Icons.access_time_rounded, size: 18),
                        Text(
                          task.timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: task.state == TaskVisualState.overdue
                                    ? const Color(0xFFB44C22)
                                    : ScheduleBoardPalette.mutedText,
                              ),
                        ),
                        if (task.delayDays > 0)
                          Text(
                            '顺延${task.delayDays}天',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFFE14D3A),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        if (task.hasVoiceNote && task.voiceFilePath != null)
                          _VoicePlayChip(
                            filePath: task.voiceFilePath!,
                            durationMillis: task.voiceDurationMillis,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggleComplete,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    size: 32,
                    color: task.state == TaskVisualState.completed
                        ? ScheduleBoardPalette.warmAccent
                        : const Color(0xFFBFBFBF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePlayChip extends ConsumerWidget {
  const _VoicePlayChip({required this.filePath, required this.durationMillis});

  final String filePath;
  final int durationMillis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoicePlayerService player = ref.watch(voicePlayerServiceProvider);
    return StreamBuilder<VoicePlaybackSnapshot>(
      stream: player.stateStream,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<VoicePlaybackSnapshot> snapshot,
          ) {
            final bool playing = snapshot.data?.isActiveFor(filePath) ?? false;
            return Material(
              color: const Color(0xFFE6F8F6),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () async {
                  if (playing) {
                    await player.stop();
                  } else {
                    await player.playFile(filePath);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 18,
                        color: ScheduleBoardPalette.tealAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        durationMillis > 0
                            ? _formatShort(durationMillis)
                            : '语音',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ScheduleBoardPalette.tealAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
    );
  }

  String _formatShort(int millis) {
    final int seconds = (millis / 1000).round();
    final int minutes = seconds ~/ 60;
    final int rem = seconds % 60;
    if (minutes == 0) {
      return '$rem″';
    }
    return '$minutes′${rem.toString().padLeft(2, '0')}″';
  }
}
