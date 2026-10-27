// The launcher and the sheet on screen (W01, D169, D295, D335, D44).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/core/store.dart';
import 'package:viper_flutter/src/ui/host.dart';
import 'package:viper_flutter/src/ui/launcher.dart';
import 'package:viper_flutter/src/ui/sheet.dart';
import 'package:viper_flutter/src/ui/skeleton.dart';

import 'support/fakes.dart';

Future<(Harness, ViperRuntime)> pumpApp(
  WidgetTester tester, {
  MemoryStore? store,
  String? revealHint,
  Widget? bottomBar,
  ConfigOutcome? outcome,
}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
  final h = Harness(view: tester.view, store: store, outcome: outcome, revealHint: revealHint);
  final runtime = h.runtime();
  addTearDown(runtime.dispose);
  await runtime.boot();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: bottomBar,
        body: Center(
          child: ElevatedButton(onPressed: () {}, child: const Text('Save')),
        ),
      ),
      builder: (context, child) => ViperHost(runtime: runtime, child: child!),
    ),
  );
  return (h, runtime);
}

Finder get launcher => find.byKey(launcherButtonKey);

void main() {
  testWidgets('shows at the bottom right with its label, and the app still takes taps', (tester) async {
    final (_, runtime) = await pumpApp(tester);
    final rect = tester.getRect(launcher);
    expect(rect.bottomRight, const Offset(393 - 16, 852 - 34 - 16));
    expect(find.bySemanticsLabel('Viper'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(runtime.sheetOpen, isFalse);
  });

  testWidgets("the label says what's open and what needs the viewer", (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:ready'});
    h.panel!.post({'type': 'viper:count', 'open': 5, 'needs_you': 1});
    await tester.pump();
    expect(find.bySemanticsLabel('Viper, 5 open, 1 needs you'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a tap opens the sheet with the skeleton until viper:ready (D44)', (tester) async {
    final (h, runtime) = await pumpApp(tester);
    await tester.tap(launcher);
    await tester.pump(const Duration(milliseconds: 400));
    expect(runtime.sheetOpen, isTrue);
    expect(find.byType(PanelSkeleton), findsOneWidget);
    expect(launcher, findsNothing);
    h.panel!.post({'type': 'viper:ready'});
    await tester.pump();
    expect(find.byType(PanelSkeleton), findsNothing);
    h.panel!.post({'type': 'viper:close'});
    await tester.pumpAndSettle();
    expect(launcher, findsOneWidget);
  });

  testWidgets('the sheet stays below the top safe area and rises with the keyboard', (tester) async {
    final (_, runtime) = await pumpApp(tester);
    runtime.openSheet();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byType(ViperSheet);
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(59));
    expect(tester.getRect(sheet).bottom, 852);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(sheet).bottom, 852 - 336);
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(59));
  });

  testWidgets("the panel's footer stays above the home indicator; with the keyboard up, no strip", (tester) async {
    final (_, runtime) = await pumpApp(tester);
    runtime.openSheet();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byType(ViperSheet);
    final web = find.byKey(FakePanelView.webViewKey);
    // 102 physical pixels at 3x: a 34-point home indicator.
    expect(tester.getRect(sheet).bottom, 852, reason: 'the sheet still runs to the edge');
    expect(tester.getRect(web).bottom, 852 - 34, reason: 'the web view stops above the indicator');
    expect(tester.getSize(find.byKey(ViperSheet.bottomStripKey)).height, 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(ViperSheet.bottomStripKey), findsNothing);
    expect(tester.getRect(web).bottom, 852 - 336, reason: 'on the keyboard, the web view reaches the sheet bottom');
  });

  testWidgets('a drag snaps to the nearest spot and is remembered per install (D169, D335)', (tester) async {
    final store = MemoryStore();
    final (_, runtime) = await pumpApp(tester, store: store);
    await tester.drag(launcher, const Offset(-300, -700));
    await tester.pumpAndSettle();
    expect(runtime.layout.spot, 'top-left');
    expect(runtime.sheetOpen, isFalse);
    expect(await store.readJson('viper.hbr_loc_9w.launcher'), containsPair('spot', 'top-left'));
    expect(await store.readJson('viper.hbr_loc_9w.launcher'), containsPair('moved', true));
  });

  testWidgets('a long press tucks it to an edge tab, and the tab brings the button back', (tester) async {
    final (_, runtime) = await pumpApp(tester);
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    expect(find.text('Hide Viper'), findsOneWidget, reason: 'a shake can bring it back');
    await tester.tap(find.text('Tuck to the edge'));
    await tester.pumpAndSettle();
    expect(runtime.layout.tucked, isTrue);
    final tab = tester.getRect(launcher);
    expect(tab.right, 393 + 6);
    expect(tab.width, 34);
    await tester.tap(launcher);
    await tester.pump(const Duration(milliseconds: 400));
    expect(runtime.sheetOpen, isTrue);
    runtime.closeSheet();
    await tester.pumpAndSettle();
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show the round button'));
    await tester.pumpAndSettle();
    expect(runtime.layout.tucked, isFalse);
  });

  testWidgets('hidden, nothing shows; the menu offers hiding once shake can bring it back', (tester) async {
    final (_, runtime) = await pumpApp(tester);
    runtime.shakeAvailable = true;
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide Viper'));
    await tester.pump();
    expect(runtime.layout.hidden, isTrue);
    expect(launcher, findsNothing);
    expect(find.text('Viper is hidden. Shake your phone to bring it back.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Viper is hidden'), findsNothing);
  });

  testWidgets("with the app's own way back, hiding is offered without a shake and says that way (D371)", (
    tester,
  ) async {
    final (_, runtime) = await pumpApp(tester, revealHint: 'Long-press the logo on Account to bring it back.');
    // A phone with no shake to listen for: only the app's way brings Viper back.
    runtime.shakeAvailable = false;
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide Viper'));
    await tester.pump();
    expect(runtime.layout.hidden, isTrue);
    expect(find.text('Viper is hidden. Long-press the logo on Account to bring it back.'), findsOneWidget);
    runtime.show();
    await tester.pump();
    expect(launcher, findsOneWidget);
    // Back again, the note on how to bring it back goes at once rather than sitting over the sheet.
    expect(find.textContaining('Viper is hidden'), findsNothing);
  });

  testWidgets('without a shake or a way back from the app, hiding is never offered (D335, D371)', (tester) async {
    final (_, runtime) = await pumpApp(tester);
    runtime.shakeAvailable = false;
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    expect(find.text('Hide Viper'), findsNothing);
  });

  testWidgets('VoiceOver and TalkBack get the tuck action (D335)', (tester) async {
    final handle = tester.ensureSemantics();
    final (_, runtime) = await pumpApp(tester);
    tester.semantics.customAction(
      find.semantics.byLabel('Viper'),
      const CustomSemanticsAction(label: 'Tuck to the edge'),
    );
    await tester.pumpAndSettle();
    expect(runtime.layout.tucked, isTrue);
    handle.dispose();
  });

  testWidgets('nothing is drawn while Viper is refused', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness(view: tester.view, outcome: const ConfigRefused('disabled'));
    final runtime = h.runtime();
    addTearDown(runtime.dispose);
    await runtime.boot();
    await tester.pumpWidget(
      MaterialApp(
        home: const Text('App'),
        builder: (context, child) => ViperHost(runtime: runtime, child: child!),
      ),
    );
    expect(launcher, findsNothing);
    expect(find.text('App'), findsOneWidget);
  });

  test('labels', () {
    expect(launcherLabel(0, 0), 'Viper');
    expect(launcherLabel(3, 0), 'Viper, 3 open');
    expect(launcherLabel(3, 2), 'Viper, 3 open, 2 needs you');
  });

  testWidgets("a bottom spot sits above the app's bottom navigation bar (D351)", (tester) async {
    await pumpApp(
      tester,
      bottomBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    final bar = tester.getRect(find.byType(NavigationBar));
    final button = tester.getRect(launcher);
    expect(button.bottom, lessThanOrEqualTo(bar.top - 15.9), reason: '$button over $bar');
    expect(button.right, 393 - 16);
  });

  testWidgets("the project's own raise wins over the lift (D295, D351)", (tester) async {
    await pumpApp(
      tester,
      outcome: ConfigOk(
        exampleConfig(
          launcher: {
            'style': 'corner',
            'spot': 'bottom-right',
            'raise': 200,
            'edge_side': 'right',
            'edge_position': 50,
          },
        ),
      ),
      bottomBar: const BottomAppBar(child: SizedBox(height: 40)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(launcher).bottom, 852 - 34 - 16 - 200);
  });

  testWidgets('with no bottom bar, it sits on the safe area as before', (tester) async {
    await pumpApp(tester);
    await tester.pump();
    expect(tester.getRect(launcher).bottom, 852 - 34 - 16);
  });

  testWidgets("a bar on a covered route doesn't lift the launcher over the route on top", (tester) async {
    await pumpApp(
      tester,
      bottomBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
    await tester.pump();
    final lifted = tester.getRect(launcher).bottom;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Details')))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.getRect(launcher).bottom, 852 - 34 - 16);
    expect(lifted, lessThan(852 - 34 - 16));
  });

  testWidgets('turning the phone, or an iPad split view, puts the launcher back on its spot', (tester) async {
    await pumpApp(tester);
    expect(tester.getRect(launcher).bottomRight, const Offset(393 - 16, 852 - 34 - 16));
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.padding = const FakeViewPadding(left: 177, right: 177, bottom: 63);
    await tester.pump();
    expect(tester.getRect(launcher).bottomRight, const Offset(852 - 59 - 16, 393 - 21 - 16));
    tester.view.physicalSize = const Size(1500, 2048);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    expect(tester.getRect(launcher).bottomRight, const Offset(500 - 16, 682.6666666666666 - 16));
  });

  testWidgets("Viper's own words are in its text style, never Flutter's debug one", (tester) async {
    await pumpApp(tester);
    await tester.longPress(launcher);
    await tester.pumpAndSettle();
    final style = DefaultTextStyle.of(tester.element(find.text('Tuck to the edge'))).style;
    expect(style.decoration, TextDecoration.none);
    expect(style.fontFamily, isNot('monospace'));
  });
}
