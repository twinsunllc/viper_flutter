// The production entry point: no Viper (D336). This file and everything it imports use only
// package:viper_flutter/markers.dart, so a build from here never contains the implementation,
// and without --dart-define=VIPER=true the markers fold away too.
import 'package:viper_flutter_example/app.dart' as app;

void main() => app.main();
