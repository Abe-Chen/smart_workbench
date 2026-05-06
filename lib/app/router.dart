import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/reminder/presentation/reminder_alert_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/task/presentation/task_editor_page.dart';
import '../features/workbench/presentation/workbench_shell_page.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const WorkbenchShellPage()),
    GoRoute(
      path: '/task/new',
      builder: (context, state) => const TaskEditorPage(),
    ),
    GoRoute(
      path: '/task/:taskId',
      builder: (context, state) {
        final int taskId = int.parse(state.pathParameters['taskId']!);
        return TaskEditorPage(taskId: taskId);
      },
    ),
    GoRoute(
      path: '/reminder/:taskId',
      pageBuilder: (context, state) {
        final int taskId = int.parse(state.pathParameters['taskId']!);
        final DateTime occurrenceDate =
            DateTime.tryParse(state.uri.queryParameters['date'] ?? '') ??
            DateTime.now();
        return CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          barrierDismissible: false,
          child: ReminderAlertPage(
            taskId: taskId,
            occurrenceDate: DateTime(
              occurrenceDate.year,
              occurrenceDate.month,
              occurrenceDate.day,
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
