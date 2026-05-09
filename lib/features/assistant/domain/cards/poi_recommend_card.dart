import '../assistant_result_card.dart';

enum PoiKind { attraction, hotel, restaurant }

class PoiRecommendCard extends AssistantResultCard {
  const PoiRecommendCard({
    required this.subtype,
    required this.title,
    required this.items,
    required this.summary,
    this.subtitle,
    this.sourceNote,
  });

  @override
  String get type => 'poi_recommend';

  @override
  final String summary;

  final PoiKind subtype;
  final String title;
  final String? subtitle;

  /// 至少 1 条，最多 5 条；渲染层默认展示前 3 条。
  final List<PoiItem> items;

  /// 来源说明，如 "信息来自高德地图，以官方为准"。可空，渲染层会兜底。
  final String? sourceNote;

  static PoiRecommendCard? tryParse(Map<String, dynamic> json) {
    final PoiKind? subtype = _parsePoiKind(_readString(json['subtype']));
    if (subtype == null) return null;

    final String title = _readString(json['title']);
    if (title.isEmpty) return null;

    final List<dynamic> rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    final List<PoiItem> items = <PoiItem>[];
    for (final dynamic item in rawItems.take(5)) {
      if (item is! Map<String, dynamic>) continue;
      final PoiItem? poi = PoiItem.tryParse(item);
      if (poi != null) items.add(poi);
    }
    if (items.isEmpty) return null;

    final String summary = '$title（${items.length} 项）';

    return PoiRecommendCard(
      subtype: subtype,
      title: title,
      summary: summary,
      subtitle: _readOptionalString(json['subtitle']),
      sourceNote: _readOptionalString(json['sourceNote']),
      items: items,
    );
  }
}

class PoiItem {
  const PoiItem({
    required this.name,
    this.rating,
    this.priceLabel,
    this.distanceLabel,
    this.tag,
    this.iconEmoji,
  });

  final String name;

  /// 评分 0-5。校验失败置 null。
  final double? rating;

  /// 价格标签，如 "¥ 320 起" / "¥ 60"
  final String? priceLabel;

  /// 距离标签，必须带单位 km 或 m，如 "1.2km" / "850m"。校验失败置 null。
  final String? distanceLabel;

  /// 单个标签，如 "亲子" / "夜景"
  final String? tag;

  /// 类目 emoji，如 "🏛" / "🏨"。模型未填时由 widget 按 subtype 兜底。
  final String? iconEmoji;

  static PoiItem? tryParse(Map<String, dynamic> json) {
    final String name = _readString(json['name']);
    if (name.isEmpty) return null;

    final double? rawRating = _readDouble(json['rating']);
    final double? rating =
        (rawRating != null && rawRating >= 0 && rawRating <= 5) ? rawRating : null;

    final String? rawDistance = _readOptionalString(json['distanceLabel']);
    final String? distanceLabel =
        (rawDistance != null && _isValidDistance(rawDistance)) ? rawDistance : null;

    return PoiItem(
      name: name,
      rating: rating,
      priceLabel: _readOptionalString(json['priceLabel']),
      distanceLabel: distanceLabel,
      tag: _readOptionalString(json['tag']),
      iconEmoji: _readOptionalString(json['iconEmoji']),
    );
  }
}

PoiKind? _parsePoiKind(String s) {
  switch (s.toLowerCase().trim()) {
    case 'attraction':
    case 'attractions':
    case '景点':
      return PoiKind.attraction;
    case 'hotel':
    case 'hotels':
    case '酒店':
      return PoiKind.hotel;
    case 'restaurant':
    case 'restaurants':
    case '餐厅':
      return PoiKind.restaurant;
    default:
      return null;
  }
}

bool _isValidDistance(String s) {
  if (!RegExp(r'\d').hasMatch(s)) return false;
  final String lower = s.toLowerCase();
  return lower.contains('km') || lower.contains('m');
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

double? _readDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}
