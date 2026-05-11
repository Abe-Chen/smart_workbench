import 'package:flutter/material.dart';

class ToolFeedbackCardData {
  const ToolFeedbackCardData({
    required this.title,
    this.subtitle,
    this.rows = const <ToolFeedbackRow>[],
    this.undoLabel,
  });

  final String title;
  final String? subtitle;
  final List<ToolFeedbackRow> rows;
  final String? undoLabel;
}

class ToolFeedbackRow {
  const ToolFeedbackRow({
    required this.label,
    required this.value,
    this.icon,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool highlighted;
}

class ReminderCardData {
  const ReminderCardData({
    required this.title,
    required this.timeLabel,
    this.subtitle,
  });

  final String title;
  final String timeLabel;
  final String? subtitle;
}
