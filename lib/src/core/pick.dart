// Picking what a person means (D332, W03, W17): a tap is hit tested in the app, the first target
// that is a render object (a TextSpan isn't) is mapped to the element that owns it by walking the
// element tree, which works in release builds, and the path up from it is the steps the panel's
// breadcrumb offers. The label comes from what the widget says: its semantics, its text, its type.
// An app's own tappable widget (an InkWell or GestureDetector that isn't part of a control) is a
// thing worth naming too, so a custom card or row picks as itself; a tap on nothing worth naming
// is the whole screen. While a finger is down the pick is aimed: what lifting would pick is
// outlined and named first (PickAim).
import 'package:flutter/cupertino.dart' show CupertinoNavigationBar, CupertinoTabBar;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:viper_flutter/markers.dart';
import 'package:viper_flutter/src/core/mask.dart';
import 'package:viper_flutter/src/core/screens.dart';

/// One step of a pick's path: the element and what to call it.
class PickedStep {
  /// A step.
  const PickedStep(this.element, this.label, this.widget);

  /// The element.
  final Element element;

  /// Plain words for it: "Save button".
  final String label;

  /// Its widget's type, for staff: "ElevatedButton".
  final String widget;
}

/// What lifting the finger would pick, shown while it's down: its name, and its box on the
/// screen (null for the whole screen).
@immutable
class PickAim {
  /// An aim at [label], outlined at [rect].
  const PickAim(this.label, this.rect);

  /// "Save button", or "Whole screen".
  final String label;

  /// Where it is on the screen, in logical pixels.
  final Rect? rect;

  @override
  bool operator ==(Object other) => other is PickAim && other.label == label && other.rect == rect;

  @override
  int get hashCode => Object.hash(label, rect);
}

/// Widgets a person means when they tap inside them, with the noun the label ends in.
const Map<String, String> _nouns = {
  'ElevatedButton': 'button',
  'FilledButton': 'button',
  'OutlinedButton': 'button',
  'TextButton': 'button',
  'IconButton': 'button',
  'FloatingActionButton': 'button',
  'CupertinoButton': 'button',
  'BackButton': 'button',
  'CloseButton': 'button',
  'PopupMenuButton': 'menu',
  'DropdownButton': 'menu',
  'DropdownMenu': 'menu',
  'TextField': 'field',
  'TextFormField': 'field',
  'CupertinoTextField': 'field',
  'Checkbox': 'checkbox',
  'CheckboxListTile': 'checkbox',
  'Switch': 'switch',
  'SwitchListTile': 'switch',
  'Radio': 'option',
  'RadioListTile': 'option',
  'Slider': 'slider',
  'Chip': 'chip',
  'ActionChip': 'chip',
  'FilterChip': 'chip',
  'ChoiceChip': 'chip',
  'InputChip': 'chip',
  'ListTile': 'row',
  'Card': 'card',
  'Image': 'image',
  'CircleAvatar': 'avatar',
  'NavigationDestination': 'tab',
  'BottomNavigationBar': 'navigation',
  'NavigationBar': 'navigation',
  'TabBar': 'tabs',
  'Tab': 'tab',
  'AppBar': 'header',
  'Drawer': 'menu',
  'AlertDialog': 'dialog',
  'SimpleDialog': 'dialog',
  'Dialog': 'dialog',
  'BottomSheet': 'sheet',
  'Text': 'text',
  'ExpansionTile': 'section',
  'Stepper': 'steps',
  'SegmentedButton': 'options',
  'SearchBar': 'search',
};

/// Widgets that hold a control: a tap on the text inside one means the control.
const Set<String> _controls = {
  'ElevatedButton',
  'FilledButton',
  'OutlinedButton',
  'TextButton',
  'IconButton',
  'FloatingActionButton',
  'CupertinoButton',
  'ListTile',
  'CheckboxListTile',
  'SwitchListTile',
  'RadioListTile',
  'Chip',
  'ActionChip',
  'FilterChip',
  'ChoiceChip',
  'InputChip',
  'NavigationDestination',
  'Tab',
  'TextField',
  'TextFormField',
  'CupertinoTextField',
  'PopupMenuButton',
  'DropdownButton',
  'DropdownMenu',
  'SegmentedButton',
};

