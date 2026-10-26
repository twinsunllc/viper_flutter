// What the app keeps at the bottom of the screen, so the launcher's default spot sits above it
// (D351): a bottom navigation bar, a tab bar, a bottom app bar, anything in a Scaffold's bottom
// navigation slot or persistent footer.
import 'package:flutter/cupertino.dart' show CupertinoTabBar;
import 'package:flutter/material.dart' show BottomAppBar, BottomNavigationBar, NavigationBar;
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/mask.dart';

/// The Scaffold slots that hold a bar along the bottom edge.
const Set<String> _bottomSlots = {'_ScaffoldSlot.bottomNavigationBar', '_ScaffoldSlot.persistentFooter'};

/// How far above the bottom safe area the app's bottom bar reaches, in logical pixels; 0 when
/// there's none. Only bars that touch the bottom of the screen count, and only ones painted.
double bottomBarLift(Element root, {required Size screen, required EdgeInsets padding}) {
  var top = double.infinity;
  final theaters = <RenderObject>{};
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Overlay) {
      final theater = overlayTheater(element);
      if (theater != null) theaters.add(theater);
    }
    final bar =
        widget is NavigationBar ||
        widget is BottomNavigationBar ||
        widget is BottomAppBar ||
        widget is CupertinoTabBar ||
        (widget is LayoutId && _bottomSlots.contains(widget.id.toString()));
    if (bar) {
      final box = element.findRenderObject();
      // A bar on a covered route or a hidden tab isn't on screen.
      if (box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty && isPainted(box, theaters)) {
        final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
        if (rect.bottom >= screen.height - 1 && rect.top < top) top = rect.top;
      }
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  if (top == double.infinity) return 0;
  final lift = screen.height - top - padding.bottom;
  return lift > 0 ? lift : 0;
}
