// What the app says while it runs (D333): print and debugPrint through Viper's zone around main,
// FlutterError.onError and PlatformDispatcher.onError chained to what the app set (Crashlytics
// keeps working), Viper.recordError from the app's own zone handler, and package:logging through
// onRecord, never changing the app's level.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:viper_flutter/src/core/activity.dart';
import 'package:viper_flutter/src/core/network.dart';

/// How many lines of a stack go with an error.
const int stackLines = 6;

/// An error and the top of its stack, as one console line.
String errorText(Object error, StackTrace? stack) {
  final top = stack == null
      ? ''
      : '\n${stack.toString().split('\n').where((line) => line.trim().isNotEmpty).take(stackLines).join('\n')}';
  return '$error$top';
}

/// Hooks the app's console and network into [log].
class ConsoleCapture {
  /// Captures into [log].
  ConsoleCapture(this.log);

  /// Where it all goes.
  final ActivityLog log;

  StreamSubscription<LogRecord>? _records;
  bool _installed = false;
  FlutterExceptionHandler? _flutterErrors;
  ErrorCallback? _platformErrors;
  FlutterExceptionHandler? _ourFlutter;
  ErrorCallback? _ourPlatform;
  HttpOverrides? _previousHttp;
  HttpOverrides? _ourHttp;

  /// A line printed inside Viper's zone.
  void printed(String line) => log.log('log', line);

  /// An error the app's own handler caught (Viper.recordError).
  void recordError(Object error, StackTrace? stack) => log.log('error', errorText(error, stack));

  /// Chains the error handlers, listens to package:logging and wraps the HTTP client, once.
  /// Called from Viper.start, after the app set its own handlers and before it builds its clients.
  void install() {
    if (_installed) return;
    _installed = true;
    final flutterErrors = _flutterErrors = FlutterError.onError;
    FlutterError.onError = _ourFlutter = (details) {
      log.log('error', errorText(details.exception, details.stack));
      flutterErrors?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final platformErrors = _platformErrors = dispatcher.onError;
    dispatcher.onError = _ourPlatform = (error, stack) {
      log.log('error', errorText(error, stack));
      return platformErrors?.call(error, stack) ?? false;
    };
    _records = Logger.root.onRecord.listen((record) {
      final level = record.level >= Level.SEVERE
          ? 'error'
          : record.level >= Level.WARNING
          ? 'warn'
          : record.level >= Level.INFO
          ? 'info'
          : 'log';
      final text = record.error == null
          ? record.message
          : '${record.message} ${errorText(record.error!, record.stackTrace)}';
      log.log(level, '[${record.loggerName}] $text');
    });
    _previousHttp = HttpOverrides.current;
    HttpOverrides.global = _ourHttp = ViperHttpOverrides(_previousHttp, log);
  }

  /// Takes it all back where nothing has replaced it since: Viper isn't running after all (below
  /// the OS floor, refused, switched off), so the app runs exactly as it would without it (D338).
  void release() {
    if (!_installed) return;
    _installed = false;
    if (identical(FlutterError.onError, _ourFlutter)) FlutterError.onError = _flutterErrors;
    if (identical(PlatformDispatcher.instance.onError, _ourPlatform)) {
      PlatformDispatcher.instance.onError = _platformErrors;
    }
    if (identical(HttpOverrides.current, _ourHttp)) HttpOverrides.global = _previousHttp;
    unawaited(_records?.cancel());
    _records = null;
  }
}
