// Where on the app a person is (D18, D332): the screen's key and name for ScreenRef, and the
// surface open on it.
//
//   - The screen is the page route on top of the innermost navigator that's on screen (a tab's own
//     navigator inside the app's, D332's nested navigators). Each navigator's current route is
//     read from the navigator itself, so an observer attached late still knows it.
//   - Its key is, in order: the nearest ViperScreen's name, the route's settings.name (other than
//     the "/" every first route gets), else the type of the widget the route built.
//   - A surface is a popup route on top (a dialog, a bottom sheet, a menu), an open drawer, or the
//     tab a navigation bar shows.
import 'package:flutter/material.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/core/mask.dart';
import 'package:viper_flutter/src/slots.dart';

/// Reads the current screen from the navigators Viper observes.
class ScreenTracker {
  /// A tracker over [observers], by default every observer the app made.
  ScreenTracker({List<ViperNavigatorObserver> Function()? observers})
    : _observers = observers ?? (() => ViperSlots.observers);

  final List<ViperNavigatorObserver> Function() _observers;

  /// The navigators on screen, innermost first.
  List<NavigatorState> _navigators() {
    final shown = <(int, NavigatorState)>[];
    for (final observer in _observers()) {
      final navigator = observer.navigator;
      if (navigator == null || !navigator.mounted) continue;
      final element = navigator.context as Element;
      if (!onScreen(element)) continue;
      var depth = 0;
      element.visitAncestorElements((_) {
        depth++;
        return true;
      });
      shown.add((depth, navigator));
    }
    shown.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, navigator) in shown) navigator];
  }

  /// The route on top of [navigator], read from the navigator, so a late observer still knows it.
  ///
  /// Navigator has no getter for its current route, so this asks popUntil, whose predicate is
  /// called with the top route first: answering true at once stops it before it pops anything.
  /// The predicate must always answer true; anything else would pop the app's own routes.
  static Route<dynamic>? topRoute(NavigatorState navigator) {
    Route<dynamic>? top;
    bool readOnly(Route<dynamic> route) {
      top ??= route;
      return true;
    }

    navigator.popUntil(readOnly);
    return top;
  }

  /// The page under any popup on the innermost navigator on screen.
  ModalRoute<dynamic>? topPage() {
    for (final navigator in _navigators()) {
      final page = _pageOf(navigator);
      if (page != null) return page;
    }
    return null;
  }

  ModalRoute<dynamic>? _pageOf(NavigatorState navigator) {
    final top = topRoute(navigator);
    if (top is PageRoute) return top;
    // A popup is on top: the page is the one under it, the last page route the observer saw, or
    // the route whose subtree is painted under the popup.
    for (final observer in _observers()) {
      if (observer.navigator != navigator) continue;
      for (final route in observer.routes.reversed) {
        if (route is PageRoute && route.isActive) return route;
      }
    }
    return null;
  }

  /// The popup on top of any navigator on screen: a dialog, a bottom sheet, a menu.
  PopupRoute<dynamic>? topPopup() {
    // The navigators on screen only: a popup on a hidden tab's own navigator isn't showing.
    for (final navigator in _navigators()) {
      final top = topRoute(navigator);
      if (top is PopupRoute && top.isActive) return top;
    }
    return null;
  }

  /// ScreenRef for where the person is now (D332). `url` is empty on a phone.
  Map<String, Object?> current({String? build, PrivacyLevel level = PrivacyLevel.standard}) {
    final page = topPage();
    final key = page == null ? '/' : screenKey(page);
    final surface = currentSurface(level: level);
    return {
      'route': key,
      'url': '',
      'title': page == null ? 'Home' : screenName(page, key),
      'build': ?build,
      'surface': ?surface,
    };
  }

  /// The surface open now (D18, D332): a popup route, an open drawer, or the tab on show.
  Map<String, Object?>? currentSurface({PrivacyLevel level = PrivacyLevel.standard}) {
    final popup = topPopup();
    if (popup != null) return surfaceOf(popup, level: level);
    final page = topPage();
    final pageContext = page?.subtreeContext;
    if (pageContext == null || !pageContext.mounted) return null;
    final scaffold = Scaffold.maybeOf(pageContext) ?? _findState<ScaffoldState>(pageContext as Element);
    if (scaffold != null && (scaffold.isDrawerOpen || scaffold.isEndDrawerOpen)) {
      return {'kind': 'drawer', 'key': scaffold.isDrawerOpen ? 'drawer' : 'end-drawer', 'name': 'Menu'};
    }
    // The tab bar is often outside the tab's own navigator: look on each page from the innermost out.
    for (final navigator in _navigators()) {
      final context = _pageOf(navigator)?.subtreeContext;
      if (context is! Element || !context.mounted) continue;
      final tab = _tabOf(context, level);
      if (tab != null) return tab;
    }
    return null;
  }
}

/// The key for a page route (D332).
String screenKey(ModalRoute<dynamic> route) {
  final context = route.subtreeContext;
  if (context is Element && context.mounted) {
    final named = _nearest<ViperScreen>(context);
    if (named != null) return named.name;
  }
  final name = route.settings.name;
  if (name != null && name.isNotEmpty && name != '/') return name;
  final built = context is Element && context.mounted ? builtWidgetType(context) : null;
  return built ?? name ?? '/';
}

/// The name people see for a screen: a ViperScreen's name as given, else the key said in words.
String screenName(ModalRoute<dynamic> route, String key) {
  final context = route.subtreeContext;
  if (context is Element && context.mounted && _nearest<ViperScreen>(context) != null) return key;
  return displayName(key);
}

