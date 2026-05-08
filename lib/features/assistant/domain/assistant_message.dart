import 'assistant_result_card.dart';
import 'tool_call.dart';

enum AssistantRole { user, assistant, system, tool }

extension AssistantRoleApi on AssistantRole {
  String get apiValue {
    switch (this) {
      case AssistantRole.user:
        return 'user';
      case AssistantRole.assistant:
        return 'assistant';
      case AssistantRole.system:
        return 'system';
      case AssistantRole.tool:
        return 'tool';
    }
  }
}

class AssistantMessage {
  AssistantMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.streaming = false,
    this.resultCard,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
  }) : createdAt = createdAt ?? DateTime.now();

  final AssistantRole role;
  final String content;
  final DateTime createdAt;
  final bool streaming;

  /// 仅展示层使用的场景化结果卡，不参与 API 会话历史。
  final AssistantResultCard? resultCard;

  /// 仅 assistant 角色发起 function call 时填，对应 chat 协议的 `tool_calls`。
  final List<ToolCall>? toolCalls;

  /// 仅 tool 角色回填，对应 chat 协议的 `tool_call_id`。
  final String? toolCallId;

  /// 仅 tool 角色，被回的工具名。
  final String? toolName;

  bool get isToolRequest =>
      role == AssistantRole.assistant &&
      toolCalls != null &&
      toolCalls!.isNotEmpty;

  bool get isVisibleInChat {
    // tool 请求 + tool 结果不展示给用户。
    if (role == AssistantRole.system) return false;
    if (role == AssistantRole.tool) return false;
    if (role == AssistantRole.assistant && content.isEmpty && isToolRequest) {
      return false;
    }
    return true;
  }

  AssistantMessage copyWith({
    String? content,
    bool? streaming,
    AssistantResultCard? resultCard,
    List<ToolCall>? toolCalls,
  }) {
    return AssistantMessage(
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      streaming: streaming ?? this.streaming,
      resultCard: resultCard ?? this.resultCard,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId,
      toolName: toolName,
    );
  }

  Map<String, dynamic> toApiJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'role': role.apiValue,
      'content': content,
    };
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!
          .map((ToolCall c) => c.toApiJson())
          .toList();
    }
    if (toolCallId != null) {
      json['tool_call_id'] = toolCallId;
    }
    if (toolName != null) {
      json['name'] = toolName;
    }
    return json;
  }
}
