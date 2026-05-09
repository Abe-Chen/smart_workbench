enum AssistantProactiveActionKind {
  weather,
  tripPlan,
  route,
  checklist,
  agenda,
  reminder,
  dismiss,
}

class AssistantProactiveAction {
  const AssistantProactiveAction({
    required this.id,
    required this.kind,
    required this.label,
    this.prompt,
    this.dismissOnly = false,
  });

  final String id;
  final AssistantProactiveActionKind kind;
  final String label;
  final String? prompt;
  final bool dismissOnly;
}

class AssistantProactiveSuggestion {
  const AssistantProactiveSuggestion({
    required this.id,
    required this.title,
    required this.message,
    required this.actions,
  });

  final String id;
  final String title;
  final String message;
  final List<AssistantProactiveAction> actions;
}
