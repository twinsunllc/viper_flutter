// The slots shared code calls through (D336). markers.dart forwards to them; the implementation
// fills them when Viper.start runs. This file imports only Flutter's widgets layer: never the
// implementation and never dart:io, so shared widgets still build for the web.
import 'package:flutter/widgets.dart';

/// True only in a build given `--dart-define=VIPER=true` (the staging flavor's define file). A
/// const, so in every other build the compiler folds each check to false and drops what it guards.
const bool viperDefined = bool.fromEnvironment('VIPER');

/// The identity the app's backend signed (D21, D86), as JSON: `{v: 1, payload: {...}, signature}`.
typedef SignedIdentity = Map<String, Object?>;

/// Asks the app's backend for a fresh signature before the last one expires.
typedef IdentityRefresh = Future<SignedIdentity?> Function();

/// What the implementation does for each call shared code makes.
abstract interface class ViperSlotHandler {
  /// The app with Viper's launcher and sheet over it.
  Widget wrap(Widget child);

  /// An error the app's own zone handler caught (D333).
  void recordError(Object error, StackTrace? stack);

  /// Who is signed in, or null after sign-out (D21).
  void identify(SignedIdentity? identity, {IdentityRefresh? refresh});

  /// Anything else worth logging with a capture (D27): merged by key, null removes a key.
  void context(Map<String, Object?> values);

  /// A navigator an observer watches changed its routes.
  void routesChanged(ViperNavigatorObserver observer);

  /// The app's own way back (D371): a hidden launcher shows again, remembered per install.
  void show();

  /// The app's own way in (D371): shows the launcher if hidden and opens the sheet, as a tap on
  /// the launcher does.
  void open();
}

/// The slots, empty until Viper.start fills them.
abstract final class ViperSlots {
  /// Notifies when the handler arrives or leaves, so a wrap built earlier picks it up.
  static final ValueNotifier<ViperSlotHandler?> handler = ValueNotifier<ViperSlotHandler?>(null);

  /// Every observer made so far, in the order they were made, held weakly so an app that drops
  /// one doesn't keep it alive.
  static final List<WeakReference<ViperNavigatorObserver>> _observers = <WeakReference<ViperNavigatorObserver>>[];

  /// The observers still alive, oldest first.
  static List<ViperNavigatorObserver> get observers {
    _observers.removeWhere((ref) => ref.target == null);
    return [for (final ref in _observers) ?ref.target];
  }

  /// Called by each observer as it's made.
  static void addObserver(ViperNavigatorObserver observer) {
    _observers.removeWhere((ref) => ref.target == null);
    _observers.add(WeakReference(observer));
  }

  /// What identify and context said before Viper.start ran, handed over when it does.
  static SignedIdentity? pendingIdentity;

  /// The refresh callback that came with [pendingIdentity].
  static IdentityRefresh? pendingRefresh;

  /// Whether identify was called before start (null is a real answer: signed out).
  static bool identityPending = false;

  /// Context set before start.
  static final Map<String, Object?> pendingContext = <String, Object?>{};
}

/// One per navigator (D332): tells the implementation when that navigator's routes change. Hold it
/// in state rather than building a new one in `build`, since a navigator keeps the observers it
/// was first given.
class ViperNavigatorObserver extends NavigatorObserver {
  /// Registers itself so the implementation can read each navigator's current route.
  ViperNavigatorObserver() {
    ViperSlots.addObserver(this);
  }

  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  /// The routes this observer has seen pushed and not yet popped, bottom first. An observer
  /// attached after its navigator's first route misses that one; the implementation reads the
  /// navigator itself for it.
  List<Route<dynamic>> get routes => List.unmodifiable(_routes);

  void _changed() => ViperSlots.handler.value?.routesChanged(this);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute != null) {
      if (at >= 0) {
        _routes[at] = newRoute;
      } else {
        _routes.add(newRoute);
      }
    } else if (at >= 0) {
      _routes.removeAt(at);
    }
    _changed();
  }
}
