// What a phone's screenshot hides before it leaves the phone (D331, D67's levels):
//
//   Standard: obscured text fields, anything under ViperPrivate, every embedded web view.
//   Strict:   every text field, every image, every platform view, ViperPrivate.
//   Maximum:  all text and images except under ViperUnmask, every platform view.
//
// The boxes come from a walk of what is actually painted: a parent that doesn't paint a child
// (Offstage, an IndexedStack's hidden tabs, an Overlay's covered routes) hides that child's whole
// subtree, each box goes through every transform to the screen, and each is cut to what its
// ancestors' clips let show (a scrolled list's viewport, a ClipRRect), so a box never spills past
// what's visible. Logical pixels, filled natively before the PNG is encoded.
import 'package:flutter/material.dart' show Ink;
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

/// Widgets whose subtree is a web view, by type name for the ones from other packages (release
/// builds keep widget type names, the spike found).
const Set<String> webViewWidgetNames = {'WebViewWidget', 'InAppWebView', 'WebView', 'PlatformWebViewWidget'};

/// Widgets that paint a picture without a RenderImage: SVGs, vector graphics.
const Set<String> pictureWidgetNames = {'SvgPicture', 'VectorGraphic', 'Lottie', 'RiveAnimation'};

/// Render objects that paint a picture, for packages Viper doesn't depend on.
const Set<String> pictureRenderNames = {
  'RenderVectorGraphic',
  'RenderPictureProvider',
  'RenderSvgPicture',
  'RenderLottie',
};

/// The boxes to fill under [root] at [level], in the screen's logical pixels. [blockPlatformViews]
/// fills every platform view whatever the level, for a picture Flutter drew itself, where they
/// come out blank (D338).
List<Rect> maskBoxes(Element root, PrivacyLevel level, {bool blockPlatformViews = false}) {
  final private = <RenderObject>{};
  final unmasked = <RenderObject>{};
  final webViews = <RenderObject>{};
  final pictures = <RenderObject>{};
  final theaters = <RenderObject>{};
  void mark(Element element) {
    final widget = element.widget;
    final name = widget.runtimeType.toString();
    final set = widget is ViperPrivate
        ? private
        : widget is ViperUnmask
        ? unmasked
        : widget is WebViewWidget || webViewWidgetNames.contains(name)
        ? webViews
        : widget is Overlay
        ? theaters
        : pictureWidgetNames.contains(name) || (widget is Ink && _hasImage(widget.decoration))
        ? pictures
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
  void add(RenderObject node, Rect clip) {
    if (node is! RenderBox || !node.hasSize || node.size.isEmpty) return;
    final rect = MatrixUtils.transformRect(node.getTransformTo(null), Offset.zero & node.size).intersect(clip);
    if (rect.width > 0 && rect.height > 0 && rect.isFinite) boxes.add(rect);
  }

  void walk(RenderObject node, Rect clip, {required bool unmask}) {
    // ViperPrivate is masked at every level, ViperUnmask or not; so is a web view.
    if (private.contains(node) || webViews.contains(node)) {
      add(node, clip);
      return;
    }
    final isUnmasked = unmask || unmasked.contains(node);
    if (_isPlatformView(node)) {
      if (level != PrivacyLevel.standard || blockPlatformViews) add(node, clip);
      return;
    }
    // Every field at Strict and above; an obscured one always. ViperUnmask is for text and
    // images, never for what someone types.
    if (node is RenderEditable) {
      if (node.obscureText || level != PrivacyLevel.standard) add(node, clip);
      return;
    }
    final image = pictures.contains(node) || _isImage(node);
    if (image && (level == PrivacyLevel.strict || (level == PrivacyLevel.maximum && !isUnmasked))) {
      add(node, clip);
      return;
    }
    if (node is RenderParagraph && level == PrivacyLevel.maximum && !isUnmasked) {
      add(node, clip);
      return;
    }
    _paintedChildren(node, theaters, (child) {
      final local = node.describeApproximatePaintClip(child);
      final inner = local == null ? clip : MatrixUtils.transformRect(node.getTransformTo(null), local).intersect(clip);
      if (inner.width > 0 && inner.height > 0) walk(child, inner, unmask: isUnmasked);
    });
  }

  final screen = start is RenderBox && start.hasSize
      ? MatrixUtils.transformRect(start.getTransformTo(null), Offset.zero & start.size)
      : Rect.largest;
  walk(start, screen, unmask: false);
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

bool _hasImage(Decoration? decoration) => decoration is BoxDecoration && decoration.image != null;

/// A picture: an image, an image decoration (an avatar's backgroundImage), an SVG.
bool _isImage(RenderObject node) {
  if (node is RenderImage) return true;
  if (node is RenderDecoratedBox) return _hasImage(node.decoration);
  return pictureRenderNames.contains(node.runtimeType.toString());
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
