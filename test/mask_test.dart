// What each privacy level hides (D331, D67): the boxes the native side fills, checked against
// what's on screen, through clips, transforms, hidden tabs and scrolled lists.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/core/mask.dart';

/// A one-pixel PNG, so images lay out without the network.
final Uint8List pixel = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, //
  137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, //
  0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class FakePlatformView implements PlatformViewController {
  @override
  int get viewId => 7;

  @override
  bool get awaitingCreation => false;

  @override
  Future<void> create({Size? size, Offset? position}) async {}

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> dispose() async {}
}

/// Stand-ins named like other packages' widgets: Viper knows them by type name.
class SvgPicture extends StatelessWidget {
  const SvgPicture({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 30, height: 30);
}

class InAppWebView extends StatelessWidget {
  const InAppWebView({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 200, height: 80);
}

Widget screen() {
  final image = MemoryImage(pixel);
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const Text('Plain words', key: ValueKey('words')),
          const TextField(key: ValueKey('field')),
          const TextField(key: ValueKey('password'), obscureText: true),
          Image.memory(pixel, key: const ValueKey('image'), width: 40, height: 40),
          CircleAvatar(key: const ValueKey('avatar'), backgroundImage: image, radius: 20),
          Container(
            key: const ValueKey('decorated'),
            width: 40,
            height: 40,
            decoration: BoxDecoration(image: DecorationImage(image: image)),
          ),
          const ViperPrivate(child: Text('Private', key: ValueKey('private'))),
          ViperUnmask(
            child: Column(
              children: [
                const Text('Unmasked words', key: ValueKey('unmasked-words')),
                Image.memory(pixel, key: const ValueKey('unmasked-image'), width: 40, height: 40),
                const TextField(key: ValueKey('unmasked-field')),
              ],
            ),
          ),
          SizedBox(
            key: const ValueKey('platform'),
            height: 60,
            child: PlatformViewSurface(
              controller: FakePlatformView(),
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> pumpScreen(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

List<Rect> boxesAt(WidgetTester tester, PrivacyLevel level) => maskBoxes(tester.binding.rootElement!, level);

Rect editable(WidgetTester tester, String key) =>
    tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)));

bool covered(List<Rect> boxes, Rect target) => boxes.any((box) => box.overlaps(target.deflate(1)));

void main() {
  testWidgets('Standard hides passwords, ViperPrivate and web views only', (tester) async {
    await pumpScreen(tester, screen());
    final boxes = boxesAt(tester, PrivacyLevel.standard);
    expect(covered(boxes, editable(tester, 'password')), isTrue);
    expect(covered(boxes, tester.getRect(find.byKey(const ValueKey('private')))), isTrue);
    for (final shown in ['words', 'image', 'avatar', 'decorated', 'unmasked-words', 'platform']) {
      expect(covered(boxes, tester.getRect(find.byKey(ValueKey(shown)))), isFalse, reason: shown);
    }
    expect(covered(boxes, editable(tester, 'field')), isFalse);
    expect(boxes, hasLength(2));
  });

  testWidgets('Strict adds every field, every image (avatars, decorations) and every platform view', (tester) async {
    await pumpScreen(tester, screen());
    final boxes = boxesAt(tester, PrivacyLevel.strict);
    for (final hidden in ['image', 'avatar', 'decorated', 'unmasked-image', 'platform', 'private']) {
      expect(covered(boxes, tester.getRect(find.byKey(ValueKey(hidden)))), isTrue, reason: hidden);
    }
    for (final field in ['field', 'password', 'unmasked-field']) {
      expect(covered(boxes, editable(tester, field)), isTrue, reason: field);
    }
    expect(covered(boxes, tester.getRect(find.byKey(const ValueKey('words')))), isFalse);
  });

  testWidgets('Maximum hides all text and images except under ViperUnmask; fields and private stay hidden', (
    tester,
  ) async {
    await pumpScreen(tester, screen());
    final boxes = boxesAt(tester, PrivacyLevel.maximum);
    for (final hidden in ['words', 'image', 'avatar', 'decorated', 'platform', 'private']) {
      expect(covered(boxes, tester.getRect(find.byKey(ValueKey(hidden)))), isTrue, reason: hidden);
    }
    expect(
      covered(boxes, editable(tester, 'unmasked-field')),
      isTrue,
      reason: 'ViperUnmask never shows what someone types',
    );
    expect(covered(boxes, tester.getRect(find.byKey(const ValueKey('unmasked-words')))), isFalse);
    expect(covered(boxes, tester.getRect(find.byKey(const ValueKey('unmasked-image')))), isFalse);
  });

  testWidgets('a box is cut to the clips above it, and goes through transforms', (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 30,
                child: ClipRect(
                  child: OverflowBox(
                    maxHeight: 100,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      height: 100,
                      child: ViperPrivate(child: SizedBox.expand(key: ValueKey('tall'))),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 50),
              Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.diagonal3Values(2, 2, 1),
                child: ViperPrivate(child: SizedBox(key: ValueKey('scaled'), width: 50, height: 20)),
              ),
            ],
          ),
        ),
      ),
    );
    final boxes = boxesAt(tester, PrivacyLevel.standard);
    expect(boxes, hasLength(2));
    expect(boxes.first.height, 30, reason: 'cut to the ClipRect, not the 100 the child lays out');
    expect(boxes.last.size, const Size(100, 40), reason: 'scaled twice over');
  });

  testWidgets('a scrolled list masks only what shows inside its viewport', (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 100),
              SizedBox(
                height: 200,
                child: ListView(
                  key: const ValueKey('list'),
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 50, child: TextField(key: ValueKey('row-$i'), obscureText: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const ValueKey('list')), matching: find.byType(Scrollable)).first,
        )
        .position
        .jumpTo(118);
    await tester.pump();
    final viewport = tester.getRect(find.byKey(const ValueKey('list')));
    final boxes = boxesAt(tester, PrivacyLevel.standard);
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(
        viewport.inflate(0.01).contains(box.topLeft) && viewport.inflate(0.01).contains(box.bottomRight),
        isTrue,
        reason: '$box',
      );
    }
    // The row half scrolled off the top is cut where the viewport starts.
    expect(boxes.any((box) => (box.top - viewport.top).abs() < 0.01), isTrue);
  });

  testWidgets("a hidden tab's fields and pictures are never masked: they aren't painted", (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: IndexedStack(
            index: 0,
            children: [
              const Text('Shown tab'),
              Column(children: [const TextField(obscureText: true), Image.memory(pixel, width: 40, height: 40)]),
            ],
          ),
        ),
      ),
    );
    expect(boxesAt(tester, PrivacyLevel.strict), isEmpty);
    expect(boxesAt(tester, PrivacyLevel.maximum), hasLength(1), reason: 'the shown tab\'s words only');
  });

  testWidgets("another package's web view is masked at Standard, and its SVG from Strict, by name", (tester) async {
    await pumpScreen(
      tester,
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SvgPicture(key: ValueKey('svg')),
              InAppWebView(key: ValueKey('web')),
            ],
          ),
        ),
      ),
    );
    final web = tester.getRect(find.byKey(const ValueKey('web')));
    final svg = tester.getRect(find.byKey(const ValueKey('svg')));
    expect(covered(boxesAt(tester, PrivacyLevel.standard), web), isTrue);
    expect(covered(boxesAt(tester, PrivacyLevel.standard), svg), isFalse);
    expect(covered(boxesAt(tester, PrivacyLevel.strict), svg), isTrue);
  });

  testWidgets('text scrolled under a pinned, translucent header is still masked there (failing closed)', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            key: const ValueKey('scroll'),
            slivers: [
              const SliverAppBar(pinned: true, backgroundColor: Color(0x80FFFFFF), title: Text('Header')),
              SliverList.list(children: [for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('Row $i'))]),
            ],
          ),
        ),
      ),
    );
    tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const ValueKey('scroll')), matching: find.byType(Scrollable)).first,
        )
        .position
        .jumpTo(300);
    await tester.pump();
    final header = tester.getRect(find.byType(AppBar));
    final boxes = boxesAt(tester, PrivacyLevel.maximum);
    final under = boxes
        .where((box) => box.top < header.bottom - 1 && box != tester.getRect(find.text('Header')))
        .toList();
    expect(under, isNotEmpty, reason: 'the rows that scrolled under the header show through it');
  });
}
