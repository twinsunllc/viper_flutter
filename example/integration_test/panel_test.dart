// The panel from a local Viper, in the example app on a simulator or an emulator (flutter.md,
// slice 1). Needs a local Viper on port 4830 with the seeds (the package README, "How to try
// it"), and the VIPER define:
//
//   flutter test integration_test/panel_test.dart -d <device> --dart-define=VIPER=true
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/launcher.dart';
import 'package:viper_flutter/src/ui/panel_view.dart';
import 'package:viper_flutter/viper_flutter.dart';
import 'package:viper_flutter_example/main_staging.dart' as staging;

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the launcher opens the panel in bridge mode, and Dart and the panel talk', (tester) async {
    staging.main();
    await pumpUntil(tester, () => Viper.runtime?.phase == ViperPhase.ready);
    final runtime = Viper.runtime!;
    await pumpUntil(tester, () => runtime.panelReady);

    await tester.tap(find.byKey(launcherButtonKey));
    await tester.pump(const Duration(milliseconds: 600));
    expect(runtime.sheetOpen, isTrue);

    final web = (runtime.panel! as WebPanelView).controller;
    final mode = await web.runJavaScriptReturningResult(
      "new URLSearchParams(location.search).get('bridge') + '|' + (typeof window.viperReceive)",
    );
    expect('$mode'.replaceAll('"', ''), 'native|function');
    final text = await web.runJavaScriptReturningResult('document.body.innerText');
    expect('$text', isNot(contains('This panel opens from the Viper widget')));

    // The panel's own reads pass as Viper's (Sec-Fetch-Site, D329): a 403 here means the web view
    // isn't in a secure context (plain HTTP to anything but localhost).
    await web.runJavaScript(
      "window.__viperCheck = 'pending'; fetch('/widget/screen?route=%2F&url=&title=Home&key=' + "
      "new URLSearchParams(location.search).get('key')).then(r => window.__viperCheck = String(r.status))",
    );
    var status = '"pending"';
    for (var i = 0; i < 50 && status.contains('pending'); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      status = '${await web.runJavaScriptReturningResult('window.__viperCheck')}';
    }
    expect(status.replaceAll('"', ''), '200');

    // The panel's close button sends viper:close; Dart closes the sheet.
    await web.runJavaScript("ViperBridge.postMessage(JSON.stringify({type: 'viper:close'}))");
    await pumpUntil(tester, () => !runtime.sheetOpen);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(launcherButtonKey), findsOneWidget);
  });
}
