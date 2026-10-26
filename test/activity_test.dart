// The console and network a report carries (D333, D80): what's kept, how it's masked, the
// handlers chained to the app's, and the HTTP wrapper that leaves pinning alone.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:viper_flutter/src/core/activity.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/console.dart';
import 'package:viper_flutter/src/core/mask.dart';
import 'package:viper_flutter/src/core/network.dart';

void main() {
  group('the log', () {
    test('keeps the last 200 lines and 100 calls, each line at most 1,000 characters', () {
      final log = ActivityLog();
      for (var i = 0; i < 250; i++) {
        log.log('log', 'line $i');
      }
      log.log('warn', 'x' * 5000);
      for (var i = 0; i < 130; i++) {
        log.start('GET', Uri.parse('https://api.example.com/$i')).status = 200;
      }
      expect(log.console, hasLength(200));
      expect(log.console.first.text, 'line 51');
      expect(log.console.last.text, hasLength(1000));
      expect(log.network, hasLength(100));
      expect(log.network.first.url.path, '/30');
    });

    test('masks console text and strips queries at Strict and Maximum, never at Standard (D80)', () {
      final log = ActivityLog(clock: () => DateTime.utc(2026, 10, 26, 19));
      log.log('error', 'Card 4242 declined');
      log.start('POST', Uri.parse('https://api.example.com/charges?card=4242'))
        ..status = 402
        ..duration = const Duration(milliseconds: 120)
        ..requestId = 'req-9';
      log.start('GET', Uri.parse('https://api.example.com/pending'));
      expect(log.consoleEntries(PrivacyLevel.standard).single['text'], 'Card 4242 declined');
      expect(log.consoleEntries(PrivacyLevel.strict).single['text'], '•••• •••• ••••••••');
      expect(log.consoleEntries(PrivacyLevel.maximum).single['text'], '•••• •••• ••••••••');
      expect(log.networkEntries(PrivacyLevel.standard).single, {
        'method': 'POST',
        'path': 'https://api.example.com/charges?card=4242',
        'status': 402,
        'duration_ms': 120,
        'request_id': 'req-9',
      });
      expect(log.networkEntries(PrivacyLevel.strict).single['path'], 'https://api.example.com/charges');
      expect(
        log.consoleEntries(PrivacyLevel.standard).single['at_ms'],
        DateTime.utc(2026, 10, 26, 19).millisecondsSinceEpoch,
      );
    });

    test("the context keeps the web's limits: 40 keys, 1,000 characters a value, 8,000 in all (D27)", () {
      var context = mergeContext({}, {'plan': 'pro', 'big': 'x' * 2000, 'gone': 1});
      expect(context, {'plan': 'pro', 'gone': 1});
      context = mergeContext(context, {'gone': null});
      expect(context, {'plan': 'pro'});
      context = mergeContext(context, {for (var i = 0; i < 60; i++) 'k$i': i});
      expect(context, hasLength(40));
      context = mergeContext({}, {for (var i = 0; i < 12; i++) 'k$i': 'y' * 900});
      expect(jsonEncode(context).length, lessThanOrEqualTo(8000));
    });
  });

  group('the console', () {
    late FlutterExceptionHandler? flutterBefore;
    late ErrorCallback? platformBefore;
    late Level rootLevel;

    setUp(() {
      flutterBefore = FlutterError.onError;
      platformBefore = PlatformDispatcher.instance.onError;
      rootLevel = Logger.root.level;
    });

    tearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
      HttpOverrides.global = null;
    });

    test("chains to the app's handlers, so Crashlytics keeps working, and lets go again", () {
      final seen = <String>[];
      void app(FlutterErrorDetails details) => seen.add('app ${details.exception}');
      bool appPlatform(Object error, StackTrace stack) {
        seen.add('platform $error');
        return true;
      }

      FlutterError.onError = app;
      PlatformDispatcher.instance.onError = appPlatform;
      final log = ActivityLog();
      final capture = ConsoleCapture(log)..install();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('layout'), stack: StackTrace.current));
      expect(PlatformDispatcher.instance.onError!(ArgumentError('async'), StackTrace.current), isTrue);
      capture.recordError('from the zone', null);
      expect(seen, ['app Bad state: layout', 'platform Invalid argument(s): async']);
      expect(log.console.map((line) => line.level), ['error', 'error', 'error']);
      expect(log.console.first.text, startsWith('Bad state: layout\n'));

      capture.release();
      expect(identical(FlutterError.onError, app), isTrue);
      expect(identical(PlatformDispatcher.instance.onError, appPlatform), isTrue);
      expect(HttpOverrides.current, isNull);
    });

    test("hears package:logging without changing the app's level", () async {
      final log = ActivityLog();
      final capture = ConsoleCapture(log)..install();
      Logger('Auth').warning('token refresh failed');
      Logger('Auth').fine('below the level: never recorded');
      await Future<void>.delayed(Duration.zero);
      expect(Logger.root.level, rootLevel);
      expect(log.console.single.level, 'warn');
      expect(log.console.single.text, '[Auth] token refresh failed');
      capture.release();
    });
  });

  group('the network', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = request.uri.path == '/missing' ? 404 : 200
          ..headers.set('x-request-id', 'req-${request.uri.path.substring(1)}')
          ..write('body that is never kept');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<void> call(HttpClient client, String method, String path, {Map<String, String> headers = const {}}) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      headers.forEach(request.headers.set);
      final response = await request.close();
      await response.drain<void>();
    }

    test("logs the app's calls, never their bodies, and leaves Viper's own out (D109)", () async {
      final log = ActivityLog();
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        expect(client, isA<ViperHttpClient>());
        await call(client, 'GET', '/jobs?page=2');
        await call(client, 'POST', '/missing');
        await call(client, 'GET', '/widget/config', headers: {clientHeaderName: clientHeader});
        client.close();
      }, ViperHttpOverrides(null, log));
      await Future<void>.delayed(Duration.zero);
      final entries = log.networkEntries(PrivacyLevel.standard);
      expect(entries.map((e) => '${e['method']} ${e['path']} ${e['status']} ${e['request_id']}'), [
        'GET http://127.0.0.1:${server.port}/jobs?page=2 200 req-jobs',
        'POST http://127.0.0.1:${server.port}/missing 404 req-missing',
      ]);
      expect(jsonEncode(entries), isNot(contains('body that is never kept')));
    });

    test('a call that never connects is logged with why', () async {
      final log = ActivityLog();
      final port = server.port;
      await server.close(force: true);
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        await expectLater(client.getUrl(Uri.parse('http://127.0.0.1:$port/down')), throwsA(isA<SocketException>()));
        client.close();
      }, ViperHttpOverrides(null, log));
      expect(log.networkEntries(PrivacyLevel.standard).single['error'], startsWith('SocketException'));
    });

    test('forwards every property to the client it wraps', () {
      final inner = HttpClient();
      final client = ViperHttpClient(inner, ActivityLog())
        ..idleTimeout = const Duration(seconds: 3)
        ..connectionTimeout = const Duration(seconds: 4)
        ..maxConnectionsPerHost = 2
        ..userAgent = 'SetAndCo/2.4'
        ..autoUncompress = false;
      expect(inner.idleTimeout, const Duration(seconds: 3));
      expect(inner.connectionTimeout, const Duration(seconds: 4));
      expect(inner.maxConnectionsPerHost, 2);
      expect(inner.userAgent, 'SetAndCo/2.4');
      expect(inner.autoUncompress, isFalse);
      client.close();
    });
  });

  group('certificate pinning through the wrapper (D333)', () {
    late HttpServer server;
    final pem = File('test/support/certs/localhost.pem').readAsStringSync();

    setUp(() async {
      final context = SecurityContext()
        ..useCertificateChain('test/support/certs/localhost.pem')
        ..usePrivateKey('test/support/certs/localhost.key');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      server.listen((request) async {
        request.response.statusCode = 200;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    /// The app's pinning, installed after Viper's and chained to it, as Set&Co's is: it trusts no
    /// roots and accepts only the pinned certificate.
    HttpOverrides pinning(String pinned) => _Pinning(pinned, ViperHttpOverrides(null, ActivityLog()));

    Future<int> get(HttpOverrides overrides) => HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/'));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }, overrides);

    test('a pinned client still refuses a wrong certificate through it', () async {
      await expectLater(get(pinning('-----BEGIN CERTIFICATE-----\nnot this one')), throwsA(isA<HandshakeException>()));
    });

    test('and still takes the pinned one', () async {
      expect(await get(pinning(pem)), 200);
    });
  });
}

class _Pinning extends HttpOverrides {
  _Pinning(this.pinned, this.previous);

  final String pinned;
  final HttpOverrides previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = previous.createHttpClient(SecurityContext(withTrustedRoots: false));
    expect(client, isA<ViperHttpClient>(), reason: "the app's pinning wraps Viper's client");
    client.badCertificateCallback = (cert, host, port) => cert.pem.trim() == pinned.trim();
    return client;
  }
}
