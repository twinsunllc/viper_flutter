// Picking and screens (D332, W03, W17, D169): a tap picks the widget under it, the path steps up
// from it, a box names what's in it, the dialog on top is a pick of its own, and the screen and
// surface come from the navigators on screen, nested ones included.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/device.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/core/screens.dart';
import 'package:viper_flutter/src/ui/host.dart';
import 'package:viper_flutter/src/ui/pick_handle.dart';

import 'support/fakes.dart';

/// The fixtures' screen (S's intake specs): Cast hub with its Edit cast dialog.
class CastHubScreen extends StatelessWidget {
  const CastHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cast hub')),
      body: Center(
        child: OutlinedButton(
          key: const ValueKey('edit-cast'),
          onPressed: () => showDialog<void>(context: context, builder: (_) => const EditCastDialog()),
          child: const Text('Edit cast'),
        ),
      ),
    );
  }
}

class EditCastDialog extends StatelessWidget {
  const EditCastDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit cast'),
      content: const Card(
        child: Padding(padding: EdgeInsets.all(8), child: Text('Kalani Akana, lead')),
      ),
      actions: [
        ElevatedButton(key: const ValueKey('save-cast'), onPressed: () {}, child: const Text('Save')),
      ],
    );
  }
}

/// The fixture's phone (S's intake specs): a Pixel 9, 412 logical pixels wide.
const DeviceFacts pixel9 = DeviceFacts(
  os: 'Android',
  osVersion: '16',
  sdkInt: 36,
  model: 'Pixel 9',
  manufacturer: 'Google',
  physical: true,
  appId: 'dev.twinsun.viper.example',
  build: '2.4.0+311',
);

Future<(Harness, ViperRuntime, ViperNavigatorObserver)> pumpApp(
  WidgetTester tester, {
  Widget? home,
  ConfigOutcome? outcome,
  DeviceFacts? device,
}) async {
  final phone = device == pixel9;
  tester.view.physicalSize = phone ? const Size(412 * 2.625, 915 * 2.625) : const Size(1179, 2556);
  tester.view.devicePixelRatio = phone ? 2.625 : 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
  final observer = ViperNavigatorObserver();
  final nested = <ViperNavigatorObserver>[];
  final h = Harness(
    view: tester.view,
    device: device ?? onBuild(iphone, '2.4.0+311'),
    outcome: outcome,
    screens: ScreenTracker(observers: () => [observer, ...nested]),
  );
  final runtime = h.runtime();
  addTearDown(runtime.dispose);
  await runtime.boot();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: home ?? const CastHubScreen(),
      builder: (context, child) => ViperHost(runtime: runtime, child: child!),
    ),
  );
  h.panel!.post({'type': 'viper:ready'});
  await tester.pump();
  runtime.openSheet();
  await tester.pump(const Duration(milliseconds: 400));
  return (h, runtime, observer);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> startPick(WidgetTester tester, Harness h, String mode) async {
  h.panel!.post({'type': 'viper:pick:start', 'mode': mode});
  await settle(tester);
}

