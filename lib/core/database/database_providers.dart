import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/local_settings_repository.dart';
import '../../features/task/data/local_task_repository.dart';
import 'schedule_database.dart';

final scheduleDatabaseProvider = Provider<ScheduleDatabase>((Ref ref) {
  return ScheduleDatabase.instance;
});

final taskRepositoryProvider = Provider<LocalTaskRepository>((Ref ref) {
  return LocalTaskRepository(ref.watch(scheduleDatabaseProvider));
});

final settingsRepositoryProvider = Provider<LocalSettingsRepository>((Ref ref) {
  return LocalSettingsRepository(ref.watch(scheduleDatabaseProvider));
});
