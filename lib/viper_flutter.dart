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
import 'package:viper_flutter/src/core/activity.dart';
import 'package:viper_flutter/src/core/console.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/slots.dart';

export 'package:viper_flutter/markers.dart' hide Viper;
export 'package:viper_flutter/src/core/api.dart' show implementationMarker, packageVersion;

/// Viper: what shared code calls, and the staging entry point's `runZoned` and `start`.
abstract final class Viper {
  static ViperRuntime? _runtime;

  /// The console and network log, kept from runZoned on, so what the app prints before Viper
  /// starts is there too (D333).
  static final ActivityLog _activity = ActivityLog();
  static final ConsoleCapture _console = ConsoleCapture(_activity);

  /// The console and network log, for tests.
  @visibleForTesting
  static ActivityLog get activity => _activity;

  /// The running Viper, once started.
  static ViperRuntime? get runtime => _runtime;

  /// Runs the app's `main` inside Viper's zone (D333), so what it prints reaches a capture's
  /// console. Call it first in `main_staging.dart`; the app's own zone handlers keep working.
  static R runZoned<R>(R Function() body) {
    if (!viperDefined) return body();
    return Zone.current.fork(specification: ZoneSpecification(print: _print)).run(body);
  }

  static void _print(Zone self, ZoneDelegate parent, Zone zone, String line) {
    _console.printed(line);
    parent.print(zone, line);
  }

  /// Starts Viper for the staging environment [key] on [host] (D336). Never waits on the
  /// network, so the first frame and offline launches don't wait on Viper. Below iOS 16.4 and
  /// Android API 24 it does nothing (D338). [identity] asks the app's backend for a signed
  /// identity (D21, D86); [context] adds to every capture what `Viper.context` would (D27).
  /// [revealHint] says the app has its own way to bring a hidden Viper back (`Viper.show` or
  /// `Viper.open`), in the words the tester is told when they hide it: "Long-press the logo on
  /// Account to bring it back." With it, "Hide Viper" is offered even where there's no shake (D371).
  static void start({
    required String key,
    required Uri host,
    Future<SignedIdentity?> Function()? identity,
    Map<String, Object?> Function()? context,
    String? revealHint,
  }) {
    if (!viperDefined || _runtime != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    // Before the app builds its HTTP clients, after it set its own error handlers (D333).
    _console.install();
    final runtime = ViperRuntime(
      key: key,
      host: host,
      identityCallback: identity,
      contextCallback: context,
      revealHint: revealHint,
      activity: _activity,
      onStop: _console.release,
    );
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

  /// See `Viper.show` in markers.dart.
  static void show() => markers.Viper.show();

  /// See `Viper.open` in markers.dart.
  static void open() => markers.Viper.open();
}
