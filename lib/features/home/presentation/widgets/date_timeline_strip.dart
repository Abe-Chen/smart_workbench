import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/calendar_utils.dart';
import '../../../../core/utils/lunar_utils.dart';
import '../../../../core/utils/task_formatters.dart';
import '../../../settings/application/app_settings_controller.dart';

class DateTimelineStrip extends ConsumerWidget {
  const DateTimelineStrip({
    required this.dates,
    required this.selectedDate,
    required this.onSelectDate,
    required this.taskCounts,
    super.key,
  });

  final List<DateTime> dates;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final Map<DateTime, int> taskCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool showLunar = ref
            .watch(appSettingsControllerProvider)
            .valueOrNull
            ?.showLunar ??
        true;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: showLunar ? 132 : 112,
        child: Row(
          children: dates.map((DateTime date) {
            final bool selected = isSameDate(date, selectedDate);
            final int count = taskCounts[normalizeDate(date)] ?? 0;
            final LunarLabel? lunar = showLunar ? lunarLabelFor(date) : null;
            return Expanded(
              child: Material(
                color: selected ? const Color(0xFFF3F6FF) : Colors.white,
                child: InkWell(
                  onTap: () => onSelectDate(date),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: date == dates.last
                              ? Colors.transparent
                              : ScheduleBoardPalette.boardBorder,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          formatWeekdayLabel(date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? ScheduleBoardPalette.blueAccent
                                  : Colors.transparent,
                              width: 2.4,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? ScheduleBoardPalette.blueAccent
                                      : null,
                                ),
                          ),
                        ),
                        if (lunar != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            lunar.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: lunar.isFestival
                                      ? const Color(0xFFB44C22)
                                      : ScheduleBoardPalette.mutedText,
                                  fontWeight: lunar.isFestival
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: count > 0 ? 1 : 0,
                          child: Container(
                            width: 14,
                            height: 5,
                            decoration: BoxDecoration(
                              color: ScheduleBoardPalette.blueAccent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
