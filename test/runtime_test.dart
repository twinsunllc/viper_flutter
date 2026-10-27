// Viper's start and the bridge's message table (flutter.md), from Dart's side.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/environment.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/core/store.dart';
import 'package:viper_flutter/src/slots.dart';

import 'support/fakes.dart';

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
}

Future<(Harness, ViperRuntime)> started(WidgetTester tester, {Harness? harness}) async {
  phone(tester);
  final h = harness ?? Harness(view: tester.view);
  final runtime = h.runtime();
  addTearDown(runtime.dispose);
  await runtime.boot();
  // Let what boot started without waiting (the shake listener) settle.
  await tester.pump();
  return (h, runtime);
}

Future<void> ready(WidgetTester tester, Harness h) async {
  h.panel!.post({'type': 'viper:ready'});
  await tester.pump();
}

void main() {
  group('start', () {
    testWidgets('below iOS 16.4 does nothing and never calls Viper (D338)', (tester) async {
      phone(tester);
      final h = Harness(view: tester.view, device: iphone.copyWithVersion('16.3.1'));
      final runtime = h.runtime();
      addTearDown(runtime.dispose);
      await runtime.boot();
      expect(runtime.phase, ViperPhase.unsupported);
      expect(h.api.calls, 0);
      expect(h.panel, isNull);
      expect(h.log.single, contains('iOS 16.3.1 is below 16.4'));
    });

    testWidgets('below Android API 24 does nothing (D338)', (tester) async {
      phone(tester);
      final h = Harness(view: tester.view, device: pixel.copyWithSdk(23));
      final runtime = h.runtime();
      addTearDown(runtime.dispose);
      await runtime.boot();
      expect(runtime.phase, ViperPhase.unsupported);
      expect(h.api.calls, 0);
    });

    testWidgets('iOS 16.4 and Android API 24 run', (tester) async {
      for (final device in [iphone.copyWithVersion('16.4'), pixel.copyWithSdk(24)]) {
        final (h, runtime) = await started(
          tester,
          harness: Harness(view: tester.view, device: device),
        );
        expect(runtime.phase, ViperPhase.ready, reason: device.os);
        expect(h.api.calls, 1);
      }
    });

    testWidgets('a refusal shows nothing and records nothing (D82, D329)', (tester) async {
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, outcome: const ConfigRefused('untrusted_app')),
      );
      expect(runtime.phase, ViperPhase.refused);
      expect(runtime.refusal, 'untrusted_app');
      expect(h.panel, isNull);
    });

    testWidgets('unreachable tries again on resume', (tester) async {
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, outcome: const ConfigUnreachable('offline')),
      );
      expect(runtime.phase, ViperPhase.unreachable);
      h.api.outcome = ConfigOk(exampleConfig());
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(runtime.phase, ViperPhase.ready);
      expect(h.api.calls, 2);
    });

    testWidgets('a resume while a config call is out never makes a second panel', (tester) async {
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, outcome: const ConfigUnreachable('offline')),
      );
      h.api
        ..outcome = ConfigOk(exampleConfig())
        ..gate = Completer<void>();
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 6));
      expect(h.api.calls, 2, reason: 'one call out at a time, the retry timer included');
      h.api.gate!.complete();
      await tester.pump();
      expect(runtime.phase, ViperPhase.ready);
      expect(h.panelsMade, 1);
    });

    testWidgets('loads the panel in bridge mode once, hidden, at the config ok', (tester) async {
      final (h, runtime) = await started(tester);
      expect(runtime.phase, ViperPhase.ready);
      expect(runtime.sheetOpen, isFalse);
      expect(h.panel!.loaded, [Uri.parse('http://localhost:4830/panel?key=hbr_loc_9w&bridge=native')]);
    });
  });

  group('the bridge', () {
    testWidgets('sends nothing before viper:ready', (tester) async {
      final (h, runtime) = await started(tester);
      runtime.send({'type': 'viper:pick:cancel'});
      expect(h.panel!.scripts, isEmpty);
    });

    testWidgets('viper:ready gets the bridge, the config with the kept state, the identity and the layout', (
      tester,
    ) async {
      final store = MemoryStore({
        'viper.hbr_loc_9w.panel_state': '{"view":"compose","draft":{"body":"Save is grey","scope":"screen"}}',
      });
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, store: store),
      );
      await ready(tester, h);
      final sent = h.panel!.sent;
      expect(sent.map((m) => m['type']), ['viper:bridge', 'viper:config', 'viper:identity', 'viper:layout']);
      expect(sent[0], {
        'type': 'viper:bridge',
        'platform': 'flutter',
        'app_id': 'dev.twinsun.viper.example',
        'os': 'iOS',
        'shake': true,
        'text_scale': 1.0,
      });
      expect((sent[1]['state']! as Map)['view'], 'compose');
      expect(sent[1]['screen'], {'route': '/', 'url': '', 'title': 'Home', 'build': '0.1.0+1'});
      expect(sent[3], {
        'type': 'viper:layout',
        'docked': false,
        'side': 'right',
        'phone': true,
        'dock_offered': false,
        'app_width': 393,
      });
      for (final message in sent) {
        writeFixture('LoaderToPanelMessage', (message['type']! as String).substring('viper:'.length), message);
      }
    });

    testWidgets('a shake opens Viper, and shows it again when hidden (D335)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      expect(h.native.shaking, isTrue);
      runtime.setHidden(true);
      h.native.shake!();
      expect(runtime.layout.hidden, isFalse);
      expect(runtime.sheetOpen, isTrue);
    });

    testWidgets("the app's Viper.show brings a hidden launcher back, remembered per install (D371)", (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.setHidden(true);
      runtime.show();
      expect(runtime.layout.hidden, isFalse);
      expect(runtime.sheetOpen, isFalse);
      expect(await h.store.readJson('viper.hbr_loc_9w.launcher'), containsPair('hidden', false));
    });

    testWidgets("the app's Viper.open shows a hidden launcher and opens the sheet, never while picking (D371)", (
      tester,
    ) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.setHidden(true);
      runtime.open();
      expect(runtime.layout.hidden, isFalse);
      expect(runtime.sheetOpen, isTrue);
      runtime.picking = true;
      runtime.closeSheet();
      runtime.picking = true;
      runtime.open();
      expect(runtime.sheetOpen, isFalse, reason: 'picking, the sheet is the handle');
    });

    testWidgets('Viper.open called while Viper is still starting opens it once ready (D371)', (tester) async {
      phone(tester);
      final h = Harness(view: tester.view);
      final runtime = h.runtime();
      addTearDown(runtime.dispose);
      runtime.open();
      expect(runtime.sheetOpen, isFalse);
      await runtime.boot();
      await tester.pump();
      expect(runtime.phase, ViperPhase.ready);
      expect(runtime.sheetOpen, isTrue);
    });

    testWidgets("where Viper won't run, show and open do nothing (D338, D371)", (tester) async {
      phone(tester);
      final h = Harness(view: tester.view, device: iphone.copyWithVersion('16.3.1'));
      final runtime = h.runtime();
      addTearDown(runtime.dispose);
      await runtime.boot();
      runtime.show();
      runtime.open();
      expect(runtime.phase, ViperPhase.unsupported);
      expect(runtime.sheetOpen, isFalse);
      expect(await h.store.readJson('viper.hbr_loc_9w.launcher'), isNull);
    });

    testWidgets("a project with shake off never listens, and doesn't offer hiding (D335)", (tester) async {
      final config = exampleConfig();
      (config['project']! as Map)['shake_to_open'] = false;
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, outcome: ConfigOk(config)),
      );
      await ready(tester, h);
      expect(h.native.shaking, isFalse);
      expect(runtime.shakeAvailable, isFalse);
      expect(h.panel!.of('viper:bridge').single['shake'], isFalse);
    });

    testWidgets('viper:bridge says Android and its text scale', (tester) async {
      final (h, runtime) = await started(
        tester,
        harness: Harness(view: tester.view, device: pixel),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ready(tester, h);
      expect(h.panel!.of('viper:bridge').single, containsPair('os', 'Android'));
      expect(h.panel!.of('viper:bridge').single, containsPair('text_scale', 1.3));
    });

    testWidgets('ignores anything that is not a viper message', (tester) async {
      final (h, runtime) = await started(tester);
      h.panel!.onMessage('not json');
      h.panel!.onMessage('{"type":"other:ready"}');
      h.panel!.onMessage('[1,2]');
      await tester.pump();
      expect(runtime.panelReady, isFalse);
    });

    testWidgets('viper:state is kept in memory and on the phone (D108)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      h.panel!.post({
        'type': 'viper:state',
        'state': {'view': 'list', 'filter': 'mine'},
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(runtime.panelState, {'view': 'list', 'filter': 'mine'});
      expect(await h.store.readJson('viper.hbr_loc_9w.panel_state'), {'view': 'list', 'filter': 'mine'});
    });

    testWidgets('viper:count, viper:viewer and viper:theme reach the launcher', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      h.panel!.post({'type': 'viper:count', 'open': 5, 'needs_you': 1});
      h.panel!.post({'type': 'viper:viewer', 'staff': true});
      h.panel!.post({'type': 'viper:theme', 'theme': 'dark'});
      await tester.pump();
      expect((runtime.openCount, runtime.needsYou, runtime.staff, runtime.theme), (5, 1, true, 'dark'));
      expect(await h.store.read('viper.hbr_loc_9w.theme'), 'dark');
      expect(runtime.palette.dark, isTrue);
    });

    testWidgets('viper:launcher moves a launcher nobody moved, never one a person did (D295, D296)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      final edge = {'style': 'edge_tab', 'spot': 'bottom-right', 'raise': 0, 'edge_side': 'left', 'edge_position': 30};
      h.panel!.post({'type': 'viper:launcher', 'launcher': edge});
      await tester.pump();
      expect(runtime.layout.tucked, isTrue);
      expect(runtime.layout.edgeSide, 'left');
      runtime.moveLauncher(runtime.layout.copyWith(tucked: false, spot: 'top-left'));
      h.panel!.post({
        'type': 'viper:launcher',
        'launcher': {...edge, 'edge_side': 'right'},
      });
      await tester.pump();
      expect(runtime.layout.spot, 'top-left');
      expect(runtime.layout.tucked, isFalse);
    });

    testWidgets('viper:close and viper:collapse close and open the sheet; opening sends the viewport', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.openSheet();
      expect(runtime.sheetOpen, isTrue);
      final viewport = h.panel!.of('viper:viewport').single;
      expect(viewport, {'type': 'viper:viewport', 'width': 393, 'height': 852, 'phone': true});
      writeFixture('LoaderToPanelMessage', 'viewport', viewport);
      h.panel!.post({'type': 'viper:close'});
      await tester.pump();
      expect(runtime.sheetOpen, isFalse);
      h.panel!.post({'type': 'viper:collapse', 'collapsed': false});
      await tester.pump();
      expect(runtime.sheetOpen, isTrue);
      h.panel!.post({'type': 'viper:collapse', 'collapsed': true});
      await tester.pump();
      expect(runtime.sheetOpen, isFalse);
    });

    testWidgets('a tap before the panel is ready logs the time to viper:ready', (tester) async {
      final (h, runtime) = await started(tester);
      runtime.openSheet();
      await ready(tester, h);
      expect(h.log.where((line) => line.startsWith('launcher tap to viper:ready: ')), hasLength(1));
      expect(h.panel!.of('viper:viewport'), hasLength(1));
    });

    testWidgets('viper:off stops at once and hides the launcher (D99)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.openSheet();
      h.panel!.post({'type': 'viper:off', 'reason': 'disabled'});
      await tester.pump();
      expect(runtime.phase, ViperPhase.off);
      expect(runtime.sheetOpen, isFalse);
      final before = h.panel!.scripts.length;
      h.panel!.post({'type': 'viper:exact:request'});
      await tester.pump();
      expect(h.panel!.scripts, hasLength(before));
    });

    testWidgets('viper:exact:request is answered unsupported (D337)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      h.panel!.post({'type': 'viper:exact:request'});
      await tester.pump();
      final status = h.panel!.of('viper:exact:status').single;
      expect(status, {'type': 'viper:exact:status', 'granted': false, 'reason': 'unsupported'});
      writeFixture('LoaderToPanelMessage', 'exact_status', status);
    });

    testWidgets('viper:pins and the web-only messages are never answered', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      final before = h.panel!.scripts.length;
      for (final type in [
        'viper:pins',
        'viper:overlay',
        'viper:dock',
        'viper:panel:drag',
        'viper:lookthrough',
        'viper:exact:stop',
        'viper:preview:on',
        'viper:edit:start',
        'viper:resize',
      ]) {
        h.panel!.post({'type': type, 'items': <Object?>[]});
      }
      await tester.pump();
      expect(h.panel!.scripts, hasLength(before));
    });

    testWidgets('viper:open goes to the system browser; viper:open:auth only for Viper (D334)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      h.panel!.post({'type': 'viper:open', 'url': 'https://twinsun.atlassian.net/browse/WB-1'});
      h.panel!.post({'type': 'viper:open', 'url': 'javascript:alert(1)'});
      h.panel!.post({
        'type': 'viper:open:auth',
        'url': 'http://localhost:4830/widget/sign_in?key=hbr_loc_9w&app=dev.twinsun.viper.example',
      });
      h.panel!.post({'type': 'viper:open:auth', 'url': 'https://evil.example.com/sign_in'});
      h.panel!.post({'type': 'viper:auth:done'});
      await tester.pump();
      expect(h.opener.external, [Uri.parse('https://twinsun.atlassian.net/browse/WB-1')]);
      expect(h.opener.auth, [
        Uri.parse('http://localhost:4830/widget/sign_in?key=hbr_loc_9w&app=dev.twinsun.viper.example'),
      ]);
      expect(h.opener.closed, 1);
    });

    testWidgets('viper:pick:start for the whole screen answers viper:pick:none', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
      await tester.pump();
      final none = h.panel!.of('viper:pick:none').single;
      expect(none['label'], 'Whole screen');
      writeFixture('LoaderToPanelMessage', 'pick_none', none);
      h.panel!.post({'type': 'viper:pick:start', 'mode': 'element'});
      await tester.pump();
      expect(runtime.picking, isTrue);
      expect(await runtime.didPopRoute(), isFalse, reason: 'the sheet is closed, so back is the app\'s');
      runtime.openSheet();
      expect(await runtime.didPopRoute(), isTrue, reason: 'back while picking cancels the pick');
      expect(runtime.picking, isFalse);
      final cancel = h.panel!.of('viper:pick:cancel').single;
      writeFixture('LoaderToPanelMessage', 'pick_cancel', cancel);
    });

    testWidgets('viper:submit answers viper:report with the device environment (D330, D340)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.context({'plan': 'pro'});
      h.panel!.post({
        'type': 'viper:submit',
        'client_id': 'c-1',
        'report': {'scope': 'screen', 'body': 'The Save button stays grey'},
      });
      await tester.pump();
      await tester.pump();
      final report = h.panel!.of('viper:report').single;
      final payload = report['payload']! as Map<String, Object?>;
      expect(report['client_id'], 'c-1');
      expect(payload['platform'], 'flutter');
      expect(payload['key'], 'hbr_loc_9w');
      expect(payload['privacy_level'], 'standard');
      expect(payload['asset_manifest'], <String, Object?>{});
      expect(payload['assets_skipped'], <Object?>[]);
      final env = payload['env']! as Map<String, Object?>;
      expect(env['platform'], 'flutter');
      expect((env['app']! as Map)['context'], {'plan': 'pro'});
      expect((env['screen']! as Map)['logical'], {'width': 393.0, 'height': 852.0});
      // No app on screen in this test: no picture, and the capture says why (D338).
      expect(env['screenshot'], {'method': 'none', 'platform_views_blocked': false, 'blocked': 'failed'});
      expect(report['files'], [
        {'field': 'console', 'filename': 'console.json', 'body': '[]'},
        {'field': 'network', 'filename': 'network.json', 'body': '[]'},
      ]);
    });

    testWidgets('a build made with VIPER_COMMIT names its commit in the screen and the environment (D356)', (
      tester,
    ) async {
      phone(tester);
      final (h, _) = await started(
        tester,
        harness: Harness(view: tester.view, device: onCommit(iphone, '1.0.0+1', '4f2a9c1e8b7d')),
      );
      await ready(tester, h);
      final config = h.panel!.of('viper:config').single;
      expect(config['screen'], {
        'route': '/',
        'url': '',
        'title': 'Home',
        'build': '1.0.0+1',
        'commit': '4f2a9c1e8b7d',
      });
      final env = deviceEnvironment(
        facts: onCommit(iphone, '1.0.0+1', '4f2a9c1e8b7d'),
        view: tester.view,
        connection: 'wifi',
        screenshot: const ScreenshotInfo(method: 'native'),
        capturedAt: Harness.now,
        appOpen: const Duration(minutes: 1),
        timezone: 'America/Los_Angeles',
        app: const AppDetails(environment: 'staging'),
      );
      expect((env['app']! as Map)['commit'], '4f2a9c1e8b7d');
      expect((env['app']! as Map)['build'], '1.0.0+1');
    });

    testWidgets('the device environment of a capture taken natively on an iPhone (D27, D338)', (tester) async {
      phone(tester);
      // The capture the Rails portal specs show: build 2.4.0+311, the picture taken on the phone, a
      // tester on the mainland.
      final env = deviceEnvironment(
        facts: onBuild(iphone, '2.4.0+311'),
        view: tester.view,
        connection: 'wifi',
        screenshot: const ScreenshotInfo(method: 'native'),
        capturedAt: Harness.now,
        appOpen: const Duration(minutes: 3, seconds: 2),
        timezone: 'America/Los_Angeles',
        app: const AppDetails(environment: 'staging'),
      );
      expect(env['screenshot'], {'method': 'native', 'platform_views_blocked': false});
      expect((env['app']! as Map)['build'], '2.4.0+311');
      writeFixture('DeviceEnvironmentInfo', 'iphone', env);
    });

    testWidgets("the report carries the console and network, masked as the project's level says (D333, D80)", (
      tester,
    ) async {
      Future<Map<String, Object?>> report(String privacy) async {
        final (h, runtime) = await started(
          tester,
          harness: Harness(
            view: tester.view,
            outcome: ConfigOk(exampleConfig(privacy: privacy)),
          ),
        );
        await ready(tester, h);
        h.activity.log('error', 'Card 4242 declined');
        h.activity.start('POST', Uri.parse('https://api.example.com/charges?card=4242'))
          ..status = 402
          ..duration = const Duration(milliseconds: 120)
          ..requestId = 'req-9';
        h.panel!.post({
          'type': 'viper:submit',
          'client_id': 'c-$privacy',
          'report': {'scope': 'screen', 'body': 'Charge fails'},
        });
        await tester.pump();
        await tester.pump();
        final files = h.panel!.of('viper:report').single['files']! as List<Object?>;
        return {
          for (final file in files.cast<Map<String, Object?>>())
            file['field']! as String: jsonDecode(file['body']! as String),
        };
      }

      final standard = await report('standard');
      final console = (standard['console']! as List).single as Map<String, Object?>;
      final network = (standard['network']! as List).single as Map<String, Object?>;
      expect(console['text'], 'Card 4242 declined');
      expect(network['path'], 'https://api.example.com/charges?card=4242');
      writeFixture('ConsoleEntry', 'error', console);
      writeFixture('NetworkEntry', 'call', network);

      final strict = await report('strict');
      expect(((strict['console']! as List).single as Map)['text'], '•••• •••• ••••••••');
      final masked = (strict['network']! as List).single as Map<String, Object?>;
      expect(masked['path'], 'https://api.example.com/charges');
      writeFixture('NetworkEntry', 'call_strict', masked);
    });

    testWidgets('a silent capture of an item that exists is the screen as it is (D20, D113)', (tester) async {
      // The fix's build on the item's screen: the Rails specs post this fixture as the after.
      final (h, runtime) = await started(
        tester,
        harness: Harness(
          view: tester.view,
          device: onBuild(iphone, '2.4.0+312'),
          screens: FixedScreens('CastHubScreen'),
          outcome: ConfigOk(exampleConfig(privacy: 'strict')),
        ),
      );
      await ready(tester, h);
      h.panel!.post({
        'type': 'viper:submit',
        'client_id': 'silent-1',
        'report': {
          'scope': 'screen',
          'body': '',
          'moment': 'fix_landed',
          'item_id': '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b',
        },
      });
      await tester.pump();
      await tester.pump();
      final payload = h.panel!.of('viper:report').single['payload']! as Map<String, Object?>;
      expect(payload['moment'], 'fix_landed');
      expect(payload['item_id'], '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b');
      writeFixture('ReportPayload', 'fix_landed_no_picture', payload);
    });

    testWidgets('identify sends viper:identity once ready (D21)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      final identity = {
        'v': 1,
        'payload': {
          'id': 'u_7',
          'email': 'dana@example.com',
          'name': 'Dana Ortiz',
          'iat': 1793041200,
          'exp': 1793044800,
        },
        'signature': 'a1b2c3',
      };
      runtime.identify(identity);
      final sent = h.panel!.of('viper:identity').last;
      expect(sent['identity'], identity);
      writeFixture('LoaderToPanelMessage', 'identity_signed', sent);
    });

    testWidgets('a minute before the signature expires, the app is asked for a fresh one (D86)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      final exp = Harness.now.add(const Duration(minutes: 3)).millisecondsSinceEpoch ~/ 1000;
      Map<String, Object?> signed(int exp) => {
        'v': 1,
        'payload': {'id': 'u_7', 'email': 'dana@example.com', 'name': 'Dana Ortiz', 'iat': exp - 600, 'exp': exp},
        'signature': 'sig-$exp',
      };
      var asked = 0;
      runtime.identify(
        signed(exp),
        refresh: () async {
          asked++;
          return signed(exp + 600);
        },
      );
      await tester.pump(const Duration(minutes: 1, seconds: 30));
      expect(asked, 0);
      await tester.pump(const Duration(seconds: 31));
      expect(asked, 1);
      expect((h.panel!.of('viper:identity').last['identity']! as Map)['signature'], 'sig-${exp + 600}');
      runtime.identify(null);
    });

    Map<String, Object?> signedUntil(int exp, [String id = 'u_7']) => {
      'v': 1,
      'payload': {'id': id, 'email': '$id@example.com', 'name': 'Dana Ortiz', 'iat': exp - 600, 'exp': exp},
      'signature': 'sig-$id-$exp',
    };
    int secondsFromNow(Duration d) => Harness.now.add(d).millisecondsSinceEpoch ~/ 1000;

    testWidgets('signing out while a refresh runs stays signed out, as on the web', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      final exp = secondsFromNow(const Duration(minutes: 2));
      final answer = Completer<SignedIdentity?>();
      var asked = 0;
      runtime.identify(
        signedUntil(exp),
        refresh: () {
          asked++;
          return answer.future;
        },
      );
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(asked, 1);
      runtime.identify(null);
      answer.complete(signedUntil(exp + 600));
      await tester.pump();
      expect(h.panel!.of('viper:identity').last['identity'], isNull);
      await tester.pump(const Duration(hours: 1));
      expect(asked, 1, reason: 'signed out, nothing is refreshed');
    });

    testWidgets('a token already in its last minute waits ten seconds before each refresh', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      var asked = 0;
      runtime.identify(
        signedUntil(secondsFromNow(const Duration(seconds: 30))),
        refresh: () async {
          asked++;
          return signedUntil(secondsFromNow(const Duration(seconds: 30)));
        },
      );
      await tester.pump(const Duration(seconds: 9));
      expect(asked, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(asked, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(asked, 1, reason: 'never a loop');
      runtime.identify(null);
    });

    testWidgets('an identity set before start is refreshed with the callback it came with', (tester) async {
      final exp = secondsFromNow(const Duration(minutes: 3));
      var asked = 0;
      // What Viper.identify keeps before start (markers.dart).
      ViperSlots.identityPending = true;
      ViperSlots.pendingIdentity = signedUntil(exp);
      ViperSlots.pendingRefresh = () async {
        asked++;
        return signedUntil(exp + 600);
      };
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(asked, 1);
      expect((h.panel!.of('viper:identity').last['identity']! as Map)['signature'], 'sig-u_7-${exp + 600}');
      runtime.identify(null);
    });

    testWidgets('resume and pause tell the panel (D42)', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final states = h.panel!.of('viper:app:state');
      expect(states.map((m) => m['state']), ['paused', 'resumed']);
      writeFixture('LoaderToPanelMessage', 'app_state_resumed', states.last);
    });

    testWidgets('Android back closes the sheet before the app sees it', (tester) async {
      final (h, runtime) = await started(tester);
      await ready(tester, h);
      expect(await runtime.didPopRoute(), isFalse);
      runtime.openSheet();
      expect(await runtime.didPopRoute(), isTrue);
      expect(runtime.sheetOpen, isFalse);
    });
  });
}
