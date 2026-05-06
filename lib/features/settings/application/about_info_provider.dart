import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutInfo {
  const AboutInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.deviceModel,
    required this.platformLabel,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String deviceModel;
  final String platformLabel;

  String get versionLabel =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}

final aboutInfoProvider = FutureProvider<AboutInfo>((Ref ref) async {
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();

  String deviceModel = '未知设备';
  String platformLabel = '未知平台';

  try {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo info = await deviceInfo.androidInfo;
      deviceModel = '${info.manufacturer} ${info.model}';
      platformLabel = 'Android ${info.version.release}';
    } else if (Platform.isIOS) {
      final IosDeviceInfo info = await deviceInfo.iosInfo;
      deviceModel = info.utsname.machine;
      platformLabel = '${info.systemName} ${info.systemVersion}';
    } else if (Platform.isMacOS) {
      final MacOsDeviceInfo info = await deviceInfo.macOsInfo;
      deviceModel = info.model;
      platformLabel = 'macOS ${info.osRelease}';
    } else if (Platform.isWindows) {
      final WindowsDeviceInfo info = await deviceInfo.windowsInfo;
      deviceModel = info.computerName;
      platformLabel = 'Windows ${info.displayVersion}';
    } else if (Platform.isLinux) {
      final LinuxDeviceInfo info = await deviceInfo.linuxInfo;
      deviceModel = info.prettyName;
      platformLabel = info.name;
    }
  } catch (_) {
    // 设备信息获取失败时退回默认占位
  }

  return AboutInfo(
    appName: packageInfo.appName.isEmpty
        ? 'Schedule Board'
        : packageInfo.appName,
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
    deviceModel: deviceModel,
    platformLabel: platformLabel,
  );
});
