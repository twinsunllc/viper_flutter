// The app's own network calls (D333): an HttpOverrides wrapper around dart:io's HttpClient that
// forwards every property to the client it wraps, so certificate pinning and proxies still apply,
// and notes each call's method, path, status, duration and request id. Never a body. It wraps
// whatever overrides were current when Viper started; an override the app installs later must
// chain to it (as Set&Co's pinning does with `previous:`). Viper's own calls carry X-Viper-Client
// and are left out. It doesn't see web sockets or native SDKs' own traffic.
import 'dart:async';
import 'dart:io';

import 'package:viper_flutter/src/core/activity.dart';
import 'package:viper_flutter/src/core/api.dart';

/// The overrides Viper installs: every client the app makes goes through [ViperHttpClient].
class ViperHttpOverrides extends HttpOverrides {
  /// Wraps [previous], the overrides current when Viper started, logging to [log].
  ViperHttpOverrides(this.previous, this.log);

  /// What was there before, kept in the chain.
  final HttpOverrides? previous;

  /// Where the calls go.
  final ActivityLog log;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = previous?.createHttpClient(context) ?? super.createHttpClient(context);
    return ViperHttpClient(inner, log);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      previous?.findProxyFromEnvironment(url, environment) ?? super.findProxyFromEnvironment(url, environment);
}

/// An HttpClient that notes each call and forwards everything else to the one it wraps.
class ViperHttpClient implements HttpClient {
  /// Wraps [inner].
  ViperHttpClient(this.inner, this.log);

  /// The client doing the work.
  final HttpClient inner;

  /// Where the calls go.
  final ActivityLog log;

  Future<HttpClientRequest> _note(String method, Uri url, Future<HttpClientRequest> Function() open) async {
    final call = log.start(method, url);
    final watch = Stopwatch()..start();
    final HttpClientRequest request;
    try {
      request = await open();
    } catch (error) {
      call
        ..duration = watch.elapsed
        ..error = _short(error);
      rethrow;
    }
    // The answer arrives on `done`, the same future close() returns; listening changes nothing.
    unawaited(
      request.done.then(
        (response) {
          if (request.headers.value(clientHeaderName) != null) {
            log.forget(call);
            return;
          }
          call
            ..status = response.statusCode
            ..duration = watch.elapsed
            ..requestId = _requestId(response.headers);
        },
        onError: (Object error) {
          if (request.headers.value(clientHeaderName) != null) {
            log.forget(call);
            return;
          }
          call
            ..duration = watch.elapsed
            ..error = _short(error);
        },
      ),
    );
    return request;
  }

  static String? _requestId(HttpHeaders headers) {
    for (final name in requestIdHeaders) {
      final value = headers.value(name);
      if (value != null && value.isNotEmpty) return value.length > 200 ? value.substring(0, 200) : value;
    }
    return null;
  }

  static String _short(Object error) {
    final text = error is SocketException
        ? 'SocketException: ${error.message}'
        : error is HandshakeException
        ? 'HandshakeException: ${error.message}'
        : error.runtimeType.toString();
    return text.length > 200 ? text.substring(0, 200) : text;
  }

  Uri _uri(String host, int port, String path) {
    final query = path.indexOf('?');
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: query < 0 ? path : path.substring(0, query),
      query: query < 0 ? null : path.substring(query + 1),
    );
  }

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _note(method, _uri(host, port, path), () => inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _note(method, url, () => inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _note('GET', _uri(host, port, path), () => inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _note('GET', url, () => inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _note('POST', _uri(host, port, path), () => inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _note('POST', url, () => inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _note('PUT', _uri(host, port, path), () => inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _note('PUT', url, () => inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _note('DELETE', _uri(host, port, path), () => inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _note('DELETE', url, () => inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _note('PATCH', _uri(host, port, path), () => inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _note('PATCH', url, () => inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _note('HEAD', _uri(host, port, path), () => inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _note('HEAD', url, () => inner.headUrl(url));

  // Everything else is the wrapped client's, untouched.

  @override
  bool get autoUncompress => inner.autoUncompress;

  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => inner.userAgent;

  @override
  set userAgent(String? value) => inner.userAgent = value;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) => inner.authenticate = f;

  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      inner.authenticateProxy = f;

  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      inner.badCertificateCallback = callback;

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) =>
      inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => inner.keyLog = callback;

  @override
  void close({bool force = false}) => inner.close(force: force);
}
