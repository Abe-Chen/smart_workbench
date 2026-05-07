import 'package:flutter_riverpod/flutter_riverpod.dart';

enum WorkbenchTab { dashboard, schedule, news, memo, profile }

extension WorkbenchTabIndex on WorkbenchTab {
  int get index {
    switch (this) {
      case WorkbenchTab.dashboard:
        return 0;
      case WorkbenchTab.schedule:
        return 1;
      case WorkbenchTab.news:
        return 2;
      case WorkbenchTab.memo:
        return 3;
      case WorkbenchTab.profile:
        return 4;
    }
  }
}

final StateProvider<int> workbenchTabIndexProvider = StateProvider<int>(
  (Ref ref) => 0,
);
