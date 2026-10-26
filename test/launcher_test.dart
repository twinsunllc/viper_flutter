// The launcher and the sheet on screen (W01, D169, D295, D335, D44).
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

Future<(Harness, ViperRuntime)> pumpApp(WidgetTester tester, {MemoryStore? store}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
  final h = Harness(view: tester.view, store: store);
  final runtime = h.runtime();
  addTearDown(runtime.dispose);
  await runtime.boot();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
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
    expect(find.text('Hide Viper'), findsNothing, reason: 'hiding waits for shake (slice 6)');
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
}
