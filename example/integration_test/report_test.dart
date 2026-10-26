// A real report from the example app to a local Viper (flutter.md, slices 2 and 5): the whole
// screen picked from the handle, the phone's masked picture uploaded, the words typed in the
// panel, the reporter named, and the item back in the panel's list. Needs a local Viper on port
// 4830 with the seeds (the package README, "How to try it"):
//
//   flutter test integration_test/report_test.dart -d <device> --dart-define=VIPER=true
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viper_flutter/src/core/camera.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/launcher.dart';
import 'package:viper_flutter/src/ui/panel_view.dart';
import 'package:viper_flutter/src/ui/pick_handle.dart';
import 'package:viper_flutter/viper_flutter.dart';
import 'package:viper_flutter_example/main_staging.dart' as staging;
import 'package:webview_flutter/webview_flutter.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  Future<bool> Function() done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await done()) {
    if (DateTime.now().isAfter(end)) {
      final panel = Viper.runtime?.panel;
      final page = panel is WebPanelView
          ? await js(
              panel.controller,
              "JSON.stringify([...document.querySelectorAll('textarea')].map((t) => [t.name, t.value, !!t.offsetParent])) + ' ' + JSON.stringify([...document.querySelectorAll('[data-act=send]')].map((b) => [b.disabled, b.className, !!b.offsetParent])) + ' ' + document.body.innerText.slice(0, 300)",
            )
          : '';
      fail('timed out; the panel says: $page');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<String> js(WebViewController web, String script) async {
  final result = await web.runJavaScriptReturningResult(script);
  final text = '$result';
  // iOS answers the string itself; Android answers it JSON-encoded.
  return text.startsWith('"') ? jsonDecode(text) as String : text;
}

Future<void> reportWholeScreen(WidgetTester tester, ViperRuntime runtime, String words) async {
  final web = (runtime.panel! as WebPanelView).controller;
  await tester.tap(find.byKey(launcherButtonKey));
  await tester.pump(const Duration(milliseconds: 600));
  await pumpUntil(
    tester,
    () async => await js(web, "String(!!document.querySelector('[data-act=\"report\"]'))") == 'true',
  );
  await web.runJavaScript("document.querySelector('[data-act=\"report\"]').click()");
  await pumpUntil(tester, () async => runtime.picking);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(PickHandle.wholeScreenKey));
  await pumpUntil(tester, () async => !runtime.picking && !runtime.capturing);
  await pumpUntil(tester, () async => runtime.panelState['view'] == 'compose');
  await pumpUntil(
    tester,
    () async => await js(web, "String(!!document.querySelector('textarea[name=\"body\"]'))") == 'true',
  );
  // The composer can render again as the picture arrives: type until Send takes the words.
  await pumpUntil(tester, () async {
    final sent = await js(web, '''
      (() => {
        const say = [...document.querySelectorAll('textarea[name="body"]')].filter((t) => t.offsetParent).pop();
        say.value = ${jsonEncode(words)};
        say.dispatchEvent(new Event('input', { bubbles: true }));
        const send = [...document.querySelectorAll('[data-act="send"]')].filter((b) => b.offsetParent).pop();
        if (send.disabled) return 'no';
        send.click();
        return 'yes';
      })()
    ''');
    if (sent != 'yes') await tester.pump(const Duration(milliseconds: 500));
    return sent == 'yes';
  });
  // Nobody signed in the first time: the panel asks who's sending it (W10).
  await tester.pump(const Duration(seconds: 1));
  if (await js(web, "String(!!document.querySelector('input[name=\"email\"]'))") == 'true') {
    await web.runJavaScript('''
      const form = document.querySelector('input[name="email"]').form;
      form.querySelector('input[name="name"]').value = 'Kalani Akana';
      form.querySelector('input[name="email"]').value = 'kalani@example.com';
      form.requestSubmit();
    ''');
  }
  // The item comes back in the panel's list once Viper has it.
  await pumpUntil(
    tester,
    () async => (await js(web, 'document.body.innerText')).contains(words.substring(0, 30)),
    timeout: const Duration(seconds: 60),
  );
  await pumpUntil(tester, () async => !(await js(web, 'document.body.innerText')).contains('Sending'));
  runtime.closeSheet();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Takes a shot, pumping frames meanwhile: the shot waits for a frame without Viper on it.
Future<Shot> shoot(WidgetTester tester, ViperRuntime runtime) async {
  Shot? shot;
  unawaited(runtime.takeShot().then((value) => shot = value));
  await pumpUntil(tester, () async => shot != null);
  return shot!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('whole-screen reports land in Viper with the phone\'s picture', (tester) async {
    staging.main();
    await pumpUntil(tester, () async => Viper.runtime?.phase == ViperPhase.ready && Viper.runtime!.panelReady);
    final runtime = Viper.runtime!;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // The Account tab, so the picture shows the password masked (D331). The launcher sits above
    // the tab bar on its own (D351), so the tab is there to tap.
    await tester.tap(find.text('Account'));
    await tester.pump(const Duration(milliseconds: 500));
    // Save prints, warns through package:logging and calls the app's API, so the report has
    // console lines and a network call (D333).
    await tester.tap(find.byKey(const ValueKey('save')));
    await pumpUntil(tester, () async => find.text('Saved.').evaluate().isNotEmpty);
    await reportWholeScreen(tester, runtime, 'The Save button stays grey (integration $stamp)');

    // A native platform view, which the native picture draws (D338).
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Native view'));
    await tester.pump(const Duration(seconds: 1));
    await reportWholeScreen(tester, runtime, 'The native bar is cut off (integration $stamp)');

    // An embedded web view, which every level masks (D331).
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Web page'));
    await tester.pump(const Duration(seconds: 2));
    await reportWholeScreen(tester, runtime, 'The call sheet page is blank (integration $stamp)');
  });

  testWidgets('a secure window gets no picture, on purpose (D338)', (tester) async {
    if (!Platform.isAndroid) return;
    staging.main();
    await pumpUntil(tester, () async => Viper.runtime?.phase == ViperPhase.ready);
    final runtime = Viper.runtime!;
    await pumpUntil(tester, () async => find.text('Account').evaluate().isNotEmpty);
    await tester.tap(find.text('Account'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('secure')));
    await tester.pump(const Duration(milliseconds: 500));
    final shot = await shoot(tester, runtime);
    expect(shot.png, isNull);
    expect(shot.info.toJson(), {'method': 'none', 'platform_views_blocked': false, 'blocked': 'secure_window'});
    await tester.tap(find.byKey(const ValueKey('secure')));
    await tester.pump(const Duration(milliseconds: 500));
    expect((await shoot(tester, runtime)).info.method, 'native');
  });
}
