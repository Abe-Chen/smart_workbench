import 'package:lunar/lunar.dart';

class LunarLabel {
  const LunarLabel({required this.text, this.isFestival = false});

  final String text;
  final bool isFestival;
}

LunarLabel lunarLabelFor(DateTime date) {
  final Lunar lunar = Lunar.fromDate(
    DateTime(date.year, date.month, date.day),
  );

  final List<String> festivals = <String>[
    ...lunar.getFestivals(),
    ...lunar.getOtherFestivals(),
  ];
  if (festivals.isNotEmpty) {
    return LunarLabel(text: festivals.first, isFestival: true);
  }

  final String jieQi = lunar.getJieQi();
  if (jieQi.isNotEmpty) {
    return LunarLabel(text: jieQi, isFestival: true);
  }

  if (lunar.getDay() == 1) {
    return LunarLabel(text: '${lunar.getMonthInChinese()}月');
  }

  return LunarLabel(text: lunar.getDayInChinese());
}
