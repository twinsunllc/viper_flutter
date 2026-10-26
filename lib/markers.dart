/// What an app's shared code calls (D336): `Viper.wrap`, `Viper.observer()`, `Viper.recordError`,
/// `Viper.identify`, `Viper.context`, and the marker widgets `ViperScreen`, `ViperPrivate` and
/// `ViperUnmask`. Each is a pass-through until the staging entry point calls `Viper.start` from
/// `package:viper_flutter/viper_flutter.dart`, and folds to nothing in any build without
/// `--dart-define=VIPER=true`.
///
/// This library imports neither the implementation nor `dart:io`, so a production build that
/// imports only this never contains Viper, and shared widgets still build for the web.
library;

import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/slots.dart';

export 'package:viper_flutter/src/slots.dart'
    show IdentityRefresh, SignedIdentity, ViperNavigatorObserver, viperDefined;

/// Viper's calls for shared code. All of them do nothing until `Viper.start` runs.
abstract final class Viper {
  /// Puts Viper's launcher and sheet over the app. Use it in `MaterialApp.builder`, or anywhere
  /// above the app's navigator: `builder: (context, child) => Viper.wrap(child: child!)`.
  static Widget wrap({required Widget child}) {
    if (!viperDefined) return child;
    return _ViperSlot(child: child);
  }

  /// A navigator observer, one per navigator (the app's and each nested one), so Viper knows the
  /// screen (D332). Make it once and keep it in a field; a new one per build is never attached.
  static NavigatorObserver observer() {
    if (!viperDefined) return NavigatorObserver();
    return ViperNavigatorObserver();
  }

  /// Logs an error the app's own zone handler caught, beside Crashlytics or whatever else it
  /// reports to (D333). Viper never handles the error itself.
  static void recordError(Object error, StackTrace? stack) {
    if (!viperDefined) return;
    ViperSlots.handler.value?.recordError(error, stack);
  }

  /// Tells Viper who is signed in, from a signature the app's backend made (D21, D86), or null
  /// after sign-out. `refresh` is called for a fresh one before it expires.
  static void identify(SignedIdentity? identity, {IdentityRefresh? refresh}) {
    if (!viperDefined) return;
    final handler = ViperSlots.handler.value;
    if (handler != null) {
      handler.identify(identity, refresh: refresh);
      return;
    }
    ViperSlots.identityPending = true;
    ViperSlots.pendingIdentity = identity;
    ViperSlots.pendingRefresh = refresh;
  }

  /// Anything else worth logging with a capture (D27): feature flags, the account's plan, the
  /// record on screen. Merged by key; null removes a key. JSON values only.
  static void context(Map<String, Object?> values) {
    if (!viperDefined) return;
    final handler = ViperSlots.handler.value;
    if (handler != null) {
      handler.context(values);
      return;
    }
    ViperSlots.pendingContext.addAll(values);
  }
}

/// Holds the app in a stable place while the implementation arrives or leaves, so the app's own
/// state survives Viper starting after the first frame.
class _ViperSlot extends StatefulWidget {
  const _ViperSlot({required this.child});

  final Widget child;

  @override
  State<_ViperSlot> createState() => _ViperSlotState();
}

class _ViperSlotState extends State<_ViperSlot> {
  final GlobalKey _app = GlobalKey(debugLabel: 'viper app');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ViperSlotHandler?>(
      valueListenable: ViperSlots.handler,
      builder: (context, handler, _) {
        final app = KeyedSubtree(key: _app, child: widget.child);
        return handler == null ? app : handler.wrap(app);
      },
    );
  }
}

/// Names a screen (D332): its key and display name in Viper. Without it, the route's name is the
/// key, else the type of the widget the route built.
class ViperScreen extends StatelessWidget {
  /// Marks [child] as the screen called [name].
  const ViperScreen({required this.name, required this.child, super.key});

  /// The screen's name as people say it: "Cast hub".
  final String name;

  /// The screen.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Masked at every privacy level (D331): what's under it never leaves the phone.
class ViperPrivate extends StatelessWidget {
  /// Marks [child] as private.
  const ViperPrivate({required this.child, super.key});

  /// What is private.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Shown even at Maximum (D331): text and images under it are left unmasked.
class ViperUnmask extends StatelessWidget {
  /// Marks [child] as safe to show.
  const ViperUnmask({required this.child, super.key});

  /// What may be shown.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
