// Viper running in the app: Dart's half of the bridge (D328). It asks Viper for its config, keeps
// the panel's web view, answers every message the panel sends (the table in flutter.md), and tells
// the panel what it needs to know about the app.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/device.dart';
import 'package:viper_flutter/src/core/environment.dart';
import 'package:viper_flutter/src/core/opener.dart';
import 'package:viper_flutter/src/core/placement.dart';
import 'package:viper_flutter/src/core/screens.dart';
import 'package:viper_flutter/src/core/store.dart';
import 'package:viper_flutter/src/slots.dart';
import 'package:viper_flutter/src/ui/host.dart';
import 'package:viper_flutter/src/ui/panel_view.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// Where Viper is in its life.
enum ViperPhase {
  /// Asking the phone and Viper.
  starting,

  /// Below iOS 16.4 or Android API 24 (D338): nothing runs.
  unsupported,

  /// Viper refused the key, the app or the environment (D82, D329).
  refused,

  /// Viper didn't answer; asked again later.
  unreachable,

  /// Running: the launcher shows.
  ready,

  /// Switched off by the kill switch while running (D99).
  off,
}

/// Writes a line to the device's log, outside the app's zone so it never lands in a capture.
typedef ViperLog = void Function(String line);

void _rootLog(String line) => Zone.root.print('Viper: $line');

/// Everything the runtime reaches outside itself, so tests can stand in for each.
class ViperServices {
  /// The services; the defaults are the real ones.
  ViperServices({
    ViperApi Function(DeviceFacts facts)? api,
    ViperDevice? device,
    ViperStore? store,
    PanelViewFactory? panelView,
    ViperOpener? opener,
    DateTime Function()? clock,
    ViperLog? log,
    ui.FlutterView Function()? view,
    String Function(DateTime now)? timezone,
  }) : device = device ?? PluginDevice(),
       store = store ?? PreferencesStore(),
       panelView = panelView ?? webPanelView,
       opener = opener ?? const LauncherOpener(),
       clock = clock ?? DateTime.now,
       log = log ?? _rootLog,
       view =
           view ??
           (() =>
               WidgetsBinding.instance.platformDispatcher.implicitView ??
               WidgetsBinding.instance.platformDispatcher.views.first),
       timezone = timezone ?? dartTimezone,
       _api = api;

  final ViperApi Function(DeviceFacts facts)? _api;

  /// The phone and the app.
  final ViperDevice device;

  /// What's kept on the phone.
  final ViperStore store;

  /// Makes the panel's web view.
  final PanelViewFactory panelView;

  /// Opens links outside the panel.
  final ViperOpener opener;

  /// Now.
  final DateTime Function() clock;

  /// The device log.
  final ViperLog log;

  /// The app's view.
  final ui.FlutterView Function() view;

  /// The phone's time zone.
  final String Function(DateTime now) timezone;

  /// The API for an app, once its ID is known.
  ViperApi api(Uri host, String key, DeviceFacts facts) =>
      _api?.call(facts) ?? HttpViperApi(host: host, key: key, appId: facts.appId);
}

/// Viper running in the app.
class ViperRuntime extends ChangeNotifier with WidgetsBindingObserver implements ViperSlotHandler {
  /// Viper for the environment [key] on [host].
  ViperRuntime({
    required this.key,
    required this.host,
    this.identityCallback,
    this.contextCallback,
    ViperServices? services,
    ScreenTracker? screens,
    Duration Function()? uptime,
  }) : services = services ?? ViperServices(),
       screens = screens ?? ScreenTracker(),
       _uptime = uptime;

  /// The staging environment's widget key.
  final String key;

  /// Viper's base URL.
  final Uri host;

  /// Asks the app's backend for a signed identity (D21, D86).
  final Future<SignedIdentity?> Function()? identityCallback;

  /// What the app adds to each capture, beside `Viper.context` (D27).
  final Map<String, Object?> Function()? contextCallback;

  /// Everything outside the runtime.
  final ViperServices services;

