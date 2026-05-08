import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'amap_location_service.dart';

const String _kCacheKey = 'smart_workbench.user_city';
const Duration _kCacheTtl = Duration(hours: 24);

/// 城市偏好的来源：本地缓存 / 实时 IP 定位 / 用户手动覆盖。
enum CitySource { cached, fetched, manual }

class CitySnapshot {
  const CitySnapshot({required this.city, required this.source});
  final CityLocation city;
  final CitySource source;
}

class LocationRepository {
  LocationRepository({
    required SharedPreferences prefs,
    required AmapLocationService service,
  })  : _prefs = prefs,
        _service = service;

  final SharedPreferences _prefs;
  final AmapLocationService _service;

  /// 优先返回 24 小时内的缓存；否则刷一次 IP 定位再缓存。
  /// 网络失败时若存在过期缓存仍返回（以已知值兜底，不抛错）。
  Future<CitySnapshot?> resolveCurrentCity({bool forceRefresh = false}) async {
    final CityLocation? cached = _readCache();
    if (!forceRefresh && cached != null && _isFresh(cached)) {
      return CitySnapshot(city: cached, source: CitySource.cached);
    }
    try {
      final CityLocation fresh = await _service.fetch();
      await _writeCache(fresh);
      return CitySnapshot(city: fresh, source: CitySource.fetched);
    } catch (_) {
      if (cached != null) {
        return CitySnapshot(city: cached, source: CitySource.cached);
      }
      return null;
    }
  }

  Future<void> setManualCity(String cityName) async {
    final CityLocation manual = CityLocation(
      province: '',
      city: cityName,
      adcode: '',
      fetchedAt: DateTime.now(),
    );
    await _writeCache(manual);
  }

  CityLocation? _readCache() {
    final String? raw = _prefs.getString(_kCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CityLocation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(CityLocation city) async {
    await _prefs.setString(_kCacheKey, jsonEncode(city.toJson()));
  }

  bool _isFresh(CityLocation city) {
    return DateTime.now().difference(city.fetchedAt) < _kCacheTtl;
  }
}

final FutureProvider<LocationRepository> locationRepositoryProvider =
    FutureProvider<LocationRepository>((Ref ref) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AmapLocationService service = ref.watch(amapLocationServiceProvider);
      return LocationRepository(prefs: prefs, service: service);
    });
