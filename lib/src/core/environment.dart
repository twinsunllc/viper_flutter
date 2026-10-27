// What every capture logs from a phone (D27, D332): DeviceEnvironmentInfo in the protocol.
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/device.dart';

/// How the picture was taken, for the capture's `screenshot` field (D338).
class ScreenshotInfo {
  /// How it was taken.
  const ScreenshotInfo({required this.method, this.platformViewsBlocked = false, this.blocked});

  /// No picture was taken.
  const ScreenshotInfo.none({this.blocked}) : method = 'none', platformViewsBlocked = false;

  /// `native`, `flutter` or `none`.
  final String method;

  /// True when native views came out blank and were blocked (Flutter's own `toImage`).
  final bool platformViewsBlocked;

  /// `secure_window` or `failed`, when there's no picture.
  final String? blocked;

  /// As the protocol has it.
  Map<String, Object?> toJson() => {
    'method': method,
    'platform_views_blocked': platformViewsBlocked,
    'blocked': ?blocked,
  };
}

/// What the app adds to a capture.
class AppDetails {
  /// The details.
  const AppDetails({this.environment, this.userId, this.context});

  /// The environment's kind from the config: `staging`.
  final String? environment;

  /// The signed-in person's id in the app, from their identity.
  final String? userId;

  /// What `Viper.context` and the start's context callback said.
  final Map<String, Object?>? context;
}

/// Builds DeviceEnvironmentInfo from the view, the platform's settings and the device's facts.
Map<String, Object?> deviceEnvironment({
  required DeviceFacts facts,
  required ui.FlutterView view,
  required String connection,
  required ScreenshotInfo screenshot,
  required DateTime capturedAt,
  required Duration appOpen,
  required String timezone,
  AppDetails app = const AppDetails(),
}) {
  final dispatcher = view.platformDispatcher;
  final media = MediaQueryData.fromView(view);
  final size = media.size;
  final features = dispatcher.accessibilityFeatures;
  final locales = dispatcher.locales;
  return {
    'platform': 'flutter',
    'device': {
      'model': facts.model,
      'manufacturer': facts.manufacturer,
      'physical': facts.physical,
      'tablet': size.shortestSide >= 600,
    },
    'os': {'name': facts.os, 'version': facts.osVersion, 'sdk_int': ?facts.sdkInt},
    'screen': {
      'logical': {'width': _round(size.width), 'height': _round(size.height)},
      'device_pixel_ratio': view.devicePixelRatio,
      'orientation': size.width > size.height ? 'landscape' : 'portrait',
      'padding': {
        'top': _round(media.padding.top),
        'bottom': _round(media.padding.bottom),
        'left': _round(media.padding.left),
        'right': _round(media.padding.right),
      },
      'keyboard_open': media.viewInsets.bottom > 0,
    },
    'preferences': {
      'brightness': dispatcher.platformBrightness == Brightness.dark ? 'dark' : 'light',
      'text_scale': _round(media.textScaler.scale(100) / 100),
      'bold_text': features.boldText,
      'reduced_motion': features.disableAnimations || features.reduceMotion,
      'high_contrast': features.highContrast,
      'screen_reader': features.accessibleNavigation,
      'locale': dispatcher.locale.toLanguageTag(),
      'locales': [for (final locale in locales) locale.toLanguageTag()],
      'timezone': timezone,
    },
    'connection': {'type': connection, 'online': connection != 'none'},
    'app': {
      'id': facts.appId,
      'build': facts.build,
      'commit': ?facts.commit,
      'flutter_version': ?FlutterVersion.version,
      'environment': ?app.environment,
      'user_id': ?app.userId,
      if (app.context != null && app.context!.isNotEmpty) 'context': app.context,
    },
    'screenshot': screenshot.toJson(),
    'time': {'captured_at': capturedAt.toUtc().toIso8601String(), 'app_open_ms': appOpen.inMilliseconds},
  };
}

double _round(double value) => (value * 100).roundToDouble() / 100;

/// The phone's time zone as best Dart can say it without native help: the abbreviation and the
/// offset ("HST, UTC-10:00").
String dartTimezone(DateTime now) {
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  return '${now.timeZoneName}, UTC$sign$hh:$mm';
}

/// Rounds to two places, the way the payload does.
double roundForPayload(double value) => _round(value);
