import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tools/get_user_location_tool.dart';
import '../domain/assistant_tool.dart';

class ToolRegistry {
  ToolRegistry(Iterable<AssistantTool> tools) {
    for (final AssistantTool t in tools) {
      _tools[t.name] = t;
    }
  }

  final Map<String, AssistantTool> _tools = <String, AssistantTool>{};

  AssistantTool? find(String name) => _tools[name];

  bool get isEmpty => _tools.isEmpty;

  List<Map<String, dynamic>> toApiJson() =>
      _tools.values.map((AssistantTool t) => t.toApiJson()).toList();
}

/// 注册当前仍由本地 function calling 处理的 tool。
/// 公网实时信息已经改走 Responses API + web_search，不在这里注册。
final Provider<ToolRegistry> toolRegistryProvider = Provider<ToolRegistry>((
  Ref ref,
) {
  return ToolRegistry(<AssistantTool>[ref.watch(getUserLocationToolProvider)]);
});