/// Controls a tap handler can be part of: an InkWell inside one of these is the control's own.
const Set<String> _ownsTaps = {
  ..._controls,
  'Checkbox',
  'Switch',
  'Radio',
  'Slider',
  'BackButton',
  'CloseButton',
  'ExpansionTile',
  'Stepper',
  'SearchBar',
};

/// The element under [position] in the app below [root] (logical pixels, on the screen), or null.
/// [owners] (from [ownersOf]) saves walking the whole tree for each position of an aim.
Element? elementAt(Element root, Offset position, {Map<RenderObject, Element>? owners}) {
  final target = targetAt(root, position);
  return target == null ? null : ownerOf(root, target, owners: owners);
}

/// The render object a tap at [position] lands on first, or null.
RenderObject? targetAt(Element root, Offset position) {
  final render = root.findRenderObject();
  if (render is! RenderBox || !render.attached) return null;
  final result = BoxHitTestResult();
  render.hitTest(result, position: render.globalToLocal(position));
  // The first target that is a render object: a TextSpan answers before its RenderParagraph.
  for (final entry in result.path) {
    final candidate = entry.target;
    if (candidate is RenderObject) return candidate;
  }
  return null;
}

/// Every render object below [root] with the element that owns it: built once when a finger
/// goes down, so aiming as it moves is a lookup.
Map<RenderObject, Element> ownersOf(Element root) {
  final owners = Map<RenderObject, Element>.identity();
  void visit(Element element) {
    if (element is RenderObjectElement) owners[element.renderObject] = element;
    element.visitChildElements(visit);
  }

  visit(root);
  return owners;
}

/// The element that owns [target]: from [owners] while it's current, else by walking the tree.
Element? ownerOf(Element root, RenderObject target, {Map<RenderObject, Element>? owners}) {
  final known = owners?[target];
  if (known != null && known.mounted && known is RenderObjectElement && identical(known.renderObject, target)) {
    return known;
  }
  Element? owner;
  void visit(Element element) {
    if (owner != null) return;
    if (element is RenderObjectElement && identical(element.renderObject, target)) {
      owner = element;
      return;
    }
    element.visitChildElements(visit);
  }

  visit(root);
  return owner;
}

/// What a widget is worth naming: a control, a picture, text, a screen of the app's own, or
/// anything the app gave a ValueKey.
bool meaningful(Widget widget) {
  if (widget is ViperScreen) return true;
  final name = widget.runtimeType.toString();
  if (_nouns.containsKey(name)) return true;
  return widget.key is ValueKey && !name.startsWith('_');
}

/// What an element is worth naming: a [meaningful] widget, or a tap handler of the app's own
/// (a custom card or row), never one that's part of a control (a button's own InkWell).
bool meaningfulElement(Element element) => meaningful(element.widget) || _ownTappable(element);

/// Whether [widget] answers a tap: an InkWell or InkResponse, or a GestureDetector with a tap.
bool _tappable(Widget widget) {
  if (widget is InkResponse) return widget.onTap != null || widget.onLongPress != null;
  if (widget is GestureDetector) {
    return widget.onTap != null || widget.onTapUp != null || widget.onLongPress != null;
  }
  return false;
}

bool _ownTappable(Element element) {
  if (!_tappable(element.widget)) return false;
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Navigator || ancestor.widget is Overlay) return false;
    inside = _ownsTaps.contains(ancestor.widget.runtimeType.toString());
    return !inside;
  });
  return !inside;
}

/// Whether a tap on [picked] lands on anything worth naming. When it doesn't (the space between
/// widgets), the pick is the whole screen rather than a "Padding" or a "Column".
bool nameable(Element picked) {
  if (meaningfulElement(picked)) return true;
  var found = false;
  picked.visitAncestorElements((ancestor) {
    if (ancestor.widget is Navigator || ancestor.widget is Overlay) return false;
    found = meaningfulElement(ancestor);
    return !found;
  });
  return found;
}

