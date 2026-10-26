// Where the launcher sits (D169, D295, D335): the project's starting placement, what the person
// did with it (dragged, tucked to an edge, hidden), and the geometry of each.
import 'package:flutter/widgets.dart';

/// The eight snap spots (W18): the corners and the middle of each edge.
const List<String> launcherSpots = [
  'top-left',
  'top',
  'top-right',
  'left',
  'right',
  'bottom-left',
  'bottom',
  'bottom-right',
];

/// The round launcher's size and its margin from the screen's safe edges.
const double launcherSize = 52;

/// The gap between the launcher and the safe area's edges.
const double launcherMargin = 16;

/// The edge tab's size (D295): 34 wide with 28 showing, 72 tall.
const Size edgeTabSize = Size(34, 72);

/// The project's placement, `LauncherPlacement` in the protocol.
@immutable
class ProjectPlacement {
  /// A placement.
  const ProjectPlacement({
    this.style = 'corner',
    this.spot = 'bottom-right',
    this.raise = 0,
    this.edgeSide = 'right',
    this.edgePosition = 50,
  });

  /// From the config's `launcher`, with the protocol's defaults for anything missing.
  factory ProjectPlacement.fromJson(Object? json) {
    if (json is! Map) return const ProjectPlacement();
    final spot = json['spot'];
    final side = json['edge_side'];
    return ProjectPlacement(
      style: json['style'] == 'edge_tab' ? 'edge_tab' : 'corner',
      spot: launcherSpots.contains(spot) ? spot as String : 'bottom-right',
      raise: (json['raise'] is num ? (json['raise'] as num).toDouble() : 0).clamp(0, 400).toDouble(),
      edgeSide: side == 'left' ? 'left' : 'right',
      edgePosition: (json['edge_position'] is num ? (json['edge_position'] as num).toDouble() : 50)
          .clamp(0, 100)
          .toDouble(),
    );
  }

  /// `corner` or `edge_tab`.
  final String style;

  /// The corner button's starting spot.
  final String spot;

  /// Px the button is raised from the bottom edge, on a bottom spot only.
  final double raise;

  /// The side the edge tab starts on.
  final String edgeSide;

  /// How far down the screen the tab's middle starts, a percent.
  final double edgePosition;
}

/// Where the launcher is now: the project's placement until the person moves it (D296), and
/// whether it's tucked or hidden (D335). Kept per install.
@immutable
class LauncherLayout {
  /// A layout.
  const LauncherLayout({
    required this.spot,
    required this.tucked,
    required this.edgeSide,
    required this.edgePosition,
    this.raise = 0,
    this.hidden = false,
    this.moved = false,
  });

  /// Where a project's placement starts it.
  factory LauncherLayout.fromProject(ProjectPlacement project, {bool hidden = false}) => LauncherLayout(
    spot: project.spot,
    tucked: project.style == 'edge_tab',
    edgeSide: project.edgeSide,
    edgePosition: project.edgePosition,
    raise: project.spot.startsWith('bottom') ? project.raise : 0,
    hidden: hidden,
  );

  /// What was kept on the phone, over the project's placement where the person never moved it.
  factory LauncherLayout.restore(Map<String, Object?>? kept, ProjectPlacement project) {
    final hidden = kept?['hidden'] == true;
    if (kept == null || kept['moved'] != true) return LauncherLayout.fromProject(project, hidden: hidden);
    final spot = kept['spot'];
    final position = kept['edge_position'];
    return LauncherLayout(
      spot: launcherSpots.contains(spot) ? spot as String : project.spot,
      tucked: kept['tucked'] == true,
      edgeSide: kept['edge_side'] == 'left' ? 'left' : 'right',
      edgePosition: position is num ? position.toDouble().clamp(0, 100).toDouble() : project.edgePosition,
      hidden: hidden,
      moved: true,
    );
  }

  /// The round button's spot.
  final String spot;

  /// Shown as the edge tab.
  final bool tucked;