  /// Where the person is.
  final ScreenTracker screens;

  final Stopwatch _clock = Stopwatch()..start();
  final Duration Function()? _uptime;

  /// Where Viper is in its life.
  ViperPhase phase = ViperPhase.starting;

  /// The phone and the app, once read.
  DeviceFacts? facts;

  /// The config, once Viper said yes.
  Map<String, Object?>? config;

  /// Why Viper said no.
  String? refusal;

  ViperApi? _api;
  bool _asking = false;
  Timer? _retry;
  int _attempts = 0;

  /// The panel's web view, made once the config says ok and kept for the life of the app.
  PanelView? panel;

  /// The panel said viper:ready.
  bool panelReady = false;

  /// The panel's page didn't load.
  bool loadFailed = false;

  /// The panel's last state (D108), kept in memory and on the phone.
  Map<String, Object?> panelState = <String, Object?>{};

  /// The sheet is up.
  bool sheetOpen = false;

  /// The viewer is staff (viper:viewer).
  bool staff = false;

  /// The theme the panel chose (D279): system, light or dark.
  String theme = 'system';

  /// What the launcher shows (viper:count).
  int openCount = 0;

  /// How many need the viewer.
  int needsYou = 0;

  /// The project's placement (D295).
  ProjectPlacement project = const ProjectPlacement();

  /// Where the launcher is now (D335).
  LauncherLayout layout = LauncherLayout.fromProject(const ProjectPlacement());

  /// Whether a shake can bring Viper back, so hiding is offered (D335).
  bool shakeAvailable = false;

  /// A short note on screen, such as how to bring a hidden Viper back.
  String? toast;
  Timer? _toastTimer;

  SignedIdentity? _identity;
  final Map<String, Object?> _context = <String, Object?>{};
  Map<String, Object?>? _screen;
  Timer? _stateWrite;
  int? _tapAt;
  int? _panelMadeAt;

  String get _launcherKey => 'viper.$key.launcher';
  String get _stateKey => 'viper.$key.panel_state';
  String get _themeKey => 'viper.$key.theme';

  /// Viper's origin, for what the panel may open in the sign-in view.
  Uri get origin => host.replace(path: '', query: null, fragment: null);

  /// The theme's colors now.
  ViperPalette get palette => ViperPalette.of(theme, services.view().platformDispatcher.platformBrightness);

  /// Starts Viper: reads the phone, asks Viper, and loads the panel. Never awaited by the app.
  Future<void> boot() async {
    WidgetsBinding.instance.addObserver(this);
    _takePending();
    try {
      facts = await services.device.facts();
    } catch (error) {
      services.log('could not read the device ($error); Viper is off');
      _setPhase(ViperPhase.unsupported);
      return;
    }
    if (!facts!.supported) {
      services.log('${facts!.unsupportedReason}; Viper is off and the app runs as normal');
      _setPhase(ViperPhase.unsupported);
      return;
    }
    theme = await services.store.read(_themeKey) ?? 'system';
    final kept = await services.store.readJson(_stateKey);
    if (kept != null) panelState = kept;
    _api = services.api(host, key, facts!);
    await _askConfig();
  }

  void _takePending() {
    if (ViperSlots.identityPending) {
      _identity = ViperSlots.pendingIdentity;
      ViperSlots.identityPending = false;
      ViperSlots.pendingIdentity = null;
    }
    _context.addAll(ViperSlots.pendingContext);
    ViperSlots.pendingContext.clear();
  }

