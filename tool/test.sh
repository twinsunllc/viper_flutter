#!/usr/bin/env bash
# Every test the package has, as CI runs them: the suite without the VIPER define (the markers
# fold to pass-throughs, D336), the markers again with it, and the example app's own tests.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test
flutter test --dart-define=VIPER=true test/markers_test.dart test/zone_test.dart
(cd example && flutter test)
