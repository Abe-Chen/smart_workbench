import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../application/home_view_mode.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.dateLabel,
    required this.mode,
    required this.onCreateTask,
    required this.onJumpToToday,
    required this.onModeChanged,
    required this.onPickDate,
    required this.onRefresh,
    required this.onOpenSettings,
    super.key,
  });

  final String dateLabel;
  final HomeViewMode mode;
  final VoidCallback onCreateTask;
  final VoidCallback onJumpToToday;
  final ValueChanged<HomeViewMode> onModeChanged;
  final VoidCallback onPickDate;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool compact = MediaQuery.sizeOf(context).width < 960;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            ScheduleBoardPalette.headerStart,
            ScheduleBoardPalette.headerEnd,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          10,
          compact ? 12 : 16,
          10,
        ),
        child: compact
            ? _buildCompact(context, textTheme)
            : _buildWide(context, textTheme),
      ),
    );
  }

  Widget _buildWide(BuildContext context, TextTheme textTheme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _TopActionPill(label: '今天', onTap: onJumpToToday),
            ],
          ),
        ),
        const SizedBox(width: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: HomeViewMode.values.map((HomeViewMode item) {
              final bool selected = item == mode;
              return Padding(
                padding: const EdgeInsets.all(2),
                child: GestureDetector(
                  onTap: () => onModeChanged(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? ScheduleBoardPalette.blueAccent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.label,
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        _TopIconButton(icon: Icons.add_rounded, onTap: onCreateTask),
        const SizedBox(width: 10),
        _TopIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
        const SizedBox(width: 10),
        _TopIconButton(icon: Icons.settings_outlined, onTap: onOpenSettings),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TopActionPill(label: '今天', onTap: onJumpToToday),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: HomeViewMode.values.map((HomeViewMode item) {
                    final bool selected = item == mode;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: GestureDetector(
                          onTap: () => onModeChanged(item),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? ScheduleBoardPalette.blueAccent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              item.label,
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TopIconButton(icon: Icons.add_rounded, onTap: onCreateTask),
            const SizedBox(width: 8),
            _TopIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
            const SizedBox(width: 8),
            _TopIconButton(
              icon: Icons.settings_outlined,
              onTap: onOpenSettings,
            ),
          ],
        ),
      ],
    );
  }
}

class _TopActionPill extends StatelessWidget {
  const _TopActionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