  Future<void> _askConfig() async {
    // One call at a time: a resume while the retry's call is still out waits for its answer, so
    // two answers can never make two panels.
    if (phase == ViperPhase.off || phase == ViperPhase.ready || _asking) return;
    _asking = true;
    _attempts++;
    final ConfigOutcome outcome;
    try {
      outcome = await _api!.config();
    } finally {
      _asking = false;
    }
    if (phase == ViperPhase.off || phase == ViperPhase.ready) return;
    switch (outcome) {
      case ConfigOk(:final config):
        await _start(config);
      case ConfigRefused(:final reason):
        refusal = reason;
        services.log('Viper refused this app ($reason); nothing is captured');
        _setPhase(ViperPhase.refused);
      case ConfigUnreachable(:final message):
        services.log('Viper could not be reached ($message); trying again');
        _setPhase(ViperPhase.unreachable);
        _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    const waits = [5, 15, 60, 300];
    final wait = waits[(_attempts - 1).clamp(0, waits.length - 1)];
    _retry = Timer(Duration(seconds: wait), () => unawaited(_askConfig()));
  }

  Future<void> _start(Map<String, Object?> ok) async {
    if (panel != null) return;
    config = ok;
    project = ProjectPlacement.fromJson(ok['launcher']);
    layout = LauncherLayout.restore(await services.store.readJson(_launcherKey), project);
    final urls = ok['urls'];
    final panelUrl = urls is Map && urls['panel'] is String ? Uri.tryParse(urls['panel'] as String) : null;
    if (panelUrl == null) {
      services.log('the config has no panel URL; Viper is off');
      _setPhase(ViperPhase.refused);
      return;
    }
    _panelMadeAt = _clock.elapsedMilliseconds;
    panel = services.panelView(
      base: panelUrl,
      onMessage: receive,
      onExternal: (url) => unawaited(services.opener.openExternal(url)),
      onLoadError: _loadFailed,
      background: palette.surface,
    );
    unawaited(panel!.load(bridgeUrl(panelUrl)));
    _setPhase(ViperPhase.ready);
    _screen = screens.current(build: facts?.build);
    if (_identity == null && identityCallback != null) unawaited(_fetchIdentity());
  }

  /// The panel's URL in bridge mode (flutter.md, the bridge).
  static Uri bridgeUrl(Uri panelUrl) =>
      panelUrl.replace(queryParameters: {...panelUrl.queryParameters, 'bridge': 'native'});

  Future<void> _fetchIdentity() async {
    try {
      final signed = await identityCallback!();
      if (signed != null) identify(signed);
    } catch (error) {
      services.log('the identity callback failed ($error)');
    }
  }

  void _loadFailed(String description) {
    if (panelReady) return;
    services.log('the panel did not load ($description)');
    loadFailed = true;
    notifyListeners();
  }

  /// Tries the panel's page again after it failed to load.
  Future<void> retryLoad() async {
    loadFailed = false;
    notifyListeners();
    await panel?.reload();
  }

  void _setPhase(ViperPhase next) {
    phase = next;
    notifyListeners();
  }

  // -------------------------------------------------------------------------------------------
  // The sheet and the launcher
  // -------------------------------------------------------------------------------------------

  /// Opens the sheet from the launcher (or a shake).
  void openSheet() {
    if (phase != ViperPhase.ready || sheetOpen) return;
    sheetOpen = true;
    _tapAt = _clock.elapsedMilliseconds;
    if (panelReady) {
      // The pilot's first measure: with the kept web view the panel is there at the tap.
      services.log('launcher tapped; the panel was already ready (kept web view, 0 ms)');
      _sendViewport();
    }
    notifyListeners();
  }

  /// Closes the sheet back to the launcher.
  void closeSheet() {
    if (!sheetOpen) return;
    sheetOpen = false;
    _tapAt = null;
    notifyListeners();
  }

  /// The person dragged the button to [spot], or the tab along its edge.
  void moveLauncher(LauncherLayout next) {
    layout = next.copyWith(moved: true);
    unawaited(services.store.writeJson(_launcherKey, layout.toJson()));
    notifyListeners();
  }

  /// Tucks the button to an edge tab, or brings the round button back.
  void setTucked(bool tucked) {
    final side = layout.spot.endsWith('left') || layout.spot == 'left' ? 'left' : 'right';
    moveLauncher(layout.copyWith(tucked: tucked, edgeSide: tucked ? side : layout.edgeSide));
  }

  /// Hides Viper until a shake brings it back (D335), or shows it again.
  void setHidden(bool hidden) {
    layout = layout.copyWith(hidden: hidden);
    unawaited(services.store.writeJson(_launcherKey, layout.toJson()));
    if (hidden) closeSheet();
    notifyListeners();
  }

  /// Shows [text] at the bottom of the screen for a few seconds.
  void showToast(String text) {
    toast = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // -------------------------------------------------------------------------------------------
  // The bridge (flutter.md): the panel posts JSON through ViperBridge; Dart answers by calling
  // window.viperReceive with the message.
  // -------------------------------------------------------------------------------------------

  /// The script that hands [message] to the panel.
  static String script(Map<String, Object?> message) =>
      'window.viperReceive && window.viperReceive(${jsonEncode(message)});';

  /// Sends [message] to the panel, once it's ready.
  void send(Map<String, Object?> message) {
    final view = panel;
    if (view == null || !panelReady || phase != ViperPhase.ready) return;
    unawaited(
      view.run(script(message)).catchError((Object error) => services.log('could not reach the panel ($error)')),
    );
  }

  /// A message from the panel, as the JSON it posted.
  void receive(String raw) {
    final Object? message;
    try {
      message = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (!isViperMessage(message)) return;
    unawaited(handle(message as Map<String, Object?>));
  }

  /// The same test the panel and the loader use: an object whose type starts with `viper:`.
  static bool isViperMessage(Object? data) =>
      data is Map && data['type'] is String && (data['type'] as String).startsWith('viper:');

  /// Answers one panel message (the table in flutter.md).
  Future<void> handle(Map<String, Object?> message) async {
    if (phase == ViperPhase.off) return;
    switch (message['type']) {
      case 'viper:ready':
        _onReady();
      case 'viper:state':
        final state = message['state'];
        if (state is Map<String, Object?>) _keepState(state);
      case 'viper:viewer':
        staff = message['staff'] == true;
      case 'viper:theme':
        final next = message['theme'];
        if (next is String && const {'system', 'light', 'dark'}.contains(next) && next != theme) {
          theme = next;
          unawaited(services.store.write(_themeKey, next));
          notifyListeners();
        }
      case 'viper:count':
        openCount = _int(message['open']);
        needsYou = _int(message['needs_you']);
        notifyListeners();
      case 'viper:launcher':
        project = ProjectPlacement.fromJson(message['launcher']);
        // A launcher nobody moved goes where the project now starts it (D295).
        if (!layout.moved) layout = LauncherLayout.fromProject(project, hidden: layout.hidden);
        notifyListeners();
      case 'viper:close':
        closeSheet();
      case 'viper:collapse':
        if (message['collapsed'] == true) {
          closeSheet();
        } else {
          openSheet();
        }
      case 'viper:resize':
        // The sheet keeps the phone layout's height (D169); the panel scrolls inside it.
        break;
      case 'viper:off':
        _turnOff(message['reason'] is String ? message['reason'] as String : 'disabled');
      case 'viper:pick:start':
        _startPick(message['mode'] is String ? message['mode'] as String : 'element');
      case 'viper:pick:step':
        // Stepping up the pick's path comes with the element pick (slice 5).
        break;
      case 'viper:submit':
        await _submit(message);
      case 'viper:open':
        final url = Uri.tryParse(message['url'] is String ? message['url'] as String : '');
        if (url != null && const {'http', 'https', 'mailto'}.contains(url.scheme)) {
          await services.opener.openExternal(url);
        }
      case 'viper:open:auth':
        final url = Uri.tryParse(message['url'] is String ? message['url'] as String : '');
        // Only Viper's own sign-in page opens in the sign-in view (D334).
        if (url != null && url.scheme == host.scheme && url.host == host.host && url.port == host.port) {
          await services.opener.openAuth(url);
        }
      case 'viper:auth:done':
        await services.opener.closeAuth();
      case 'viper:highlight':
        // Outlining an item's widget comes with the pick (slice 6).
        break;
      case 'viper:exact:request':
        send({'type': 'viper:exact:status', 'granted': false, 'reason': 'unsupported'});
      default:
        // viper:pins is never answered, so nothing is marked missing; the overlay, docking,
        // dragging the panel, look-through, exact and live edits are web only (D337).
        break;
    }
  }

  void _onReady() {
    final first = !panelReady;
    panelReady = true;
    loadFailed = false;
    final now = _clock.elapsedMilliseconds;
    if (first && _panelMadeAt != null) {
      services.log('panel ready ${now - _panelMadeAt!} ms after the web view was made');
    }
    if (_tapAt != null) {
      services.log('launcher tap to viper:ready: ${now - _tapAt!} ms');
      _tapAt = null;
    }
    send(bridgeMessage());
    send({
      'type': 'viper:config',
      'config': config,
      'screen': _screen ?? screens.current(build: facts?.build),
      'state': panelState,
    });
    send({'type': 'viper:identity', 'identity': _identity});
    send(_layoutMessage());
    if (sheetOpen) _sendViewport();
    notifyListeners();
  }

  /// viper:bridge: what the panel needs to know about the app (flutter.md).
  Map<String, Object?> bridgeMessage() {
    final view = services.view();
    return {
      'type': 'viper:bridge',
      'platform': 'flutter',
      'app_id': facts?.appId ?? '',
      'os': facts?.os == 'Android' ? 'Android' : 'iOS',
      'shake': shakeAvailable && _shakeOn,
      'text_scale': roundForPayload(MediaQueryData.fromView(view).textScaler.scale(100) / 100),
    };
  }

  bool get _shakeOn {
    final projectConfig = config?['project'];
    return !(projectConfig is Map && projectConfig['shake_to_open'] == false);
  }

  Map<String, Object?> _layoutMessage() {
    final size = MediaQueryData.fromView(services.view()).size;
    return {
      'type': 'viper:layout',
      'docked': false,
      'side': 'right',
      'phone': true,
      'dock_offered': false,
      'app_width': size.width.round(),
    };
  }

  void _sendViewport() {
    final size = MediaQueryData.fromView(services.view()).size;
    send({'type': 'viper:viewport', 'width': size.width.round(), 'height': size.height.round(), 'phone': true});
  }

  void _keepState(Map<String, Object?> state) {
    panelState = state;
    _stateWrite?.cancel();
    _stateWrite = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(services.store.writeJson(_stateKey, panelState)),
    );
  }

  void _turnOff(String reason) {
    services.log('Viper was switched off ($reason)');
    refusal = reason;
    sheetOpen = false;
    _retry?.cancel();
    phase = ViperPhase.off;
    notifyListeners();
  }

  // -------------------------------------------------------------------------------------------
  // Picking and reporting. The whole screen is here; the element, box and dialog picks come in
  // slice 5, the picture in slice 2, masking in slice 3, console and network in slice 4.
  // -------------------------------------------------------------------------------------------

  void _startPick(String mode) {
    if (mode == 'screen') {
      final context = <String, Object?>{
        'path': [
          {'label': 'Whole screen'},
        ],
        'index': 0,
        'mode': 'screen',
      };
      send({'type': 'viper:pick:none', 'scope': 'screen', 'label': 'Whole screen', 'context': context});
      return;
    }
    send({'type': 'viper:pick:cancel'});
  }

  Future<void> _submit(Map<String, Object?> message) async {
    final report = message['report'];
    final clientId = message['client_id'];
    if (report is! Map<String, Object?>) return;
    try {
      final payload = await reportPayload(report);
      send({
        'type': 'viper:report',
        'payload': payload,
        'files': reportFiles(console: const [], network: const []),
        'client_id': ?clientId,
      });
    } catch (error) {
      send({
        'type': 'viper:save:failed',
        'message': "This app couldn't put the report together.",
        'client_id': ?clientId,
      });
      services.log('could not put the report together ($error)');
    }
  }

  /// The full ReportPayload for the panel's part of one (D330, flutter.md's protocol).
  Future<Map<String, Object?>> reportPayload(
    Map<String, Object?> report, {
    ScreenshotInfo screenshot = const ScreenshotInfo.none(),
  }) async {
    final project = config?['project'];
    final environment = config?['environment'];
    final now = services.clock();
    final env = deviceEnvironment(
      facts: facts!,
      view: services.view(),
      connection: await services.device.connection(),
      screenshot: screenshot,
      capturedAt: now,
      appOpen: _uptime?.call() ?? _clock.elapsed,
      timezone: services.timezone(now),
      app: AppDetails(
        environment: environment is Map && environment['kind'] is String ? environment['kind'] as String : null,
        userId: _identityId,
        context: {..._context, ...?_safeContext()},
      ),
    );
    final screen = screens.current(build: facts!.build);
    return {
      ...report,
      'key': key,
      'platform': 'flutter',
      'screen': screen,
      'env': env,
      'build': report['build'] ?? facts!.build,
      'privacy_level': project is Map && project['privacy_level'] is String ? project['privacy_level'] : 'standard',
      'asset_manifest': const <String, Object?>{},
      'assets_skipped': const <Object?>[],
    };
  }

  /// The report's files (D112). Over the bridge a file's body is its text: the panel makes the
  /// Blob it uploads (D342).
  static List<Map<String, Object?>> reportFiles({required List<Object?> console, required List<Object?> network}) => [
    {'field': 'console', 'filename': 'console.json', 'body': jsonEncode(console)},
    {'field': 'network', 'filename': 'network.json', 'body': jsonEncode(network)},
  ];

  String? get _identityId {
    final payload = _identity?['payload'];
    return payload is Map && payload['id'] != null ? '${payload['id']}' : null;
  }

  Map<String, Object?>? _safeContext() {
    try {
      return contextCallback?.call();
    } catch (error) {
      services.log('the context callback failed ($error)');
      return null;
    }
  }

  // -------------------------------------------------------------------------------------------
  // What shared code calls (markers.dart)
  // -------------------------------------------------------------------------------------------

  @override
  Widget wrap(Widget child) => ViperHost(runtime: this, child: child);

  @override
  void recordError(Object error, StackTrace? stack) {
    // Logged with the console in slice 4 (D333).
  }

  @override
  void identify(SignedIdentity? identity, {IdentityRefresh? refresh}) {
    _identity = identity;
    send({'type': 'viper:identity', 'identity': identity});
  }

  @override
  void context(Map<String, Object?> values) {
    values.forEach((key, value) => value == null ? _context.remove(key) : _context[key] = value);
  }

  @override
  void routesChanged(ViperNavigatorObserver observer) {
    // Read once the navigator has finished the change, never in the middle of it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (phase != ViperPhase.ready) return;
      final next = screens.current(build: facts?.build);
      if (_screen != null && next['route'] == _screen!['route']) return;
      _screen = next;
      send({'type': 'viper:navigate', 'screen': next});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  // -------------------------------------------------------------------------------------------
  // The app's life
  // -------------------------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (phase == ViperPhase.unreachable) {
        _retry?.cancel();
        unawaited(_askConfig());
      }
      // The panel reconnects its cable and refetches (D42).
      send({'type': 'viper:app:state', 'state': 'resumed'});
    } else if (state == AppLifecycleState.paused) {
      _stateWrite?.cancel();
      unawaited(services.store.writeJson(_stateKey, panelState));
      send({'type': 'viper:app:state', 'state': 'paused'});
    }
  }

  @override
  Future<bool> didPopRoute() async {
    // Android's back closes the sheet before it reaches the app's navigator.
    if (!sheetOpen) return false;
    closeSheet();
    return true;
  }

  @override
  void didChangeTextScaleFactor() => send(bridgeMessage());

  @override
  void didChangePlatformBrightness() => notifyListeners();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _stateWrite?.cancel();
    _toastTimer?.cancel();
    _api?.close();
    super.dispose();
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;
