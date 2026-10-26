// The phone's picture (D330, D331, D338): taken with Viper hidden, masked, uploaded once, and
// named by the report.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/core/api.dart';
import 'package:viper_flutter/src/core/camera.dart';
import 'package:viper_flutter/src/core/environment.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/host.dart';
import 'package:viper_flutter/src/ui/pick_handle.dart';

import 'support/fakes.dart';

class Screen extends StatelessWidget {
  const Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TextField(
            key: ValueKey('name'),
            decoration: InputDecoration(labelText: 'Name'),
          ),
          TextField(
            key: const ValueKey('password'),
            controller: TextEditingController(text: 'hunter2'),
            obscureText: true,
          ),
          const ViperPrivate(
            child: SizedBox(key: ValueKey('private'), height: 40, child: Text('Home phone (808) 555-0142')),
          ),
          const Text('Public words', key: ValueKey('public')),
        ],
      ),
    );
  }
}

Future<(Harness, ViperRuntime)> pumpApp(
  WidgetTester tester, {
  ConfigOutcome? outcome,
  Widget home = const Screen(),
}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
  final h = Harness(view: tester.view, outcome: outcome);
  final runtime = h.runtime();
  addTearDown(runtime.dispose);
  await runtime.boot();
  await tester.pumpWidget(
    MaterialApp(
      home: home,
      builder: (context, child) => ViperHost(runtime: runtime, child: child!),
    ),
  );
  h.panel!.post({'type': 'viper:ready'});
  await tester.pump();
  runtime.openSheet();
  await tester.pump();
  return (h, runtime);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

void main() {
  testWidgets('a whole-screen pick shows the thumbnail; the report names the uploaded picture (D330)', (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
    await settle(tester);

    expect(h.native.captures, hasLength(1));
    expect(h.native.hidden, [true], reason: "Viper's own UI is hidden for the frame (D331)");
    expect(runtime.capturing, isFalse);
    final shots = h.panel!.of('viper:screenshot');
    expect(shots.map((m) => m['status']), ['taking', 'ready']);
    expect(shots.last['data_url'], startsWith('data:image/jpeg;base64,'));
    writeFixture('LoaderToPanelMessage', 'screenshot_ready', shots.last);

    h.panel!.post({
      'type': 'viper:submit',
      'client_id': 'c-1',
      'report': {'scope': 'screen', 'body': 'The Save button stays grey'},
    });
    await settle(tester);
    expect(h.native.captures, hasLength(1), reason: "the report uses the pick's picture");
    expect(h.api.uploads.single, h.native.answer is NativePicture ? (h.native.answer as NativePicture).png : null);
    final report = h.panel!.of('viper:report').single;
    final payload = report['payload']! as Map<String, Object?>;
    expect(payload['device_picture'], 'pic-1');
    expect((payload['env']! as Map)['screenshot'], {'method': 'native', 'platform_views_blocked': false});
    writeFixture('LoaderToPanelMessage', 'report', report);
    writeFixture('ReportPayload', 'whole_screen', payload);
  });

  testWidgets('while picking the sheet is a handle offering the whole screen, or going back (D169)', (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'element'});
    await settle(tester);
    expect(runtime.sheetShown, isFalse);
    expect(find.text('Whole screen'), findsOneWidget);
    await tester.tap(find.byKey(PickHandle.wholeScreenKey));
    await settle(tester);
    expect(runtime.sheetShown, isTrue);
    expect(h.panel!.of('viper:pick:none').single['label'], 'Whole screen');
    expect(h.panel!.of('viper:screenshot').last['status'], 'ready');
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'element'});
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(h.panel!.of('viper:pick:cancel'), hasLength(1));
    expect(find.text('Whole screen'), findsNothing);
  });

  testWidgets('Standard masks the password and ViperPrivate, never the plain field or the words (D331)', (
    tester,
  ) async {
    final (h, runtime) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
    await settle(tester);
    final boxes = h.native.captures.single;
    bool covers(Rect target) => boxes.any((box) => box.overlaps(target.deflate(1)));
    expect(boxes, hasLength(2));
    expect(covers(rectOf(tester, 'private')), isTrue);
    final password = find.descendant(of: find.byKey(const ValueKey('password')), matching: find.byType(EditableText));
    expect(covers(tester.getRect(password)), isTrue);
    expect(covers(rectOf(tester, 'public')), isFalse);
    final name = find.descendant(of: find.byKey(const ValueKey('name')), matching: find.byType(EditableText));
    expect(covers(tester.getRect(name)), isFalse);
  });

  testWidgets("what isn't painted isn't masked: a hidden tab, a covered route (D331)", (tester) async {
    final (h, runtime) = await pumpApp(
      tester,
      home: const IndexedStack(
        index: 0,
        children: [
          Scaffold(body: Center(child: Text('Visible tab'))),
          Scaffold(body: TextField(obscureText: true)),
        ],
      ),
    );
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
    await settle(tester);
    expect(h.native.captures.last, isEmpty, reason: "the hidden tab's password isn't on screen");

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('On top')))));
    await tester.pumpAndSettle();
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
    await settle(tester);
    expect(h.native.captures.last, isEmpty);
  });

  testWidgets('a secure window gets no picture, on purpose, and the report says why (D338)', (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.native.answer = const NativeSecure();
    h.panel!.post({
      'type': 'viper:submit',
      'client_id': 'c-2',
      'report': {'scope': 'screen', 'body': 'Locked screen'},
    });
    await settle(tester);
    expect(h.api.uploads, isEmpty);
    final payload = h.panel!.of('viper:report').single['payload']! as Map<String, Object?>;
    expect(payload.containsKey('device_picture'), isFalse);
    expect((payload['env']! as Map)['screenshot'], {
      'method': 'none',
      'platform_views_blocked': false,
      'blocked': 'secure_window',
    });
    writeFixture('ReportPayload', 'secure_window', payload);
  });

  testWidgets("Flutter's own picture, when the native call fails, is masked and says platform views were blocked", (
    tester,
  ) async {
    final (_, runtime) = await pumpApp(tester);
    final boundary = runtime.appKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Shot? shot;
    await tester.runAsync(() async {
      shot = await flutterShot(boundary, [const Rect.fromLTWH(16, 100, 200, 40)], pixelRatio: 3);
    });
    expect(shot!.info.toJson(), {'method': 'flutter', 'platform_views_blocked': true});
    expect(shot!.png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(shot!.thumbType, 'image/png');
  });

  testWidgets('out of reach, the panel waits; the retry reuses the picture and uploads it again (D165)', (
    tester,
  ) async {
    final (h, runtime) = await pumpApp(tester);
    h.api.pictures = [const PictureUnreachable('offline'), PictureStored('pic-2', DateTime.utc(2026, 10, 26, 20))];
    final submit = {
      'type': 'viper:submit',
      'client_id': 'c-3',
      'report': {'scope': 'screen', 'body': 'Offline'},
    };
    h.panel!.post(submit);
    await settle(tester);
    expect(h.panel!.of('viper:save:failed').single, containsPair('unreachable', true));
    expect(h.panel!.of('viper:report'), isEmpty);
    h.panel!.post(submit);
    await settle(tester);
    expect(h.native.captures, hasLength(1), reason: 'the same picture');
    expect(h.api.uploads, hasLength(2));
    expect((h.panel!.of('viper:report').single['payload']! as Map)['device_picture'], 'pic-2');
  });

  testWidgets('a refused picture lets the report go without it', (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.api.pictures = [const PictureRefused('too_many', 'Too many pictures are waiting.')];
    h.panel!.post({
      'type': 'viper:submit',
      'client_id': 'c-4',
      'report': {'scope': 'screen', 'body': 'Refused'},
    });
    await settle(tester);
    final payload = h.panel!.of('viper:report').single['payload']! as Map<String, Object?>;
    expect(payload.containsKey('device_picture'), isFalse);
    expect((payload['env']! as Map)['screenshot'], containsPair('blocked', 'failed'));
  });

  testWidgets("a silent capture takes the screen as it is, not the pick's picture (D20, D113)", (tester) async {
    final (h, runtime) = await pumpApp(tester);
    h.panel!.post({'type': 'viper:pick:start', 'mode': 'screen'});
    await settle(tester);
    h.panel!.post({
      'type': 'viper:submit',
      'client_id': 'silent-1',
      'report': {
        'scope': 'screen',
        'body': '',
        'moment': 'review_view',
        'item_id': '6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b',
      },
    });
    await settle(tester);
    expect(h.native.captures, hasLength(2));
    expect((h.panel!.of('viper:report').single['payload']! as Map)['device_picture'], 'pic-1');
  });

  test('a thumbnail is a data URL of its type', () {
    final shot = Shot(
      png: Uint8List(1),
      thumb: Uint8List.fromList([1, 2, 3]),
      thumbType: 'image/jpeg',
      info: const ScreenshotInfo(method: 'native'),
      ms: 1,
    );
    expect(shot.thumbDataUrl, 'data:image/jpeg;base64,AQID');
  });
}
