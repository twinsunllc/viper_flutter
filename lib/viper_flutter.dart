/// Viper's implementation (D336). Import it only from the app's staging entry point,
/// `main_staging.dart`; everything else imports `package:viper_flutter/markers.dart`.
///
/// ```dart
/// void main() => Viper.runZoned(() => app.main(onBoot: () => Viper.start(
///   key: 'vk_...',
///   host: Uri.parse('https://viper-volatile.twinsun.dev'),
/// )));
/// ```
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:viper_flutter/markers.dart' as markers;
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/slots.dart';

export 'package:viper_flutter/markers.dart' hide Viper;
export 'package:viper_flutter/src/core/api.dart' show implementationMarker, packageVersion;

/// Viper: what shared code calls, and the staging entry point's `runZoned` and `start`.
abstract final class Viper {
  static ViperRuntime? _runtime;

  /// The running Viper, once started.
  static ViperRuntime? get runtime => _runtime;

  /// Runs the app's `main` inside Viper's zone (D333), so what it prints reaches a capture's
  /// console. Call it first in `main_staging.dart`; the app's own zone handlers keep working.
  static R runZoned<R>(R Function() body) {
    if (!viperDefined) return body();
    return Zone.current.fork(specification: ZoneSpecification(print: _print)).run(body);
  }

  static void _print(Zone self, ZoneDelegate parent, Zone zone, String line) {
    // Kept for the console in slice 4 (D333); printed as the app meant either way.
    parent.print(zone, line);
  }

  /// Starts Viper for the staging environment [key] on [host] (D336). Never waits on the
  /// network, so the first frame and offline launches don't wait on Viper. Below iOS 16.4 and
  /// Android API 24 it does nothing (D338). [identity] asks the app's backend for a signed
  /// identity (D21, D86); [context] adds to every capture what `Viper.context` would (D27).
  static void start({
    required String key,
    required Uri host,
    Future<SignedIdentity?> Function()? identity,
    Map<String, Object?> Function()? context,
  }) {
    if (!viperDefined || _runtime != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final runtime = ViperRuntime(key: key, host: host, identityCallback: identity, contextCallback: context);
    _runtime = runtime;
    ViperSlots.handler.value = runtime;
    unawaited(runtime.boot());
  }

  /// See `Viper.wrap` in markers.dart.
  static Widget wrap({required Widget child}) => markers.Viper.wrap(child: child);

  /// See `Viper.observer` in markers.dart.
  static NavigatorObserver observer() => markers.Viper.observer();

  /// See `Viper.recordError` in markers.dart.
  static void recordError(Object error, StackTrace? stack) => markers.Viper.recordError(error, stack);

  /// See `Viper.identify` in markers.dart.
  static void identify(SignedIdentity? identity, {IdentityRefresh? refresh}) =>
      markers.Viper.identify(identity, refresh: refresh);

  /// See `Viper.context` in markers.dart.
  static void context(Map<String, Object?> values) => markers.Viper.context(values);
}
