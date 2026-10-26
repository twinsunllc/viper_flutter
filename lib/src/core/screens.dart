// Where on the app a person is (D18, D332): the screen's key and name for ScreenRef. A route's
// name is the key when it has one; ViperScreen and the type of the widget a route built come with
// the pick (slice 5).
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/slots.dart';

/// Reads the current screen from the navigators Viper observes.
class ScreenTracker {
  /// A tracker over [observers], by default every observer the app made.
  ScreenTracker({List<ViperNavigatorObserver> Function()? observers})
    : _observers = observers ?? (() => ViperSlots.observers);

  final List<ViperNavigatorObserver> Function() _observers;

  /// The page route on top of the first navigator that has one: the screen under any dialog.
  Route<dynamic>? topPage() {
    for (final observer in _observers()) {
      final navigator = observer.navigator;
      if (navigator == null || !navigator.mounted) continue;
      for (final route in observer.routes.reversed) {
        if (route is PageRoute && route.isActive) return route;
      }
    }
    return null;
  }

  /// ScreenRef for where the person is now (D332). `url` is empty on a phone.
  Map<String, Object?> current({String? build}) {
    final route = topPage();
    final key = route?.settings.name ?? '/';
    return {'route': key, 'url': '', 'title': displayName(key), 'build': ?build};
  }
}

/// A screen's name as people say it (D332): "CastHubScreen" is "Cast hub", "/cast-hub" is "Cast
/// hub", and "/" is "Home".
String displayName(String key) {
  var name = key.trim();
  if (name == '/' || name.isEmpty) return 'Home';
  name = name.replaceAll(RegExp(r'^/+|/+$'), '');
  if (name.contains('/')) name = name.split('/').where((part) => part.isNotEmpty && !part.startsWith(':')).last;
  name = name.replaceAll(RegExp(r'(Screen|Page|View|Route)$'), '');
  final words = name
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[\s_\-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return key;
  final first = words.first;
  return [
    first[0].toUpperCase() + (first == first.toUpperCase() ? first.substring(1) : first.substring(1).toLowerCase()),
    for (final w in words.skip(1)) w == w.toUpperCase() && w.length > 1 ? w : w.toLowerCase(),
  ].join(' ');
}
