import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class ScheduleDatabase {
  ScheduleDatabase._();

  static final ScheduleDatabase instance = ScheduleDatabase._();

  Database? _database;

  Future<Database> get database async {
    return _database ??= await _open();
  }

  Future<Database> _open() async {
    final String databasesPath = await getDatabasesPath();
    final String databasePath = path.join(
      databasesPath,
      'smart_workbench_schedule.db',
    );

    return openDatabase(
      databasePath,
      version: 3,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            start_date TEXT NOT NULL,
            is_all_day INTEGER NOT NULL DEFAULT 1,
            start_time_minutes INTEGER,
            end_time_minutes INTEGER,
            reminder_key TEXT NOT NULL,
            custom_reminder_at TEXT,
            repeat_key TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT,
            deleted_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE task_voice_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL,
            local_path TEXT NOT NULL,
            duration_millis INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE app_settings (
            id INTEGER PRIMARY KEY,
            reminders_enabled INTEGER NOT NULL DEFAULT 1,
            show_completed INTEGER NOT NULL DEFAULT 1,
            show_lunar INTEGER NOT NULL DEFAULT 1,
            locale_code TEXT NOT NULL DEFAULT 'zh-CN',
            tts_voice TEXT NOT NULL DEFAULT 'x6_lingxiaoxuan_pro',
            tts_playback_mode TEXT NOT NULL DEFAULT 'auto',
            tts_speed REAL NOT NULL DEFAULT 1.0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        final String now = DateTime.now().toIso8601String();
        await db.insert('app_settings', <String, Object?>{
          'id': 1,
          'reminders_enabled': 1,
          'show_completed': 1,
          'show_lunar': 1,
          'locale_code': 'zh-CN',
          'tts_voice': 'x6_lingxiaoxuan_pro',
          'tts_playback_mode': 'auto',
          'tts_speed': 1.0,
          'created_at': now,
          'updated_at': now,
        });

        await db.execute(
          'CREATE INDEX idx_tasks_active_date ON tasks(start_date, status, deleted_at)',
        );
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE app_settings ADD COLUMN tts_voice TEXT NOT NULL DEFAULT 'x6_lingxiaoxuan_pro'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE app_settings ADD COLUMN tts_playback_mode TEXT NOT NULL DEFAULT 'auto'",
          );
          await db.execute(
            'ALTER TABLE app_settings ADD COLUMN tts_speed REAL NOT NULL DEFAULT 1.0',
          );
        }
      },
    );
  }
}
