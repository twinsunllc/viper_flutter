// What the phone and the app are (D27, D338): read once at start, and the connection on each
// capture.
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The phone and the app, read once.
class DeviceFacts {
  /// The facts.
  const DeviceFacts({
    required this.os,
    required this.osVersion,
    required this.model,
    required this.manufacturer,
    required this.physical,
    required this.appId,
    required this.build,
    this.sdkInt,
  });

  /// `iOS` or `Android`.
  final String os;

  /// The OS version as the phone says it: "26.0", "16".
  final String osVersion;

  /// Android's API level.
  final int? sdkInt;

  /// "iPhone17,1", "Pixel 9 Pro".
  final String model;

  /// "Apple", "Google".
  final String manufacturer;

  /// False on a simulator or an emulator.
  final bool physical;

  /// The bundle or application ID (D329).
  final String appId;

  /// `<version>+<build number>`, the build string (flutter.md, D103).
  final String build;

  /// Viper runs on iOS 16.4 and up and Android 7 (API 24) and up (D338).
  bool get supported {
    if (os == 'Android') return (sdkInt ?? 0) >= 24;
    if (os == 'iOS') return compareVersions(osVersion, '16.4') >= 0;
    return false;
  }

  /// Why it isn't supported, for the log.
  String get unsupportedReason => os == 'Android'
      ? 'Android API ${sdkInt ?? '?'} is below 24'
      : os == 'iOS'
      ? 'iOS $osVersion is below 16.4'
      : '$os is not iOS or Android';
}

/// Compares dotted versions numerically: "16.10" is after "16.4".
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0).toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Where the facts come from.
abstract interface class ViperDevice {
  /// The phone and the app.
  Future<DeviceFacts> facts();

  /// `wifi`, `cellular`, `ethernet`, `none` or `other`.
  Future<String> connection();
}

/// [ViperDevice] from device_info_plus, package_info_plus and connectivity_plus.
class PluginDevice implements ViperDevice {
  /// The device.
  PluginDevice();

  @override
  Future<DeviceFacts> facts() async {
    final package = await PackageInfo.fromPlatform();
    final build = package.buildNumber.isEmpty ? package.version : '${package.version}+${package.buildNumber}';
    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return DeviceFacts(
        os: 'iOS',
        osVersion: ios.systemVersion,
        model: ios.modelName.isNotEmpty ? ios.modelName : ios.utsname.machine,
        manufacturer: 'Apple',
        physical: ios.isPhysicalDevice,
        appId: package.packageName,
        build: build,
      );
    }
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return DeviceFacts(
        os: 'Android',
        osVersion: android.version.release,
        sdkInt: android.version.sdkInt,
        model: android.model,
        manufacturer: android.manufacturer,
        physical: android.isPhysicalDevice,
        appId: package.packageName,
        build: build,
      );
    }
    return DeviceFacts(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      model: '',
      manufacturer: '',
      physical: true,
      appId: package.packageName,
      build: build,
    );
  }

  @override
  Future<String> connection() async {
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.mobile)) return 'cellular';
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) return 'none';
    return 'other';
  }
}
