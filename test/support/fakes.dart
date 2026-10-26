// Stand-ins for what the runtime reaches outside itself, and the fixture writer (D340).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/device.dart';
import 'package:viper_flutter/src/core/opener.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/core/store.dart';
import 'package:viper_flutter/src/ui/panel_view.dart';

/// An iPhone on iOS 26, the example app.
const DeviceFacts iphone = DeviceFacts(
  os: 'iOS',
  osVersion: '26.1',
  model: 'iPhone 16',
  manufacturer: 'Apple',
  physical: true,
  appId: 'dev.twinsun.viper.example',
  build: '0.1.0+1',
);

/// A Pixel on Android 16.
const DeviceFacts pixel = DeviceFacts(
  os: 'Android',
  osVersion: '16',
  sdkInt: 36,
  model: 'Pixel 9 Pro',
  manufacturer: 'Google',
  physical: false,
  appId: 'dev.twinsun.viper.example',
  build: '0.1.0+1',
);

/// The config Viper answers for the example app's staging environment.
Map<String, Object?> exampleConfig({Map<String, Object?>? launcher, String privacy = 'standard'}) => {
  'ok': true,
  'environment': {'id': '6c1d1d3e-8b7a-4e39-9a51-1f3c2b0d9e01', 'kind': 'staging', 'name': 'Staging'},
  'project': {
    'id': '0f6f2f0a-5a2e-4b8e-9a53-2f5d0c7b1e22',
    'name': 'Viper example',
    'slug': 'viper-example',
    'privacy_level': privacy,
    'modules_enabled': true,
    'sign_off_enabled': true,
    'docked_allowed': false,
    'shake_to_open': true,
  },
  'launcher':
      launcher ?? {'style': 'corner', 'spot': 'bottom-right', 'raise': 0, 'edge_side': 'right', 'edge_position': 50},
  'build': null,
  'capture': {
    'replay_seconds': 60,
    'exact_screenshots': false,
    'mask_selectors': <String>[],
    'block_selectors': <String>[],
    'unmask_selectors': <String>[],
  },
  'urls': {
    'panel': 'http://localhost:4830/panel?key=hbr_loc_9w',
    'cable': 'ws://localhost:4830/cable',
    'sign_in_popup': 'http://localhost:4830/widget/sign_in',
    'privacy': 'http://localhost:4830/privacy',
  },
  'capture_notice': {'version': 1, 'summary': 'Viper captures the screen when you report.'},
};

/// A [ViperApi] that answers what it's given.
class FakeApi implements ViperApi {
  /// Answers [outcome] to every config call.
  FakeApi(this.outcome);

  /// What the config call answers.
  ConfigOutcome outcome;

  /// How many times config was asked.
  int calls = 0;

  /// When set, config waits for it before answering.
  Completer<void>? gate;

  @override
  Future<ConfigOutcome> config() async {
    calls++;
    await gate?.future;
    return outcome;
  }

  @override
  void close() {}
}

/// A [ViperDevice] with fixed facts.
class FakeDevice implements ViperDevice {
  /// The phone [facts].
  FakeDevice([this.info = iphone]);

  /// What it says.
  final DeviceFacts info;

  @override
  Future<DeviceFacts> facts() async => info;

  @override
  Future<String> connection() async => 'wifi';
}

/// A [PanelView] that records what Dart ran in it.
class FakePanelView implements PanelView {
  /// A panel for [base].
  FakePanelView(this.base, this.onMessage);

  /// Viper's base URL.
  final Uri base;

  /// Where the panel's messages go.
  final void Function(String message) onMessage;

  /// What it was told to load.
  final List<Uri> loaded = [];

  /// Every script run in it.
  final List<String> scripts = [];

  /// How many times it was reloaded.
  int reloads = 0;

  /// The messages Dart sent, decoded from the scripts.
  List<Map<String, Object?>> get sent => [for (final script in scripts) decodeScript(script)];

  /// The messages of [type] Dart sent.
  List<Map<String, Object?>> of(String type) => sent.where((m) => m['type'] == type).toList();

