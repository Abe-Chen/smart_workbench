import 'package:sqflite/sqflite.dart';

import '../../../core/database/schedule_database.dart';
import '../domain/app_settings.dart';

class LocalSettingsRepository {
  const LocalSettingsRepository(this._database);

  final ScheduleDatabase _database;

  Future<AppSettings> loadSettings() async {
    final database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'app_settings',
      where: 'id = ?',
      whereArgs: <Object?>[1],
      limit: 1,
    );

    if (rows.isEmpty) {
      final AppSettings defaults = const AppSettings();
      await saveSettings(defaults);
      return defaults;
    }

    return AppSettings.fromMap(rows.first);
  }

  Future<AppSettings> saveSettings(AppSettings settings) async {
    final database = await _database.database;
    final DateTime now = DateTime.now();
    await database.insert(
      'app_settings',
      settings.toDatabaseMap(now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return settings;
  }
}
