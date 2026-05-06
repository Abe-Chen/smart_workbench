class AppSettings {
  const AppSettings({
    this.remindersEnabled = true,
    this.showCompleted = true,
    this.showLunar = true,
    this.localeCode = 'zh-CN',
  });

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      remindersEnabled: (map['reminders_enabled'] as int? ?? 1) == 1,
      showCompleted: (map['show_completed'] as int? ?? 1) == 1,
      showLunar: (map['show_lunar'] as int? ?? 1) == 1,
      localeCode: map['locale_code'] as String? ?? 'zh-CN',
    );
  }

  final bool remindersEnabled;
  final bool showCompleted;
  final bool showLunar;
  final String localeCode;

  AppSettings copyWith({
    bool? remindersEnabled,
    bool? showCompleted,
    bool? showLunar,
    String? localeCode,
  }) {
    return AppSettings(
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      showCompleted: showCompleted ?? this.showCompleted,
      showLunar: showLunar ?? this.showLunar,
      localeCode: localeCode ?? this.localeCode,
    );
  }

  Map<String, Object?> toDatabaseMap(DateTime now) {
    final String timestamp = now.toIso8601String();
    return <String, Object?>{
      'id': 1,
      'reminders_enabled': remindersEnabled ? 1 : 0,
      'show_completed': showCompleted ? 1 : 0,
      'show_lunar': showLunar ? 1 : 0,
      'locale_code': localeCode,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }
}
