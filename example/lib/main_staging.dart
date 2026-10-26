// The staging entry point, and the only file that imports Viper's implementation (D336). Run it
// with the define that turns Viper on, and the local Viper's host and key:
//
//   flutter run -t lib/main_staging.dart --dart-define=VIPER=true \
//     --dart-define=VIPER_HOST=http://localhost:4830 --dart-define=VIPER_KEY=<the seeded key>
import 'package:viper_flutter/viper_flutter.dart';
import 'package:viper_flutter_example/app.dart' as app;

/// Viper's base URL. The default reaches a local Viper on port 4830 at localhost: the Mac itself
/// from the iOS simulator, and the Mac from an Android emulator after
/// `adb reverse tcp:4830 tcp:4830`. Not the emulator's 10.0.2.2 alias: over plain HTTP only
/// localhost is a secure context, and without one the web view sends no `Sec-Fetch-Site`, which
/// Viper needs to know the panel's own calls.
const String _host = String.fromEnvironment('VIPER_HOST', defaultValue: 'http://localhost:4830');

/// The environment's widget key, as `bin/rails db:seed` prints it. The default is the seeded
/// local environment of Harbor, which trusts this app's ID (D342).
const String _key = String.fromEnvironment('VIPER_KEY', defaultValue: 'hbr_loc_9w');

Uri get viperHost => Uri.parse(_host);

void main() => Viper.runZoned(
  () => app.main(
    onBoot: () {
      if (_key.isEmpty) {
        // ignore: avoid_print
        print('Viper: no VIPER_KEY given; run with --dart-define=VIPER_KEY=<key>. Viper is off.');
        return;
      }
      Viper.start(key: _key, host: viperHost, context: () => {'example': true});
    },
  ),
);