/// The path from the screen down to the picked element, at most [depth] steps, the picked one last
/// (W17). Text inside a control is the control.
List<PickedStep> pathFor(Element picked, PrivacyLevel level, {int depth = 4}) {
  final chain = <Element>[];
  if (meaningfulElement(picked)) chain.add(picked);
  picked.visitAncestorElements((ancestor) {
    if (ancestor.widget is Navigator || ancestor.widget is Overlay) return false;
    if (meaningfulElement(ancestor)) chain.add(ancestor);
    return chain.length < depth + 3;
  });
  // A tap handler around a control (a TabBar's InkWell around its Tab) is the control again.
  for (var i = chain.length - 1; i > 0; i--) {
    if (_tappable(chain[i].widget) && _controls.contains(chain[i - 1].widget.runtimeType.toString())) {
      chain.removeAt(i);
    }
  }
  // A Dialog inside an AlertDialog is the same thing said twice.
  chain.removeWhere(
    (element) =>
        element.widget.runtimeType == Dialog &&
        chain.any((other) => other != element && (other.widget is AlertDialog || other.widget is SimpleDialog)),
  );
  // A tap on a button's words means the button, and on a tappable card's words, the card.
  while (chain.length > 1 &&
      chain.first.widget is Text &&
      (_controls.contains(chain[1].widget.runtimeType.toString()) || _tappable(chain[1].widget))) {
    chain.removeAt(0);
  }
  if (chain.isEmpty) chain.add(picked);
  final steps = chain.take(depth).toList().reversed;
  return [
    for (final element in steps) PickedStep(element, labelFor(element, level), element.widget.runtimeType.toString()),
  ];
}

/// Whether [element] is a ViperPrivate or sits under one: nothing it says leaves the phone, at
/// any level (D331), so its label is its kind and its anchor has no words.
bool underPrivate(Element element) {
  if (element.widget is ViperPrivate) return true;
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is ViperPrivate) found = true;
    return !found;
  });
  return found;
}

/// Plain words for what [element] is (W03): "Save button", "Password field", "Crew photo".
String labelFor(Element element, PrivacyLevel level) {
  final widget = element.widget;
  final type = widget.runtimeType.toString();
  if (widget is ViperScreen) return widget.name;
  final noun = _nouns[type];
  final private = underPrivate(element);
  final semantics = level == PrivacyLevel.maximum || private
      ? null
      : (_dialogTitle(widget) ?? semanticsLabelOf(element));
  final words = private
      ? null
      : semantics ??
            _fieldLabel(element, level) ??
            (noun == 'image' || noun == 'avatar' ? null : textOf(element, level));
  if (noun == null) {
    final key = widget.key;
    final keyed = key is ValueKey && !private ? displayName('${key.value}') : null;
    // A tap handler is named by what it shows: its type ("Ink well") means nothing to anyone.
    if (_tappable(widget)) return words ?? keyed ?? 'Button';
    return words ?? keyed ?? displayName(type);
  }
  if (noun == 'text') return words ?? 'Text';
  if (words == null || words.isEmpty) return _capital(noun);
  return '$words $noun';
}

/// A dialog is called by its title ("Edit cast dialog"), not the "Alert" its semantics say.
String? _dialogTitle(Widget widget) {
  final title = widget is AlertDialog ? widget.title : (widget is SimpleDialog ? widget.title : null);
  return title is Text && title.data != null ? _clip(title.data!) : null;
}

String _capital(String noun) => noun[0].toUpperCase() + noun.substring(1);

String? _fieldLabel(Element element, PrivacyLevel level) {
  final widget = element.widget;
  final decoration = widget is TextField ? widget.decoration : null;
  final label = decoration?.labelText ?? decoration?.hintText;
  if (label == null || label.isEmpty) return null;
  return level == PrivacyLevel.maximum ? null : _clip(label);
}

/// The semantics label a widget gives itself: a Semantics label, a tooltip. Never from under a
/// ViperPrivate (D331).
String? semanticsLabelOf(Element element) {
  if (underPrivate(element)) return null;
  final widget = element.widget;
  if (widget is Semantics && widget.properties.label != null) return _clip(widget.properties.label!);
  if (widget is IconButton && widget.tooltip != null) return _clip(widget.tooltip!);
  if (widget is FloatingActionButton && widget.tooltip != null) return _clip(widget.tooltip!);
  String? found;
  void visit(Element child) {
    if (found != null) return;
    final inner = child.widget;
    if (inner is ViperPrivate) return;
    if (inner is Semantics && inner.properties.label != null && inner.properties.label!.isNotEmpty) {
      found = _clip(inner.properties.label!);
      return;
    }
    if (inner is Tooltip && inner.message != null) {
      found = _clip(inner.message!);
      return;
    }
    child.visitChildElements(visit);
  }

  if (widget is Text || widget is RichText) return null;
  element.visitChildElements(visit);
  return found;
}

