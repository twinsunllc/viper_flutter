// Each privacy level on the example's own screens (D331, flutter.md slice 3): the boxes Viper
// would fill, checked against what each screen shows, with the hidden tabs of the IndexedStack and
// a scrolled list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/mask.dart';
import 'package:viper_flutter_example/app.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ExampleApp());
  await tester.pumpAndSettle();
}

List<Rect> boxes(WidgetTester tester, PrivacyLevel level) => maskBoxes(tester.binding.rootElement!, level);

bool covered(List<Rect> boxes, Rect target) => boxes.any((box) => box.overlaps(target.deflate(1)));

Rect field(WidgetTester tester, String key) =>
    tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)));

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Jobs: Standard hides nothing; Maximum hides only the rows on screen, cut to the list', (tester) async {
    await pumpApp(tester);
    expect(boxes(tester, PrivacyLevel.standard), isEmpty, reason: "the Account tab's password is on a hidden tab");
    expect(boxes(tester, PrivacyLevel.strict), isEmpty, reason: 'no field, image or platform view on the Jobs tab');

    final list = tester.getRect(find.byKey(const ValueKey('job-list')));
    final maximum = boxes(tester, PrivacyLevel.maximum);
    expect(covered(maximum, tester.getRect(find.text('Job 1: Kakaako warehouse'))), isTrue);
    expect(covered(maximum, tester.getRect(find.text('Jobs').first)), isTrue, reason: 'the app bar title is text too');

    await tester.drag(find.byKey(const ValueKey('job-list')), const Offset(0, -900));
    await tester.pumpAndSettle();
    final scrolled = boxes(tester, PrivacyLevel.maximum).where((box) => box.overlaps(list)).toList();
    expect(scrolled, isNotEmpty);
    for (final box in scrolled) {
      expect(
        box.top >= list.top - 0.01 && box.bottom <= list.bottom + 0.01,
        isTrue,
        reason: 'cut to the list: $box in $list',
      );
    }
    expect(find.text('Job 1: Kakaako warehouse'), findsNothing, reason: 'scrolled away and gone from the tree');
  });

  testWidgets('Crew: the private phone number at every level; the photo from Strict; the words at Maximum', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTab(tester, 'Crew');
    final private = tester.getRect(find.text('Home phone: (808) 555-0142'));
    final photo = tester.getRect(find.byKey(const ValueKey('crew-image')));
    final lead = tester.getRect(find.text('Lead: Kalani Akana'));

    final standard = boxes(tester, PrivacyLevel.standard);
    expect(covered(standard, private), isTrue);
    expect(covered(standard, photo), isFalse);
    expect(covered(standard, lead), isFalse);

    final strict = boxes(tester, PrivacyLevel.strict);
    expect(covered(strict, private), isTrue);
    expect(covered(strict, photo), isTrue);
    expect(covered(strict, lead), isFalse);

    final maximum = boxes(tester, PrivacyLevel.maximum);
    expect(covered(maximum, private) && covered(maximum, photo) && covered(maximum, lead), isTrue);
    expect(
      maximum.where((box) => box.overlaps(photo)).every((box) => box.width <= photo.width + 0.01),
      isTrue,
      reason: 'the photo is cut to its ClipRRect',
    );
  });

  testWidgets('Crew: a dialog and a bottom sheet are masked as what is on top', (tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Crew');
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    final maximum = boxes(tester, PrivacyLevel.maximum);
    expect(covered(maximum, tester.getRect(find.text('Text it'))), isTrue);
    expect(covered(boxes(tester, PrivacyLevel.standard), tester.getRect(find.text('Text it'))), isFalse);
  });

  testWidgets('Account: the password at Standard; every field at Strict; the labels too at Maximum', (tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Account');
    final password = field(tester, 'password');
    final name = field(tester, 'name');
    final email = field(tester, 'email');
    final label = tester.getRect(find.text('Save'));

    final standard = boxes(tester, PrivacyLevel.standard);
    expect(covered(standard, password), isTrue);
    expect(covered(standard, name) || covered(standard, email), isFalse);

    final strict = boxes(tester, PrivacyLevel.strict);
    expect(covered(strict, password) && covered(strict, name) && covered(strict, email), isTrue);
    expect(covered(strict, label), isFalse);

    final maximum = boxes(tester, PrivacyLevel.maximum);
    expect(covered(maximum, label), isTrue);
  });

  testWidgets("a pushed route's screen is masked, never the one under it", (tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Account');
    await openTab(tester, 'Jobs');
    await tester.tap(find.text('Job 1: Kakaako warehouse'));
    await tester.pumpAndSettle();
    final maximum = boxes(tester, PrivacyLevel.maximum);
    expect(covered(maximum, tester.getRect(find.text('Accept'))), isTrue);
    expect(
      boxes(tester, PrivacyLevel.standard),
      isEmpty,
      reason: 'the list under it, and the hidden Account tab, are not painted',
    );
  });
}
