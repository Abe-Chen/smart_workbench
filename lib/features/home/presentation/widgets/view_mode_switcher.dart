import 'package:flutter/material.dart';

import '../../application/home_view_mode.dart';

class ViewModeSwitcher extends StatelessWidget {
  const ViewModeSwitcher({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final HomeViewMode mode;
  final ValueChanged<HomeViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<HomeViewMode>(
      segments: HomeViewMode.values
          .map(
            (HomeViewMode item) => ButtonSegment<HomeViewMode>(
              value: item,
              label: Text(item.label),
            ),
          )
          .toList(),
      selected: <HomeViewMode>{mode},
      onSelectionChanged: (Set<HomeViewMode> value) {
        onChanged(value.first);
      },
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Theme.of(context).colorScheme.primary,
        selectedForegroundColor: Colors.white,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
