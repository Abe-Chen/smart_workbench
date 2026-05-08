import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/amap_location_service.dart';
import '../../../../core/location/location_repository.dart';
import '../../domain/assistant_tool.dart';

class GetUserLocationTool extends AssistantTool {
  GetUserLocationTool(this._ref);

  final Ref _ref;

  @override
  String get name => 'get_user_location';

  @override
  String get description =>
      '获取用户当前所在城市。当用户问天气、附近地点、本地新闻等需要位置信息但用户没指定城市时调用。返回省份、城市名。';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{},
    'required': <String>[],
  };

  @override
  Future<String> call(Map<String, dynamic> args) async {
    try {
      final LocationRepository repo = await _ref.read(
        locationRepositoryProvider.future,
      );
      final CitySnapshot? snapshot = await repo.resolveCurrentCity();
      if (snapshot == null) {
        return '{"ok": false, "reason": "未获取到位置（无缓存且 IP 定位失败）"}';
      }
      final CityLocation city = snapshot.city;
      return '{"ok": true, "province": "${city.province}", '
          '"city": "${city.city}", "source": "${snapshot.source.name}"}';
    } catch (e) {
      return '{"ok": false, "reason": "$e"}';
    }
  }
}

final Provider<GetUserLocationTool> getUserLocationToolProvider =
    Provider<GetUserLocationTool>((Ref ref) => GetUserLocationTool(ref));
