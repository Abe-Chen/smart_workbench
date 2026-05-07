import 'package:flutter/widgets.dart';

const double _compactBreakpoint = 1100;

class DashboardMetrics {
  const DashboardMetrics._({
    required this.isCompact,
    required this.outerPadding,
    required this.outerVerticalPadding,
    required this.cardGap,
    required this.cardPadding,
    required this.cardRadius,
    required this.boardTitle,
    required this.sectionTitle,
    required this.taskRowHeight,
    required this.taskTimeColWidth,
    required this.taskTimeFontSize,
    required this.taskTitleFontSize,
    required this.taskMetaFontSize,
    required this.timelineDotSize,
    required this.timelineLineHeight,
    required this.goalsTitleFontSize,
    required this.goalsRowHeight,
    required this.goalsRowDividerHeight,
    required this.goalsItemFontSize,
    required this.nextTaskHeadlineFontSize,
    required this.nextTaskTitleFontSize,
    required this.nextTaskMetaFontSize,
    required this.nextTaskTitleMaxLines,
    required this.showNextTaskButton,
    required this.countdownRingSize,
    required this.countdownPrimaryFontSize,
    required this.weatherTempFontSize,
    required this.weatherSummaryFontSize,
    required this.weatherHourFontSize,
    required this.weatherTempSecondaryFontSize,
    required this.weatherHoursRowHeight,
    required this.showWeatherTomorrowRow,
    required this.summaryPillFontSize,
    required this.statusBarTimeFontSize,
    required this.statusBarDateFontSize,
    required this.rightColumnGoalsFlex,
    required this.rightColumnNextTaskFlex,
    required this.rightColumnWeatherFlex,
  });

  factory DashboardMetrics.of(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    return width <= _compactBreakpoint
        ? const DashboardMetrics._(
            isCompact: true,
            outerPadding: 14,
            outerVerticalPadding: 8,
            cardGap: 6,
            cardPadding: 12,
            cardRadius: 22,
            boardTitle: 17,
            sectionTitle: 14,
            taskRowHeight: 64,
            taskTimeColWidth: 48,
            taskTimeFontSize: 12,
            taskTitleFontSize: 13,
            taskMetaFontSize: 11,
            timelineDotSize: 8,
            timelineLineHeight: 30,
            goalsTitleFontSize: 14,
            goalsRowHeight: 30,
            goalsRowDividerHeight: 6,
            goalsItemFontSize: 13,
            nextTaskHeadlineFontSize: 18,
            nextTaskTitleFontSize: 15,
            nextTaskMetaFontSize: 12,
            nextTaskTitleMaxLines: 1,
            showNextTaskButton: false,
            countdownRingSize: 84,
            countdownPrimaryFontSize: 18,
            weatherTempFontSize: 22,
            weatherSummaryFontSize: 12,
            weatherHourFontSize: 11,
            weatherTempSecondaryFontSize: 12,
            weatherHoursRowHeight: 66,
            showWeatherTomorrowRow: false,
            summaryPillFontSize: 12,
            statusBarTimeFontSize: 15,
            statusBarDateFontSize: 13,
            rightColumnGoalsFlex: 7,
            rightColumnNextTaskFlex: 8,
            rightColumnWeatherFlex: 11,
          )
        : const DashboardMetrics._(
            isCompact: false,
            outerPadding: 18,
            outerVerticalPadding: 12,
            cardGap: 12,
            cardPadding: 18,
            cardRadius: 28,
            boardTitle: 20,
            sectionTitle: 17,
            taskRowHeight: 72,
            taskTimeColWidth: 56,
            taskTimeFontSize: 15,
            taskTitleFontSize: 15,
            taskMetaFontSize: 13,
            timelineDotSize: 10,
            timelineLineHeight: 36,
            goalsTitleFontSize: 16,
            goalsRowHeight: 40,
            goalsRowDividerHeight: 8,
            goalsItemFontSize: 14,
            nextTaskHeadlineFontSize: 22,
            nextTaskTitleFontSize: 19,
            nextTaskMetaFontSize: 14,
            nextTaskTitleMaxLines: 2,
            showNextTaskButton: true,
            countdownRingSize: 102,
            countdownPrimaryFontSize: 22,
            weatherTempFontSize: 26,
            weatherSummaryFontSize: 14,
            weatherHourFontSize: 12,
            weatherTempSecondaryFontSize: 13,
            weatherHoursRowHeight: 68,
            showWeatherTomorrowRow: true,
            summaryPillFontSize: 14,
            statusBarTimeFontSize: 18,
            statusBarDateFontSize: 16,
            rightColumnGoalsFlex: 8,
            rightColumnNextTaskFlex: 9,
            rightColumnWeatherFlex: 10,
          );
  }

  final bool isCompact;
  final double outerPadding;
  final double outerVerticalPadding;
  final double cardGap;
  final double cardPadding;
  final double cardRadius;
  final double boardTitle;
  final double sectionTitle;
  final double taskRowHeight;
  final double taskTimeColWidth;
  final double taskTimeFontSize;
  final double taskTitleFontSize;
  final double taskMetaFontSize;
  final double timelineDotSize;
  final double timelineLineHeight;
  final double goalsTitleFontSize;
  final double goalsRowHeight;
  final double goalsRowDividerHeight;
  final double goalsItemFontSize;
  final double nextTaskHeadlineFontSize;
  final double nextTaskTitleFontSize;
  final double nextTaskMetaFontSize;
  final int nextTaskTitleMaxLines;
  final bool showNextTaskButton;
  final double countdownRingSize;
  final double countdownPrimaryFontSize;
  final double weatherTempFontSize;
  final double weatherSummaryFontSize;
  final double weatherHourFontSize;
  final double weatherTempSecondaryFontSize;
  final double weatherHoursRowHeight;
  final bool showWeatherTomorrowRow;
  final double summaryPillFontSize;
  final double statusBarTimeFontSize;
  final double statusBarDateFontSize;
  final int rightColumnGoalsFlex;
  final int rightColumnNextTaskFlex;
  final int rightColumnWeatherFlex;
}
