// The package's own calls to Viper (D329). A phone sends no Origin, so each call carries the
// environment key with the app's ID and platform, which Viper matches against the environment's
// trusted app IDs. Every call also names the package with the implementation's marker (D336), so
// the marker string is in any build that can run Viper and in none that can't.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The implementation's marker (D336). The pilot's artifact check greps a production build's
/// `libapp.so` and `App.framework` for it and refuses the build if it's there. It's sent on every
/// call the package makes, so tree shaking keeps it wherever `Viper.start` can run.
const String implementationMarker = 'viper-flutter-implementation';

/// This package's version, as `pubspec.yaml` says.
const String packageVersion = '0.1.0';

/// The `X-Viper-Client` header: the marker and the version.
const String clientHeader = '$implementationMarker/$packageVersion';

/// The header that marks Viper's own requests, so the network log leaves them out (D333).
const String clientHeaderName = 'X-Viper-Client';

/// How a config call came out.
sealed class ConfigOutcome {
  const ConfigOutcome();
}

/// Viper said yes: the config, as JSON, passed to the panel as it came.
final class ConfigOk extends ConfigOutcome {
  /// The config.
  const ConfigOk(this.config);

  /// `WidgetConfigOk` from the protocol.
  final Map<String, Object?> config;
}

/// Viper said no, readably (D82): an unknown key, an untrusted app, a switched-off environment.
final class ConfigRefused extends ConfigOutcome {
  /// The refusal.
  const ConfigRefused(this.reason);

  /// `ConfigRefusal` from the protocol.
  final String reason;
}

/// Viper didn't answer, or answered something unreadable. Nothing is captured; the call is tried
/// again later.
final class ConfigUnreachable extends ConfigOutcome {
  /// Why.
  const ConfigUnreachable(this.message);

  /// What went wrong, for the log.
  final String message;
}

/// The calls the package makes itself. The panel makes every call that needs a person's
/// credentials (D131); these need only the key.
abstract interface class ViperApi {
  /// GET /widget/config (D82).
  Future<ConfigOutcome> config();

  /// Closes the client.
  void close();
}

/// The headers on every call the package makes (D329, D336).
Map<String, String> viperHeaders({required String key, required String appId}) => {
  'Accept': 'application/json',
  'X-Viper-Key': key,
  'X-Viper-Platform': 'flutter',
  'X-Viper-App': appId,
  clientHeaderName: clientHeader,
};

/// [ViperApi] over `dart:io`.
class HttpViperApi implements ViperApi {
  /// Calls [host] with [key] for the app [appId].
  HttpViperApi({required this.host, required this.key, required this.appId, HttpClient? client})
    : _client = client ?? HttpClient();

  /// Viper's base URL.
  final Uri host;

  /// The environment's widget key.
  final String key;

  /// The bundle or application ID.
  final String appId;

  final HttpClient _client;

  /// How long a call may take before it counts as unreachable.
  static const Duration timeout = Duration(seconds: 15);

  Uri _url(String path, [Map<String, String> query = const {}]) =>
      host.replace(path: '${host.path.replaceAll(RegExp(r'/$'), '')}$path', queryParameters: {'key': key, ...query});

  @override
  Future<ConfigOutcome> config() async {
    try {
      final request = await _client.getUrl(_url('/widget/config')).timeout(timeout);
      viperHeaders(key: key, appId: appId).forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      final Object? json;
      try {
        json = jsonDecode(body);
      } on FormatException {
        // Anything unreadable is a refusal too, as on the web: nothing is captured (D82).
        return response.statusCode == 404
            ? const ConfigRefused('unknown_key')
            : ConfigUnreachable('Viper answered ${response.statusCode}');
      }
      if (json is! Map<String, Object?>) return ConfigUnreachable('Viper answered ${response.statusCode}');
      if (json['ok'] == true) return ConfigOk(json);
      final reason = json['reason'];
      return ConfigRefused(reason is String ? reason : 'unknown_key');
    } on TimeoutException {
      return const ConfigUnreachable('timed out');
    } on IOException catch (error) {
      return ConfigUnreachable('$error');
    }
  }

  @override
  void close() => _client.close(force: true);
}
