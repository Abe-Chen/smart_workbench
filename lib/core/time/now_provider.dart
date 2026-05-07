import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每 30 秒 emit 一次 [DateTime.now()]，watch 它的 widget 会自动刷新时间派生 UI
/// （倒计时、"进行中"/"即将开始" badge、overdue 高亮、跨天的今日/明日切换）。
final StreamProvider<DateTime> nowProvider = StreamProvider<DateTime>((
  Ref ref,
) async* {
  yield DateTime.now();
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 30));
    yield DateTime.now();
  }
});