  /// The panel posts [message].
  void post(Map<String, Object?> message) => onMessage(jsonEncode(message));

  @override
  Future<void> load(Uri url) async => loaded.add(url);

  @override
  Future<void> run(String javascript) async => scripts.add(javascript);

  @override
  Future<void> reload() async => reloads++;

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFFFFFFF), child: SizedBox.expand());
}

/// The message inside `window.viperReceive && window.viperReceive(<json>);`.
Map<String, Object?> decodeScript(String script) {
  const head = 'window.viperReceive && window.viperReceive(';
  expect(script.startsWith(head), isTrue, reason: script);
  expect(script.endsWith(');'), isTrue, reason: script);
  return jsonDecode(script.substring(head.length, script.length - 2)) as Map<String, Object?>;
}

/// A [ViperOpener] that records.
class FakeOpener implements ViperOpener {
  /// Links opened in the system browser.
  final List<Uri> external = [];

  /// Sign-in pages opened.
  final List<Uri> auth = [];

  /// Times the sign-in view was closed.
  int closed = 0;

  @override
  Future<void> openExternal(Uri url) async => external.add(url);

  @override
  Future<void> openAuth(Uri url) async => auth.add(url);

  @override
  Future<void> closeAuth() async => closed++;
}

/// Everything a test runtime needs, and handles on each.
class Harness {
  /// A harness answering [outcome], on [device].
  Harness({ConfigOutcome? outcome, DeviceFacts device = iphone, MemoryStore? store, required this.view})
    : api = FakeApi(outcome ?? ConfigOk(exampleConfig())),
      store = store ?? MemoryStore(),
      device = FakeDevice(device);

  /// The view the runtime measures.
  final TestFlutterView view;

  /// The API.
  final FakeApi api;

  /// The store.
  final MemoryStore store;

  /// The device.
  final FakeDevice device;

  /// The opener.
  final FakeOpener opener = FakeOpener();

  /// The log.
  final List<String> log = [];

  /// The panel, once made.
  FakePanelView? panel;

  /// How many panels were made.
  int panelsMade = 0;

  /// A fixed now: Monday, October 26, 2026, 9:00 a.m. HST.
  static final DateTime now = DateTime.utc(2026, 10, 26, 19);

  /// The runtime for key `hbr_loc_9w` on the local Viper.
  ViperRuntime runtime() => ViperRuntime(
    key: 'hbr_loc_9w',
    host: Uri.parse('http://localhost:4830'),
    uptime: () => const Duration(seconds: 42),
    services: ViperServices(
      api: (_) => api,
      device: device,
      store: store,
      opener: opener,
      clock: () => now,
      log: log.add,
      view: () => view,
      timezone: (_) => 'Pacific/Honolulu',
      panelView: ({required base, required onMessage, required onExternal, required onLoadError, required background}) {
        panelsMade++;
        return panel = FakePanelView(base, onMessage);
      },
    ),
  );
}

/// Writes [json] to `test/fixtures/<schema>/<name>.json` (D340): the JSON the package sends,
/// validated against the protocol's schema of that name. Written only when it changed, so CI
/// can fail on a fixture that changed and wasn't committed.
void writeFixture(String schema, String name, Object? json) {
  final file = File('test/fixtures/$schema/$name.json');
  final text = '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  if (file.existsSync() && file.readAsStringSync() == text) return;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

/// Variations on the fixed phones.
extension DeviceFactsCopy on DeviceFacts {
  /// The same phone on OS [version].
  DeviceFacts copyWithVersion(String version) => DeviceFacts(
    os: os,
    osVersion: version,
    sdkInt: sdkInt,
    model: model,
    manufacturer: manufacturer,
    physical: physical,
    appId: appId,
    build: build,
  );

  /// The same Android phone on API [sdk].
  DeviceFacts copyWithSdk(int sdk) => DeviceFacts(
    os: os,
    osVersion: osVersion,
    sdkInt: sdk,
    model: model,
    manufacturer: manufacturer,
    physical: physical,
    appId: appId,
    build: build,
  );
}
