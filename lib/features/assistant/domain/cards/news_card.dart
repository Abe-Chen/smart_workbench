import '../assistant_result_card.dart';

class NewsCard extends AssistantResultCard {
  const NewsCard({
    required this.title,
    required this.summary,
    required this.items,
    this.updatedAt,
    this.sourceNote,
  });

  @override
  String get type => 'news';

  final String title;

  @override
  final String summary;

  final List<NewsItem> items;
  final String? updatedAt;
  final String? sourceNote;

  static NewsCard? tryParse(Map<String, dynamic> json) {
    final String title = _readString(json['title']).isNotEmpty
        ? _readString(json['title'])
        : '新闻简报';
    final List<dynamic> rawItems =
        json['items'] as List<dynamic>? ?? const <dynamic>[];
    final List<NewsItem> items = <NewsItem>[];
    for (final dynamic item in rawItems.take(6)) {
      if (item is! Map<String, dynamic>) continue;
      final NewsItem? newsItem = NewsItem.tryParse(item);
      if (newsItem != null) items.add(newsItem);
    }
    if (items.isEmpty) return null;

    final String rawSummary = _readString(json['summary']);
    final String summary = rawSummary.isNotEmpty
        ? rawSummary
        : '$title，共 ${items.length} 条。';

    return NewsCard(
      title: title,
      summary: summary,
      items: items,
      updatedAt: _readOptionalString(json['updatedAt']),
      sourceNote: _readOptionalString(json['sourceNote']),
    );
  }
}

class NewsItem {
  const NewsItem({
    required this.title,
    this.summary,
    this.source,
    this.timeLabel,
    this.url,
  });

  final String title;
  final String? summary;
  final String? source;
  final String? timeLabel;
  final String? url;

  static NewsItem? tryParse(Map<String, dynamic> json) {
    final String title = _readString(json['title']);
    if (title.isEmpty) return null;
    return NewsItem(
      title: title,
      summary: _readOptionalString(json['summary']),
      source: _readOptionalString(json['source']),
      timeLabel: _readOptionalString(json['timeLabel']),
      url: _readOptionalUrl(json['url']),
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

String? _readOptionalUrl(Object? value) {
  final String s = _readString(value);
  if (s.isEmpty) return null;
  final Uri? uri = Uri.tryParse(s);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return null;
  }
  return s;
}
