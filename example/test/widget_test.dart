// The example app as the production entry point builds it: no Viper (D336).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter_example/app.dart';

void main() {
  testWidgets('every screen opens, with no Viper over it', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Job 1: Kakaako warehouse'), findsOneWidget);
    await tester.tap(find.text('Job 1: Kakaako warehouse'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsOneWidget);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Leave the crew?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    expect(find.text('Text it'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('password')), findsOneWidget);
    expect(find.byKey(const ValueKey('viper-launcher')), findsNothing);
    // The ways into Viper are staging's only (D371).
    expect(find.byKey(const ValueKey('report-a-bug')), findsNothing);
    expect(find.byKey(const ValueKey('show-viper')), findsNothing);
  });

  test('only main_staging.dart imports the implementation (D336)', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('main_staging.dart'))
        .where((f) => f.readAsStringSync().contains('package:viper_flutter/viper_flutter.dart'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
    expect(File('lib/main_staging.dart').readAsStringSync(), contains('package:viper_flutter/viper_flutter.dart'));
  });
}
