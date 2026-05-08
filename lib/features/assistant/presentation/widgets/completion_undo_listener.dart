import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant_controller.dart';
import '../../application/assistant_state.dart';

/// 监听 complete_task 成功后的撤销窗口，弹出 SnackBar。
class CompletionUndoListener extends ConsumerStatefulWidget {
  const CompletionUndoListener({super.key});

  @override
  ConsumerState<CompletionUndoListener> createState() =>
      _CompletionUndoListenerState();
}

class _CompletionUndoListenerState
    extends ConsumerState<CompletionUndoListener> {
  ProviderSubscription<AssistantUiState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual<AssistantUiState>(
      assistantControllerProvider,
      _handleStateChange,
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _handleStateChange(AssistantUiState? previous, AssistantUiState next) {
    final AssistantCompletionUndo? previousUndo = previous?.completionUndo;
    final AssistantCompletionUndo? nextUndo = next.completionUndo;

    final bool sameUndo =
        previousUndo?.taskId == nextUndo?.taskId &&
        previousUndo?.expireAtMillis == nextUndo?.expireAtMillis;
    if (sameUndo) {
      return;
    }

    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (messenger == null) {
      return;
    }

    if (nextUndo == null) {
      messenger.hideCurrentSnackBar();
      return;
    }

    final int remainingMs =
        nextUndo.expireAtMillis - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) {
      ref.read(assistantControllerProvider.notifier).dismissCompletionUndo();
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: remainingMs),
            content: _CompletionUndoContent(
              title: nextUndo.title,
              expireAtMillis: nextUndo.expireAtMillis,
            ),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => ref
                  .read(assistantControllerProvider.notifier)
                  .undoLastCompletion(),
            ),
          ),
        )
        .closed
        .then((_) {
          if (!mounted) {
            return;
          }
          ref
              .read(assistantControllerProvider.notifier)
              .dismissCompletionUndo();
        });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _CompletionUndoContent extends StatefulWidget {
  const _CompletionUndoContent({
    required this.title,
    required this.expireAtMillis,
  });

  final String title;
  final int expireAtMillis;

  @override
  State<_CompletionUndoContent> createState() => _CompletionUndoContentState();
}

class _CompletionUndoContentState extends State<_CompletionUndoContent> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int remainingMs =
        widget.expireAtMillis - DateTime.now().millisecondsSinceEpoch;
    final int remainingSeconds = remainingMs <= 0
        ? 0
        : (remainingMs / 1000).ceil().clamp(0, 5);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '已完成「${widget.title}」',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${remainingSeconds}s',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