/// A popup route as a ScreenRef surface.
Map<String, Object?> surfaceOf(PopupRoute<dynamic> route, {PrivacyLevel level = PrivacyLevel.standard}) {
  final context = route.subtreeContext;
  final element = context is Element && context.mounted ? context : null;
  final built = element == null ? null : builtWidgetType(element);
  final sheet = route is ModalBottomSheetRoute || route.runtimeType.toString().contains('BottomSheet');
  final menu = route.runtimeType.toString().contains('Menu');
  final key = route.settings.name ?? built ?? (sheet ? 'bottom-sheet' : 'dialog');
  final title = element == null || level == PrivacyLevel.maximum ? null : _dialogTitle(element);
  return {
    'kind': sheet || menu ? 'other' : 'dialog',
    'key': key,
    'name': title ?? (sheet ? 'Bottom sheet' : (menu ? 'Menu' : displayName(key))),
  };
}

/// The tab a navigation bar under [page] shows, as a surface.
Map<String, Object?>? _tabOf(Element page, PrivacyLevel level) {
  Map<String, Object?>? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    String? label;
    if (widget is NavigationBar && widget.selectedIndex < widget.destinations.length) {
      final destination = widget.destinations[widget.selectedIndex];
      label = destination is NavigationDestination ? destination.label : null;
    } else if (widget is BottomNavigationBar && widget.currentIndex < widget.items.length) {
      label = widget.items[widget.currentIndex].label;
    }
    if (label != null && onScreen(element)) {
      // At Maximum a tab is known by its place, not its words.
      final index = widget is NavigationBar ? widget.selectedIndex : (widget as BottomNavigationBar).currentIndex;
      found = level == PrivacyLevel.maximum
          ? {'kind': 'tab', 'key': 'tab:${index + 1}', 'name': 'Tab ${index + 1}'}
          : {'kind': 'tab', 'key': 'tab:${_slug(label)}', 'name': label};
      return;
    }
    element.visitChildElements(visit);
  }

  page.visitChildElements(visit);
  return found;
}

String _slug(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

String? _dialogTitle(Element element) {
  String? title;
  void visit(Element child) {
    if (title != null) return;
    final widget = child.widget;
    if (widget is AlertDialog && widget.title is Text) title = (widget.title! as Text).data;
    if (widget is SimpleDialog && widget.title is Text) title = (widget.title! as Text).data;
    if (title == null) child.visitChildElements(visit);
  }

  element.visitChildElements(visit);
  return title;
}

T? _nearest<T extends Widget>(Element root) {
  T? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget is T && onScreen(element)) {
      found = element.widget as T;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return found;
}

S? _findState<S extends State>(Element root) {
  S? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is S) {
      found = element.state as S;
      return;
    }
    element.visitChildElements(visit);
  }

  visit(root);
  return found;
}

/// Framework widgets a route wraps its content in, never the screen itself.
const Set<String> _frameworkWrappers = {
  'Builder',
  'PageStorage',
  'FocusScope',
  'Focus',
  'FocusTrap',
  'FocusTrapArea',
  'Actions',
  'Shortcuts',
  'AnimatedBuilder',
  'ListenableBuilder',
  'Material',
  'Theme',
  'SafeArea',
  'TickerMode',
  'Title',
  'DualTransitionBuilder',
  'Hero',
  'HeroControllerScope',
  'NotificationListener',
  'PopScope',
  'BackButtonListener',
  'ScrollConfiguration',
  'TextFieldTapRegion',
  'TapRegion',
  'Semantics',
  'MouseRegion',
  'Listener',
  'GestureDetector',
  'RawGestureDetector',
  'Dialog',
  'Align',
  'Center',
  'Padding',
  'ConstrainedBox',
  'Container',
  'CustomSingleChildLayout',
  'LayoutBuilder',
  'ValueListenableBuilder',
  'StreamBuilder',
  'DisplayFeatureSubScreen',
  'CapturedThemes',
  'InheritedTheme',
  'RestorationScope',
  'UnmanagedRestorationScope',
  'KeyedSubtree',
  'Offstage',
  'Visibility',
  'ExcludeSemantics',
  'FutureBuilder',
  'DefaultTextStyle',
  'IconTheme',
  'MediaQuery',
  'Directionality',
};

/// The type of the first widget under [root] that the app wrote: a screen or a dialog of its own,
/// read past the framework's route and transition wrappers. Release builds keep these names.
String? builtWidgetType(Element root) {
  String? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    final name = widget.runtimeType.toString();
    final candidate =
        (widget is StatelessWidget || widget is StatefulWidget) &&
        widget is! AnimatedWidget &&
        widget is! ImplicitlyAnimatedWidget &&
        !name.startsWith('_') &&
        !name.contains('<') &&
        !_frameworkWrappers.contains(name) &&
        !name.endsWith('Transition') &&
        !name.endsWith('TransitionsBuilder');
    if (candidate) {
      found = name;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return found;
}

/// Whether [element] is painted: on a route that shows, in the tab that shows (D331's walk).
bool onScreen(Element element) {
  final render = element.findRenderObject();
  if (render == null || !render.attached) return false;
  final theaters = <RenderObject>{};
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Overlay) {
      final theater = overlayTheater(ancestor);
      if (theater != null) theaters.add(theater);
    }
    return true;
  });
  return isPainted(render, theaters);
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
