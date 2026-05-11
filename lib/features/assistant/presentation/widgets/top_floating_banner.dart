import 'package:flutter/material.dart';

enum TopBannerKind { listenPartial, pushNotification }

class TopFloatingBanner extends StatefulWidget {
  const TopFloatingBanner({
    required this.kind,
    this.title,
    this.message,
    this.remainingMs = 0,
    this.onClose,
    this.onExpand,
    super.key,
  });

  final TopBannerKind kind;
  final String? title;
  final String? message;
  final int remainingMs;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;

  @override
  State<TopFloatingBanner> createState() => _TopFloatingBannerState();
}

class _TopFloatingBannerState extends State<TopFloatingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.28),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool listen = widget.kind == TopBannerKind.listenPartial;
    final Color accent = listen
        ? const Color(0xFF2F6BFF)
        : const Color(0xFFFF8A3D);
    final String title = listen
        ? '在听...'
        : (widget.title?.trim().isNotEmpty == true
              ? widget.title!.trim()
              : '提醒');
    final String message = _messageForKind(listen);
    final double progress = widget.remainingMs <= 0
        ? 0
        : (widget.remainingMs / 8000).clamp(0, 1).toDouble();

    return SafeArea(
      minimum: const EdgeInsets.only(top: 14, left: 16, right: 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE1E8F5)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F0D47A1),
                      blurRadius: 26,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: <Widget>[
                      _BannerIcon(accent: accent, listen: listen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: const Color(0xFF22324C),
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                                if (progress > 0) ...<Widget>[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 28,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 3,
                                      borderRadius: BorderRadius.circular(99),
                                      backgroundColor: const Color(0xFFE8EEF9),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              message,
                              maxLines: listen ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF60708A),
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (listen)
                        IconButton(
                          tooltip: '取消',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF7A8798),
                        )
                      else ...<Widget>[
                        TextButton(
                          onPressed: widget.onExpand,
                          child: const Text(
                            '展开',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF7A8798),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _messageForKind(bool listen) {
    final String raw = widget.message?.trim() ?? '';
    if (raw.isNotEmpty) {
      return raw;
    }
    return listen ? '你可以直接说需求' : '有一条新的事项需要你看一下';
  }
}

class _BannerIcon extends StatelessWidget {
  const _BannerIcon({required this.accent, required this.listen});

  final Color accent;
  final bool listen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Icon(
        listen ? Icons.mic_none_rounded : Icons.notifications_none_rounded,
        color: accent,
        size: 22,
      ),
    );
  }
}
