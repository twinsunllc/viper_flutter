// The console and the network calls a report carries (D333): the last 200 lines and 100 calls,
// as on the web. Never request or response bodies (D78, D80); at Strict and above, console text
// is masked and queries are stripped.
import 'dart:convert';

import 'package:viper_flutter/src/core/mask.dart';

/// How many console lines are kept.
const int maxConsoleLines = 200;

/// How many calls are kept.
const int maxNetworkCalls = 100;

/// The longest console line kept.
const int maxConsoleText = 1000;

/// One console line.
class ConsoleLine {
  /// A line.
  const ConsoleLine(this.level, this.at, this.text);

  /// `error`, `warn`, `info` or `log`.
  final String level;

  /// When.
  final DateTime at;

  /// The words, at most [maxConsoleText] characters.
  final String text;
}

/// One network call.
class NetworkCall {
  /// A call.
  NetworkCall({required this.method, required this.url, required this.started});

  /// GET, POST.
  final String method;

  /// Where it went.
  final Uri url;

  /// When it started.
  final DateTime started;

  /// The answer's status; 0 when there was none.
  int status = 0;

  /// How long it took.
  Duration duration = Duration.zero;

  /// The request id the app's logs know it by (D78).
  String? requestId;

  /// Why it failed, when it did.
  String? error;
}

/// Response headers that carry a request id the app's logs or error tracker know (D78).
const List<String> requestIdHeaders = [
  'x-request-id',
  'x-correlation-id',
  'x-amzn-requestid',
  'x-amzn-trace-id',
  'request-id',
  'cf-ray',
  'x-trace-id',
];

/// The console and the network, kept in memory.
class ActivityLog {
  /// An empty log; [clock] says when.
  ActivityLog({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<ConsoleLine> _console = <ConsoleLine>[];
  final List<NetworkCall> _network = <NetworkCall>[];

  /// Off once Viper turns out not to run: nothing more is kept (D82, D338).
  bool enabled = true;

  /// Forgets everything and keeps nothing more.
  void stop() {
    enabled = false;
    _console.clear();
    _network.clear();
  }

  /// The lines kept, oldest first.
  List<ConsoleLine> get console => List.unmodifiable(_console);

  /// The calls kept, oldest first.
  List<NetworkCall> get network => List.unmodifiable(_network);

  /// Keeps a console line.
  void log(String level, String text) {
    if (!enabled) return;
    _console.add(ConsoleLine(level, _clock(), text.length > maxConsoleText ? text.substring(0, maxConsoleText) : text));
    if (_console.length > maxConsoleLines) _console.removeRange(0, _console.length - maxConsoleLines);
  }

  /// Starts a call; finish it by setting its status, duration or error.
  NetworkCall start(String method, Uri url) {
    final call = NetworkCall(method: method.toUpperCase(), url: url, started: _clock());
    if (!enabled) return call;
    _network.add(call);
    if (_network.length > maxNetworkCalls) _network.removeRange(0, _network.length - maxNetworkCalls);
    return call;
  }

  /// Forgets a call that turned out to be Viper's own (D109).
  void forget(NetworkCall call) => _network.remove(call);

  /// The console as the report sends it, `ConsoleEntry[]`, masked at Strict and above (D80).
  List<Map<String, Object?>> consoleEntries(PrivacyLevel level) => [
    for (final line in _console)
      {
        'level': line.level,
        'at_ms': line.at.millisecondsSinceEpoch,
        'text': level == PrivacyLevel.standard ? line.text : maskText(line.text),
      },
  ];

  /// The calls as the report sends them, `NetworkEntry[]`: queries stripped at Strict and above.
  List<Map<String, Object?>> networkEntries(PrivacyLevel level) => [
    for (final call in _network)
      if (call.status != 0 || call.error != null)
        {
          'method': call.method,
          'path': callPath(call.url, level),
          'status': call.status,
          'duration_ms': call.duration.inMilliseconds,
          // When it finished, for the full log's time order (D359, D368). A call with an error but
          // no duration yet reads as when it started.
          'at_ms': call.started.add(call.duration).millisecondsSinceEpoch,
          'request_id': ?call.requestId,
          'error': ?call.error,
        },
  ];
}

/// Every character but spaces masked, as the web masks console text (`maskString`).
String maskText(String text) => text.replaceAll(RegExp(r'\S'), '•');

/// Where a call went, as NetworkEntry says it: a phone has no origin of its own, so every call is
/// the origin and the path, with the query only at Standard (D80).
String callPath(Uri url, PrivacyLevel level) {
  final origin = url.hasAuthority ? '${url.scheme}://${url.authority}' : '';
  final path = url.path.isEmpty ? '/' : url.path;
  final query = level == PrivacyLevel.standard && url.hasQuery ? '?${url.query}' : '';
  return '$origin$path$query';
}

/// How much an app may add with Viper.context (D27): plenty for flags and ids, never a data dump.
const int maxContextKeys = 40;

/// The longest value, as JSON.
const int maxContextValue = 1000;

/// The most in all, as JSON.
const int maxContextTotal = 8000;

/// Merges [values] into [current] as the web's `mergeContext` does: JSON values only, null
/// removes a key, and what doesn't fit is dropped.
Map<String, Object?> mergeContext(Map<String, Object?> current, Map<String, Object?> values) {
  final next = Map<String, Object?>.of(current);
  values.forEach((key, value) {
    if (value == null) {
      next.remove(key);
      return;
    }
    String json;
    try {
      json = jsonEncode(value);
    } on JsonUnsupportedObjectError {
      return;
    }
    if (json.length > maxContextValue || key.length > 100) return;
    if (!next.containsKey(key) && next.length >= maxContextKeys) return;
    next[key] = jsonDecode(json);
  });
  while (next.isNotEmpty && jsonEncode(next).length > maxContextTotal) {
    next.remove(next.keys.last);
  }
  return next;
}
