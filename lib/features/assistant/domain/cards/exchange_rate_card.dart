import '../assistant_result_card.dart';

class ExchangeRateCard extends AssistantResultCard {
  const ExchangeRateCard({
    required this.fromCurrency,
    required this.fromCurrencyName,
    required this.toCurrency,
    required this.toCurrencyName,
    required this.fromAmount,
    required this.toAmount,
    required this.summary,
    this.change24h,
    this.isUp,
    this.updatedAt,
    this.note,
  });

  @override
  String get type => 'exchange_rate';

  @override
  final String summary;

  /// 源币种 ISO 代码，3 字母大写，如 "USD"
  final String fromCurrency;

  /// 源币种中文名，如 "美元"。模型未给时用 [fromCurrency] 兜底。
  final String fromCurrencyName;

  /// 目标币种 ISO 代码，3 字母大写，如 "CNY"
  final String toCurrency;

  /// 目标币种中文名，如 "人民币"。模型未给时用 [toCurrency] 兜底。
  final String toCurrencyName;

  /// 源金额，必须 > 0
  final double fromAmount;

  /// 目标金额，必须 > 0
  final double toAmount;

  /// 24h 涨跌幅文本，如 "+0.12%" / "-0.34%"
  final String? change24h;

  /// 是否上涨。null 表示未知。
  final bool? isUp;

  /// 数据更新时间（人话），如 "5 分钟前"
  final String? updatedAt;

  /// 免责说明，默认显示 "仅供参考"
  final String? note;

  static ExchangeRateCard? tryParse(Map<String, dynamic> json) {
    final String fromCurrency = _readString(json['fromCurrency']).toUpperCase();
    final String toCurrency = _readString(json['toCurrency']).toUpperCase();
    final double? fromAmount = _readPositiveDouble(json['fromAmount']);
    final double? toAmount = _readPositiveDouble(json['toAmount']);

    if (fromCurrency.length != 3 ||
        toCurrency.length != 3 ||
        !_isAllAlpha(fromCurrency) ||
        !_isAllAlpha(toCurrency) ||
        fromAmount == null ||
        toAmount == null) {
      return null;
    }

    final String rawFromName = _readString(json['fromCurrencyName']);
    final String rawToName = _readString(json['toCurrencyName']);
    final String fromName = rawFromName.isNotEmpty ? rawFromName : fromCurrency;
    final String toName = rawToName.isNotEmpty ? rawToName : toCurrency;

    final String autoSummary =
        '${_formatAmount(fromAmount)} $fromCurrency ≈ ${_formatAmount(toAmount)} $toCurrency';

    return ExchangeRateCard(
      fromCurrency: fromCurrency,
      fromCurrencyName: fromName,
      toCurrency: toCurrency,
      toCurrencyName: toName,
      fromAmount: fromAmount,
      toAmount: toAmount,
      summary: autoSummary,
      change24h: _readOptionalString(json['change24h']),
      isUp: _readOptionalBool(json['isUp']),
      updatedAt: _readOptionalString(json['updatedAt']),
      note: _readOptionalString(json['note']),
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
    if (s == 'true' || s == 'up' || s == '1') return true;
    if (s == 'false' || s == 'down' || s == '0') return false;
  }
  if (value is num) return value > 0;
  return null;
}

double? _readPositiveDouble(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final double d = value.toDouble();
    return d > 0 ? d : null;
  }
  if (value is String) {
    final String cleaned = value.trim().replaceAll(',', '');
    final double? d = double.tryParse(cleaned);
    if (d == null) return null;
    return d > 0 ? d : null;
  }
  return null;
}

bool _isAllAlpha(String s) => RegExp(r'^[A-Z]+$').hasMatch(s);

String _formatAmount(double v) {
  if (v == v.truncateToDouble()) {
    return v.toInt().toString();
  }
  String s = v.toStringAsFixed(2);
  if (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
