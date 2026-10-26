// Viper's zone around the app's main (D333): what the app prints reaches the console, and still
// prints. `tool/test.sh` runs this with --dart-define=VIPER=true; without it, runZoned is the
// body itself.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/viper_flutter.dart';

void main() {
  test('print inside Viper.runZoned is kept, and printed as the app meant', () {
    final printed = <String>[];
    Zone.current.fork(specification: ZoneSpecification(print: (_, _, _, line) => printed.add(line))).run(() {
      Viper.runZoned(() {
        // ignore: avoid_print
        print('Saving the profile');
        debugPrint('A debug line');
      });
    });
    expect(printed, ['Saving the profile', 'A debug line']);
    expect(
      Viper.activity.console.map((line) => line.text),
      viperDefined ? containsAll(['Saving the profile', 'A debug line']) : isEmpty,
    );
  });
}