/// The words a widget shows, masked as the level says: none at Maximum, and none from a field
/// above Standard (what someone typed).
String? textOf(Element element, PrivacyLevel level) {
  if (level == PrivacyLevel.maximum || underPrivate(element)) return null;
  final parts = <String>[];
  void visit(Element child) {
    if (parts.join(' ').length > 60) return;
    final widget = child.widget;
    if (widget is ViperPrivate) return;
    if (widget is EditableText) return;
    // An icon is a glyph in a font, not words: a chevron would come out as a box.
    if (widget is Icon) return;
    if (widget is RichText) {
      final text = widget.text.toPlainText().replaceAll(_privateUse, '').trim();
      if (text.isNotEmpty) parts.add(text);
      return;
    }
    child.visitChildElements(visit);
  }

  visit(element);
  if (parts.isEmpty) return null;
  return _clip(parts.join(' '));
}

/// Icon fonts put their glyphs in Unicode's private use areas, which have no words in them.
final RegExp _privateUse = RegExp(r'[\u{E000}-\u{F8FF}\u{F0000}-\u{FFFFD}\u{100000}-\u{10FFFD}]', unicode: true);

String _clip(String text) {
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length > 60 ? '${one.substring(0, 59)}…' : one;
}

/// The element's box on screen, rounded, logical pixels.
Map<String, Object?>? boxOf(Element element) {
  final render = element.findRenderObject();
  if (render is! RenderBox || !render.attached || !render.hasSize) return null;
  final rect = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
  return {'x': rect.left.round(), 'y': rect.top.round(), 'width': rect.width.round(), 'height': rect.height.round()};
}

/// The anchor for [element] (D18, D332): its widget type, its ValueKey, its semantics label, its
/// text and its box. A drawn [box] is the anchor's own when no single widget was right (D39).
Map<String, Object?> anchorFor(Element element, PrivacyLevel level, {Map<String, Object?>? box}) {
  final widget = element.widget;
  final key = widget.key;
  final text = textOf(element, level);
  // A control's semantics label is its own, or the words it shows, as a screen reader says it.
  final semantics = level == PrivacyLevel.maximum
      ? null
      : semanticsLabelOf(element) ?? (_controls.contains(widget.runtimeType.toString()) ? text : null);
  final position = boxOf(element);
  return {
    'locators': {
      'widget': widget.runtimeType.toString(),
      // A key can carry the app's data (a ValueKey of an email): none from under ViperPrivate.
      if (key is ValueKey && key.value != null && !underPrivate(element)) 'key': '${key.value}',
      'semantics': ?semantics,
      'text': ?text,
      'position': ?position,
    },
    'box': ?box,
  };
}

/// A shared part a pick sits in (D48): the app's navigation bar or its header.
Map<String, Object?>? sharedPartOf(Element element) {
  Map<String, Object?>? part;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is NavigationBar || widget is BottomNavigationBar || widget is CupertinoTabBar) {
      part = {'key': 'navigation', 'name': 'Navigation bar'};
      return false;
    }
    if (widget is AppBar || widget is SliverAppBar || widget is CupertinoNavigationBar) {
      part = {'key': 'header', 'name': 'Header'};
      return false;
    }
    return ancestor.widget is! Navigator;
  });
  if (element.widget is NavigationBar || element.widget is BottomNavigationBar) {
    return {'key': 'navigation', 'name': 'Navigation bar'};
  }
  return part;
}

/// The widget an item's anchor points at, when it's on screen now (W07): by its key and type
/// first, then by its type and words. Null when it can't be found.
Element? findAnchor(Element root, Map<String, Object?>? locators) {
  if (locators == null) return null;
  final type = locators['widget'];
  final key = locators['key'];
  final text = locators['text'];
  if (type is! String) return null;
  Element? byKey;
  Element? byText;
  void visit(Element element) {
    if (byKey != null) return;
    final widget = element.widget;
    if (widget.runtimeType.toString() == type) {
      final own = widget.key;
      if (key is String && own is ValueKey && '${own.value}' == key) {
        byKey = element;
        return;
      }
      if (byText == null && key == null && text is String && textOf(element, PrivacyLevel.standard) == text) {
        byText = element;
      }
    }
    element.visitChildElements(visit);
  }

  visit(root);
  final found = byKey ?? byText;
  return found != null && onScreen(found) ? found : null;
}
