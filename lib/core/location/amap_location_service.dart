import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';

/// 高德 IP 定位返回的城市信息。
class CityLocation {
  const CityLocation({
    required this.province,
    required this.city,
    required this.adcode,
    required this.fetchedAt,
  });

  factory CityLocation.fromJson(Map<String, dynamic> json) {
    return CityLocation(
      province: (json['province'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      adcode: (json['adcode'] as String?) ?? '',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        json['fetchedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  final String province;
  final String city;
  final String adcode;
  final DateTime fetchedAt;

  String get displayName => city.isNotEmpty ? city : province;
  bool get isEmpty => displayName.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'province': province,
    'city': city,
    'adcode': adcode,
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
  };
}

class AmapLocationException implements Exception {
  AmapLocationException(this.message);
  final String message;
  @override
  String toString() => 'AmapLocationException: $message';
}

class AmapLocationService {
  AmapLocationService({required EnvConfig env, Dio? dio})
    : _env = env,
      _dio = dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );

  static const String _endpoint = 'https://restapi.amap.com/v3/ip';

  final EnvConfig _env;
  final Dio _dio;

  Future<CityLocation> fetch() async {
    if (!_env.hasAmapCredentials) {
      throw AmapLocationException('未配置 AMAP_KEY');
    }
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>(
          _endpoint,
          queryParameters: <String, dynamic>{'key': _env.amapKey},
        );
    final Map<String, dynamic>? data = response.data;
    if (data == null) {
      throw AmapLocationException('高德 IP 定位返回空');
    }
    if (data['status'] != '1') {
      throw AmapLocationException(
        '高德 IP 定位失败：${data['info'] ?? data['infocode']}',
      );
    }
    final String province = _readString(data['province']);
    final String city = _readString(data['city']);
    final String adcode = _readString(data['adcode']);
    if (province.isEmpty && city.isEmpty) {
      throw AmapLocationException('高德返回的省市为空（可能 IP 异常）');
    }
    return CityLocation(
      province: province,
      city: city,
      adcode: adcode,
      fetchedAt: DateTime.now(),
    );
  }

  static String _readString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }
}

final Provider<AmapLocationService> amapLocationServiceProvider =
    Provider<AmapLocationService>((Ref ref) {
      final EnvConfig env = ref.watch(envConfigProvider);
      return AmapLocationService(env: env);
    });
