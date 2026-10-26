// The package's own calls (D329, D336): the headers Viper matches the app by, the marker, and
// how each answer reads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/api.dart';

import 'support/fakes.dart';

void main() {
  late HttpServer server;
  late List<HttpRequest> requests;
  late void Function(HttpResponse response) answer;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests.add(request);
      answer(request.response);
      request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  HttpViperApi api() => HttpViperApi(
    host: Uri.parse('http://127.0.0.1:${server.port}'),
    key: 'hbr_loc_9w',
    appId: 'dev.twinsun.viper.example',
  );

  test('the config call names the key, the app, the platform and the package (D329, D336)', () async {
    answer = (response) => response.write(jsonEncode(exampleConfig()));
    final outcome = await api().config();
    expect(outcome, isA<ConfigOk>());
    final request = requests.single;
    expect(request.uri.path, '/widget/config');
    expect(request.uri.queryParameters['key'], 'hbr_loc_9w');
    expect(request.headers.value('X-Viper-Key'), 'hbr_loc_9w');
    expect(request.headers.value('X-Viper-Platform'), 'flutter');
    expect(request.headers.value('X-Viper-App'), 'dev.twinsun.viper.example');
    expect(request.headers.value('X-Viper-Client'), 'viper-flutter-implementation/$packageVersion');
    expect(request.headers.value('Origin'), isNull);
  });

  test('the marker is the string the artifact check looks for', () {
    expect(implementationMarker, 'viper-flutter-implementation');
    expect(clientHeader, startsWith(implementationMarker));
  });

  test('a refusal reads as one (D82)', () async {
    answer = (response) => response.write('{"ok":false,"reason":"untrusted_app"}');
    final outcome = await api().config();
    expect(outcome, isA<ConfigRefused>().having((o) => o.reason, 'reason', 'untrusted_app'));
  });

  test('an unreadable 404 is an unknown key; an unreadable 500 is unreachable', () async {
    answer = (response) => response
      ..statusCode = 404
      ..write('<html>');
    expect(await api().config(), isA<ConfigRefused>());
    answer = (response) => response
      ..statusCode = 500
      ..write('<html>');
    expect(await api().config(), isA<ConfigUnreachable>());
  });

  test('nothing listening is unreachable', () async {
    final port = server.port;
    await server.close(force: true);
    final outcome = await HttpViperApi(host: Uri.parse('http://127.0.0.1:$port'), key: 'k', appId: 'a').config();
    expect(outcome, isA<ConfigUnreachable>());
  });
}
