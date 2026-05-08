import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _kDeviceIdKey = 'smart_workbench.device_id';

class DeviceIdRepository {
  DeviceIdRepository(this._prefs);

  final SharedPreferences _prefs;

  String getOrCreate() {
    final String? existing = _prefs.getString(_kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final String fresh = const Uuid().v4();
    _prefs.setString(_kDeviceIdKey, fresh);
    return fresh;
  }
}

final FutureProvider<DeviceIdRepository> deviceIdRepositoryProvider =
    FutureProvider<DeviceIdRepository>((Ref ref) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return DeviceIdRepository(prefs);
    });

final FutureProvider<String> deviceIdProvider = FutureProvider<String>((
  Ref ref,
) async {
  final DeviceIdRepository repo = await ref.watch(
    deviceIdRepositoryProvider.future,
  );
  return repo.getOrCreate();
});