  /// The tab's side.
  final String edgeSide;

  /// The tab's middle, a percent down the screen.
  final double edgePosition;

  /// The project's raise, while the person hasn't moved it.
  final double raise;

  /// Hidden until a shake brings it back (D335).
  final bool hidden;

  /// The person moved or tucked it, so the project's placement no longer applies.
  final bool moved;

  /// What's kept on the phone.
  Map<String, Object?> toJson() => {
    'spot': spot,
    'tucked': tucked,
    'edge_side': edgeSide,
    'edge_position': edgePosition,
    'hidden': hidden,
    'moved': moved,
  };

  /// A copy with changes.
  LauncherLayout copyWith({
    String? spot,
    bool? tucked,
    String? edgeSide,
    double? edgePosition,
    bool? hidden,
    bool? moved,
  }) => LauncherLayout(
    spot: spot ?? this.spot,
    tucked: tucked ?? this.tucked,
    edgeSide: edgeSide ?? this.edgeSide,
    edgePosition: edgePosition ?? this.edgePosition,
    raise: (moved ?? this.moved) ? 0 : raise,
    hidden: hidden ?? this.hidden,
    moved: moved ?? this.moved,
  );

  /// The round button's top left on a screen of [size] with [padding] for the safe area, above
  /// the app's bottom bar ([lift]) on a bottom spot unless the project raises it itself (D351).
  Offset buttonOffset(Size size, EdgeInsets padding, {double lift = 0}) =>
      spotOffset(spot, size, padding, raise: raise > 0 ? raise : lift);

  /// The edge tab's rectangle.
  Rect tabRect(Size size, EdgeInsets padding) {
    final top = padding.top + launcherMargin;
    final bottom = size.height - padding.bottom - launcherMargin - edgeTabSize.height;
    final middle = size.height * edgePosition / 100 - edgeTabSize.height / 2;
    final y = bottom < top ? top : middle.clamp(top, bottom).toDouble();
    final x = edgeSide == 'left' ? -6.0 : size.width - edgeTabSize.width + 6;
    return Rect.fromLTWH(x, y, edgeTabSize.width, edgeTabSize.height);
  }

  @override
  bool operator ==(Object other) =>
      other is LauncherLayout &&
      other.spot == spot &&
      other.tucked == tucked &&
      other.edgeSide == edgeSide &&
      other.edgePosition == edgePosition &&
      other.raise == raise &&
      other.hidden == hidden &&
      other.moved == moved;

  @override
  int get hashCode => Object.hash(spot, tucked, edgeSide, edgePosition, raise, hidden, moved);
}

/// The round button's top left at [spot].
Offset spotOffset(String spot, Size size, EdgeInsets padding, {double raise = 0}) {
  final left = padding.left + launcherMargin;
  final right = size.width - padding.right - launcherMargin - launcherSize;
  final top = padding.top + launcherMargin;
  final bottom = size.height - padding.bottom - launcherMargin - launcherSize - raise;
  final centerX = (size.width - launcherSize) / 2;
  final centerY = (size.height - launcherSize) / 2;
  return switch (spot) {
    'top-left' => Offset(left, top),
    'top' => Offset(centerX, top),
    'top-right' => Offset(right, top),
    'left' => Offset(left, centerY),
    'right' => Offset(right, centerY),
    'bottom-left' => Offset(left, bottom < top ? top : bottom),
    'bottom' => Offset(centerX, bottom < top ? top : bottom),
    _ => Offset(right, bottom < top ? top : bottom),
  };
}

/// The spot nearest to where a drag let go of the button (its top left at [offset]).
String nearestSpot(Offset offset, Size size, EdgeInsets padding) {
  var best = 'bottom-right';
  var distance = double.infinity;
  for (final spot in launcherSpots) {
    final d = (spotOffset(spot, size, padding) - offset).distanceSquared;
    if (d < distance) {
      distance = d;
      best = spot;
    }
  }
  return best;
}