void main() {
  testWidgets("a tap on a button's words picks the button, named as people say it (W03)", (tester) async {
    final (h, runtime, _) = await pumpApp(tester, device: pixel9);
    await tester.tap(find.byKey(const ValueKey('edit-cast')));
    await tester.pumpAndSettle();
    await startPick(tester, h, 'element');
    expect(runtime.picking, isTrue);
    expect(find.text('Tap what you mean'), findsOneWidget);
    expect(find.byKey(PickHandle.dialogKey), findsOneWidget, reason: 'a dialog is open');

    await tester.tapAt(tester.getCenter(find.text('Save')));
    await settle(tester);
    expect(runtime.picking, isFalse);
    final result = h.panel!.of('viper:pick:result').single;
    expect(result['label'], 'Save button');
    expect(result['scope'], 'element');
    final anchor = result['anchor']! as Map<String, Object?>;
    final locators = anchor['locators']! as Map<String, Object?>;
    expect(locators, containsPair('widget', 'ElevatedButton'));
    expect(locators, containsPair('key', 'save-cast'));
    expect(locators, containsPair('semantics', 'Save'));
    expect(locators, containsPair('text', 'Save'));
    final button = tester.getRect(find.byKey(const ValueKey('save-cast')));
    expect(locators['position'], {
      'x': button.left.round(),
      'y': button.top.round(),
      'width': button.width.round(),
      'height': button.height.round(),
    });
    final context = result['context']! as Map<String, Object?>;
    expect((context['path']! as List).last, {'label': 'Save button'});
    expect(context['surface'], {'kind': 'dialog', 'key': 'EditCastDialog', 'name': 'Edit cast'});
    expect(context['mode'], 'element');
    expect(runtime.outline, button);
    expect(h.panel!.of('viper:screenshot').last['status'], 'ready');
    writeFixture('LoaderToPanelMessage', 'pick_result', result);

    // The report: the panel sends the pick's anchor back with the words (D18).
    h.panel!.post({
      'type': 'viper:submit',
      'client_id': 'pick-1',
      'report': {
        'scope': 'element',
        'body': 'Save does nothing\nTapping Save on the cast dialog leaves it open and nothing changes.',
        'anchor': anchor,
      },
    });
    await settle(tester);
    final payload = h.panel!.of('viper:report').single['payload']! as Map<String, Object?>;
    expect(payload['screen'], {
      'route': 'CastHubScreen',
      'url': '',
      'title': 'Cast hub',
      'build': '2.4.0+311',
      'surface': {'kind': 'dialog', 'key': 'EditCastDialog', 'name': 'Edit cast'},
    });
    expect(payload['device_picture'], 'pic-1');
    expect(runtime.outline, isNull, reason: 'sent, the pick and its outline go');
    writeFixture('ReportPayload', 'element', payload);
  });

  testWidgets('the breadcrumb steps up the path to the dialog (W17)', (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('edit-cast')));
    await tester.pumpAndSettle();
    await startPick(tester, h, 'element');
    await tester.tapAt(tester.getCenter(find.text('Kalani Akana, lead')));
    await settle(tester);
    final first = h.panel!.of('viper:pick:result').single;
    final path = ((first['context']! as Map)['path']! as List).cast<Map<String, Object?>>();
    expect(path.map((step) => step['label']), ['Edit cast dialog', 'Kalani Akana, lead card', 'Kalani Akana, lead']);
    h.panel!.post({'type': 'viper:pick:step', 'index': 0});
    await settle(tester);
    final stepped = h.panel!.of('viper:pick:result').last;
    expect(stepped['label'], 'Edit cast dialog');
    expect(((stepped['anchor']! as Map)['locators']! as Map)['widget'], 'AlertDialog');
  });

  testWidgets('staff see each step\'s widget and key (W03)', (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:viewer', 'staff': true});
    await startPick(tester, h, 'element');
    await tester.tapAt(tester.getCenter(find.text('Edit cast')));
    await settle(tester);
    final path = (((h.panel!.of('viper:pick:result').single['context']! as Map)['path']!) as List)
        .cast<Map<String, Object?>>();
    expect(path.last, {'label': 'Edit cast button', 'detail': 'OutlinedButton · edit-cast'});
  });

  testWidgets('a drawn box is the anchor, named by what is in it (D39)', (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    await startPick(tester, h, 'box');
    expect(find.text('Drag a box around it'), findsOneWidget);
    final center = tester.getCenter(find.text('Edit cast'));
    await tester.dragFrom(center - const Offset(60, 30), const Offset(120, 60));
    await settle(tester);
    expect(runtime.picking, isFalse, reason: 'the drag picked');
    final result = h.panel!.of('viper:pick:result').single;
    expect(result['label'], 'Box around Edit cast button');
    expect((result['anchor']! as Map)['box'], isA<Map<String, Object?>>());
    expect(((result['context']! as Map)['mode']), 'box');
  });

  testWidgets('This dialog picks the dialog on top, as a screen-scoped surface (W03)', (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('edit-cast')));
    await tester.pumpAndSettle();
    await startPick(tester, h, 'element');
    await tester.tap(find.byKey(PickHandle.dialogKey));
    await settle(tester);
    final result = h.panel!.of('viper:pick:result').single;
    expect(result['label'], 'Edit cast');
    expect(result['scope'], 'screen');
    expect((result['context']! as Map)['mode'], 'surface');
  });

  testWidgets('a pick in the header is a shared part (D48); at Maximum the label has no words', (tester) async {
    final (h, runtime, _) = await pumpApp(
      tester,
      outcome: ConfigOk(exampleConfig(privacy: 'maximum')),
    );
    await startPick(tester, h, 'element');
    await tester.tapAt(tester.getCenter(find.text('Edit cast')));
    await settle(tester);
    final result = h.panel!.of('viper:pick:result').single;
    expect(result['label'], 'Button');
    final locators = (result['anchor']! as Map)['locators']! as Map;
    expect(locators.containsKey('text'), isFalse);
    expect(locators.containsKey('semantics'), isFalse);
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'element'});
    await settle(tester);
    await tester.tapAt(tester.getCenter(find.text('Cast hub')));
    await settle(tester);
    expect(h.panel!.of('viper:pick:result').last['scope'], 'shared_part');
  });

  testWidgets('a new screen is viper:navigate, a dialog on it is viper:surface (D18)', (tester) async {
    final (h, runtime, observer) = await pumpApp(tester);
    runtime.closeSheet();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-cast')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final surfaces = h.panel!.of('viper:surface');
    expect(surfaces.last, {
      'type': 'viper:surface',
      'surface': {'kind': 'dialog', 'key': 'EditCastDialog', 'name': 'Edit cast'},
    });
    writeFixture('LoaderToPanelMessage', 'surface', surfaces.last);
    unawaited(
      observer.navigator!.pushReplacement(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/crew-list'),
          builder: (_) => const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final navigate = h.panel!.of('viper:navigate').last;
    expect((navigate['screen']! as Map)['route'], '/crew-list');
    writeFixture('LoaderToPanelMessage', 'navigate', navigate);
  });

  testWidgets('nothing under ViperPrivate leaves in a pick: not as a label, a path step or a locator (D331)', (
    tester,
  ) async {
    final (h, runtime, _) = await pumpApp(
      tester,
      home: const Scaffold(
        body: Column(
          children: [
            ViperPrivate(child: Text('4111 1111 1111 1111', key: ValueKey('card-number'))),
            SizedBox(height: 40),
            Card(
              key: ValueKey('payment-card'),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Visa'),
                    ViperPrivate(
                      child: Tooltip(
                        message: 'Expires 09/29',
                        child: Text('Kalani Akana', semanticsLabel: 'Card holder Kalani Akana'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    h.panel!.post({'type': 'viper:viewer', 'staff': true});
    const secrets = ['4111', 'Kalani', 'Akana', 'Expires', '09/29', 'holder', 'card-number', 'Card number'];
    Future<String> pickAt(Finder target) async {
      h.panel!.post({'type': 'viper:pick:start', 'mode': 'element'});
      await settle(tester);
      await tester.tapAt(tester.getCenter(target));
      await settle(tester);
      return jsonEncode(h.panel!.of('viper:pick:result').last);
    }

    final number = await pickAt(find.text('4111 1111 1111 1111'));
    for (final secret in secrets) {
      expect(number, isNot(contains(secret)), reason: secret);
    }
    final holder = await pickAt(find.text('Kalani Akana'));
    for (final secret in secrets) {
      expect(holder, isNot(contains(secret)), reason: secret);
    }
    expect(holder, contains('Visa'), reason: 'the card itself still says what it is');
    // The card, stepped up to, keeps its own words and none of the private ones.
    h.panel!.post({'type': 'viper:pick:step', 'index': 0});
    await settle(tester);
    final card = jsonEncode(h.panel!.of('viper:pick:result').last);
    for (final secret in secrets) {
      expect(card, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets("checking a fix outlines the item's widget when it's on screen (W07)", (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    h.panel!.post({
      'type': 'viper:highlight',
      'item_id': '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b',
      'anchor': {
        'locators': {'widget': 'OutlinedButton', 'key': 'edit-cast', 'text': 'Edit cast'},
      },
    });
    await settle(tester);
    expect(runtime.outline, tester.getRect(find.byKey(const ValueKey('edit-cast'))));
    expect(find.byType(PickOutline), findsOneWidget);
    h.panel!.post({'type': 'viper:highlight', 'item_id': '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b'});
    await settle(tester);
    expect(runtime.outline, isNull);
    h.panel!.post({
      'type': 'viper:highlight',
      'item_id': '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b',
      'anchor': {
        'locators': {'widget': 'OutlinedButton', 'key': 'gone'},
      },
    });
    await settle(tester);
    expect(runtime.outline, isNull, reason: 'not on screen: nothing outlined');
  });

  testWidgets('a box is one step: nothing to step up to', (tester) async {
    final (h, runtime, _) = await pumpApp(tester);
    await startPick(tester, h, 'box');
    final center = tester.getCenter(find.text('Edit cast'));
    await tester.dragFrom(center - const Offset(60, 30), const Offset(120, 60));
    await settle(tester);
    expect(((h.panel!.of('viper:pick:result').single['context']! as Map)['path']! as List), hasLength(1));
  });

  group('screens and surfaces (D332)', () {
    testWidgets('ViperScreen names a screen; else the route name; else the type the route built', (tester) async {
      final (h, runtime, observer) = await pumpApp(tester);
      expect(runtime.screens.current()['route'], 'CastHubScreen');
      expect(runtime.screens.current()['title'], 'Cast hub');
      final navigator = observer.navigator!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/crew-list'),
            builder: (_) => const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(runtime.screens.current()['route'], '/crew-list');
      expect(runtime.screens.current()['title'], 'Crew list');
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const ViperScreen(name: 'Call sheet', child: Scaffold()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(runtime.screens.current()['route'], 'Call sheet');
      expect(runtime.screens.current()['title'], 'Call sheet');
    });

    testWidgets('the innermost navigator on screen wins, never one on a hidden tab', (tester) async {
      final jobs = ViperNavigatorObserver();
      final crew = ViperNavigatorObserver();
      final tab = ValueNotifier(0);
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final root = ViperNavigatorObserver();
      final screens = ScreenTracker(observers: () => [root, jobs, crew]);
      Widget tabNavigator(ViperNavigatorObserver observer, Widget page) => Navigator(
        observers: [observer],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => page),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [root],
          home: ValueListenableBuilder<int>(
            valueListenable: tab,
            builder: (context, index, _) => IndexedStack(
              index: index,
              children: [
                tabNavigator(jobs, const ViperScreen(name: 'Jobs list', child: SizedBox())),
                tabNavigator(crew, const ViperScreen(name: 'Crew list', child: SizedBox())),
              ],
            ),
          ),
        ),
      );
      expect(screens.current()['route'], 'Jobs list');
      expect(screens.currentSurface(), isNull, reason: 'no bar here');
      tab.value = 1;
      await tester.pump();
      expect(screens.current()['route'], 'Crew list');
    });

    testWidgets("the tab bar outside a tab's own navigator still names the tab", (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final root = ViperNavigatorObserver();
      final inner = ViperNavigatorObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [root],
          home: Scaffold(
            body: Navigator(
              observers: [inner],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const ViperScreen(name: 'Job details', child: SizedBox()),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.work), label: 'Jobs'),
                NavigationDestination(icon: Icon(Icons.groups), label: 'Crew'),
              ],
            ),
          ),
        ),
      );
      final screen = ScreenTracker(observers: () => [root, inner]).current();
      expect(screen['route'], 'Job details');
      expect(screen['surface'], {'kind': 'tab', 'key': 'tab:jobs', 'name': 'Jobs'});
    });

    testWidgets('an observer attached after the first route still knows the current one', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final late = ViperNavigatorObserver();
      final observers = ValueNotifier<List<NavigatorObserver>>([]);
      await tester.pumpWidget(
        ValueListenableBuilder<List<NavigatorObserver>>(
          valueListenable: observers,
          builder: (context, list, _) => MaterialApp(navigatorObservers: list, home: const CastHubScreen()),
        ),
      );
      observers.value = [late];
      await tester.pump();
      expect(late.routes, isEmpty, reason: 'it missed the first push');
      expect(ScreenTracker(observers: () => [late]).current()['route'], 'CastHubScreen');
    });

    testWidgets('a bottom sheet, an open drawer and the tab on show are surfaces', (tester) async {
      final observer = ViperNavigatorObserver();
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final screens = ScreenTracker(observers: () => [observer]);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Scaffold(
            drawer: const Drawer(child: Text('Menu items')),
            appBar: AppBar(),
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const Text('Share')),
                child: const Text('Share'),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: 1,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.work), label: 'Jobs'),
                NavigationDestination(icon: Icon(Icons.groups), label: 'Crew'),
              ],
            ),
          ),
        ),
      );
      expect(screens.currentSurface(), {'kind': 'tab', 'key': 'tab:crew', 'name': 'Crew'});
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(screens.currentSurface(), {'kind': 'drawer', 'key': 'drawer', 'name': 'Menu'});
      Navigator.of(tester.element(find.text('Menu items'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(screens.currentSurface(), containsPair('name', 'Bottom sheet'));
      expect(screens.currentSurface(), containsPair('kind', 'other'));
    });
  });
}
