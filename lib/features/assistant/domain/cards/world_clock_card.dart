import '../assistant_result_card.dart';

class WorldClockCard extends AssistantResultCard {
  const WorldClockCard({
    required this.cities,
    required this.summary,
    this.referenceCityName,
  });

  @override
  String get type => 'world_clock';

  @override
  final String summary;

  /// 至少 1 个，最多 5 个；渲染层最多展示前 3 个，剩余以"还有 N 个城市"提示。
  final List<WorldClockEntry> cities;

  /// 时差比较的基准城市（用户当前所在地），如 "北京"。可空。
  final String? referenceCityName;

  static WorldClockCard? tryParse(Map<String, dynamic> json) {
    final List<dynamic> rawCities = json['cities'] as List<dynamic>? ?? const <dynamic>[];
    final List<WorldClockEntry> cities = <WorldClockEntry>[];
    for (final dynamic item in rawCities.take(5)) {
      if (item is! Map<String, dynamic>) continue;
      final WorldClockEntry? entry = WorldClockEntry.tryParse(item);
      if (entry != null) cities.add(entry);
    }
    if (cities.isEmpty) return null;

    final String referenceCityName = _readString(json['referenceCityName']);

    final String summary = cities.length == 1
        ? '${cities.first.cityName}现在 ${cities.first.localTime}'
        : '${cities.length} 个城市的当前时间';

    return WorldClockCard(
      cities: cities,
      summary: summary,
      referenceCityName: referenceCityName.isEmpty ? null : referenceCityName,
    );
  }
}

class WorldClockEntry {
  const WorldClockEntry({
    required this.cityName,
    required this.localTime,
    this.timezone,
    this.weekday,
    this.offsetHint,
    this.isDst,
  });

  /// 城市显示名，如 "东京"
  final String cityName;

  /// 本地时间字符串，如 "14:30"
  final String localTime;

  /// IANA 时区，如 "Asia/Tokyo"。可空，仅作为元信息。
  final String? timezone;

  /// 星期，如 "周五"
  final String? weekday;

  /// 时差提示，如 "+1h vs 北京"。基准未知时省略。
  final String? offsetHint;

  /// 夏令时切换日为 true，渲染层显示"夏令时已切换"
  final bool? isDst;

  static WorldClockEntry? tryParse(Map<String, dynamic> json) {
    final String cityName = _readString(json['cityName']);
    final String localTime = _readString(json['localTime']);
    if (cityName.isEmpty || localTime.isEmpty) return null;

    return WorldClockEntry(
      cityName: cityName,
      localTime: localTime,
      timezone: _readOptionalString(json['timezone']),
      weekday: _readOptionalString(json['weekday']),
      offsetHint: _readOptionalString(json['offsetHint']),
      isDst: _readOptionalBool(json['isDst']),
    );
  }
}

String _readString(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

String? _readOptionalString(Object? value) {
  final String s = _readString(value);
  return s.isEmpty ? null : s;
}

bool? _readOptionalBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is String) {
    final String s = value.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  if (value is num) return value > 0;
  return null;
}
