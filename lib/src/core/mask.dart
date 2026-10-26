// What a phone's screenshot hides before it leaves the phone (D331, D67's levels):
//
//   Standard: obscured text fields, anything under ViperPrivate, every embedded web view.
//   Strict:   every text field, every image, every platform view, ViperPrivate.
//   Maximum:  all text and images except under ViperUnmask, every platform view.
//
// The boxes come from a walk of what is actually painted: a parent that doesn't paint a child
// (Offstage, an IndexedStack's hidden tabs, Visibility) hides that child's whole subtree, and
// each box goes through every transform to the screen. Logical pixels, filled natively before the
// PNG is encoded.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/markers.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The privacy levels (D67).
enum PrivacyLevel {
  /// Passwords, private fields, web views.
  standard,

  /// Every field, image and platform view too.
  strict,

  /// All text and images, except what's unmasked.
  maximum;

  /// The level the config names, Standard when it names none.
  static PrivacyLevel parse(Object? value) => switch (value) {
    'strict' => strict,
    'maximum' => maximum,
    _ => standard,
  };
}

/// The boxes to fill under [root] at [level], in the screen's logical pixels. [blockPlatformViews]
/// fills every platform view whatever the level, for a picture Flutter drew itself, where they
/// come out blank (D338).
List<Rect> maskBoxes(Element root, PrivacyLevel level, {bool blockPlatformViews = false}) {
  final private = <RenderObject>{};
  final unmasked = <RenderObject>{};
  final webViews = <RenderObject>{};
  final theaters = <RenderObject>{};
  void mark(Element element) {
    final widget = element.widget;
    if (widget is Overlay) {
      final theater = _topRenderObject(element);
      if (theater != null) theaters.add(theater);
    }
    final set = widget is ViperPrivate
        ? private
        : widget is ViperUnmask
        ? unmasked
        : widget is WebViewWidget
        ? webViews
        : null;
    if (set != null) {
      final top = _topRenderObject(element);
      if (top != null) set.add(top);
    }
    element.visitChildElements(mark);
  }

  mark(root);
  final start = _topRenderObject(root);
  if (start == null) return const [];

  final boxes = <Rect>[];
  void add(RenderObject node) {
    if (node is! RenderBox || !node.hasSize || node.size.isEmpty) return;
    final rect = MatrixUtils.transformRect(node.getTransformTo(null), Offset.zero & node.size);
    if (!rect.isEmpty && rect.isFinite) boxes.add(rect);
  }

  void walk(RenderObject node, {required bool unmask}) {
    if (private.contains(node) || webViews.contains(node)) {
      add(node);
      return;
    }
    final isUnmasked = unmask || unmasked.contains(node);
    if (_isPlatformView(node)) {
      if (level != PrivacyLevel.standard || blockPlatformViews) add(node);
      return;
    }
    if (node is RenderEditable) {
      if (node.obscureText || level != PrivacyLevel.standard) add(node);
      return;
    }
    if (_isImage(node) && (level == PrivacyLevel.strict || (level == PrivacyLevel.maximum && !isUnmasked))) {
      add(node);
      return;
    }
    if (node is RenderParagraph && level == PrivacyLevel.maximum && !isUnmasked) {
      add(node);
      return;
    }
    _paintedChildren(node, theaters, (child) => walk(child, unmask: isUnmasked));
  }

  walk(start, unmask: false);
  return boxes;
}

RenderObject? _topRenderObject(Element element) {
  if (element is RenderObjectElement) return element.renderObject;
  RenderObject? found;
  void visit(Element child) {
    if (found != null) return;
    if (child is RenderObjectElement) {
      found = child.renderObject;
      return;
    }
    child.visitChildElements(visit);
  }

  element.visitChildElements(visit);
  return found;
}

bool _isPlatformView(RenderObject node) =>
    node is PlatformViewRenderBox || node is RenderAndroidView || node is RenderUiKitView || node is RenderAppKitView;

bool _isImage(RenderObject node) {
  if (node is RenderImage) return true;
  if (node is RenderDecoratedBox) {
    final decoration = node.decoration;
    return decoration is BoxDecoration && decoration.image != null;
  }
  return false;
}

/// The children [node] paints, failing closed: every child unless the node says it doesn't paint
/// it (`paintsChild`: Offstage, Opacity 0), and only two kinds narrowed further, whose hidden
/// children `paintsChild` doesn't report: an IndexedStack's other tabs, and the routes an Overlay
/// covers. Both visit only what they show for semantics. Anything else that leaves children out of
/// semantics (ExcludeSemantics, `Semantics(excludeSemantics: true)`) still paints them, so they
/// are walked.
void _paintedChildren(RenderObject node, Set<RenderObject> theaters, void Function(RenderObject child) visit) {
  void each(RenderObject child) {
    if (node.paintsChild(child)) visit(child);
  }

  if (node is RenderIndexedStack || theaters.contains(node)) {
    node.visitChildrenForSemantics(each);
  } else {
    node.visitChildren(each);
  }
}
