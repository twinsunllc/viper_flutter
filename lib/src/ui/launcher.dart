// The launcher (W01, D169, D295, D335): the round ink button with the Viper eye, or the slim edge
// tab. A tap opens the sheet; a drag moves the button to the nearest of the eight spots (or the
// tab along its edge); a long press offers tucking it to the edge or hiding it. It's one button
// for VoiceOver and TalkBack, with the counts in its label and the menu's choices as actions.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/obstruction.dart';
import 'package:viper_flutter/src/core/placement.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// What the launcher says for screen readers: "Viper, 5 open, 1 needs you".
String launcherLabel(int open, int needsYou) {
  final parts = ['Viper'];
  if (open > 0) parts.add('$open open');
  if (needsYou > 0) parts.add('$needsYou needs you');
  return parts.join(', ');
}

/// The launcher's button, for tests and integration tests to find.
const ValueKey<String> launcherButtonKey = ValueKey<String>('viper-launcher');

/// The launcher, wherever it sits.
class ViperLauncher extends StatefulWidget {
  /// The launcher for [runtime].
  const ViperLauncher({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  @override
  State<ViperLauncher> createState() => _ViperLauncherState();
}

class _ViperLauncherState extends State<ViperLauncher> {
  Offset? _drag;
  bool _menu = false;

  /// How far above the safe area the app's bottom bar reaches: a bottom spot sits above it (D351).
  double _lift = 0;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // Bars come and go with the app's screens; a look a second is cheap and keeps up.
    _watch = Timer.periodic(const Duration(seconds: 1), (_) => _measure());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  void _measure() {
    // Only the round button sits on a bottom spot; a tucked tab has nothing to keep clear of.
    if (!mounted || _drag != null || widget.runtime.layout.tucked) return;
    final root = widget.runtime.appKey.currentContext;
    if (root is! Element) return;
    final media = MediaQuery.of(context);
    final lift = bottomBarLift(root, screen: media.size, padding: media.padding);
    if ((lift - _lift).abs() > 0.5) setState(() => _lift = lift);
  }

  ViperRuntime get _runtime => widget.runtime;

  void _open() {
    setState(() => _menu = false);
    _runtime.openSheet();
  }

  void _tuck(bool tucked) {
    setState(() => _menu = false);
    _runtime.setTucked(tucked);
  }

  void _hide() {
    setState(() => _menu = false);
    _runtime.setHidden(true);
    _runtime.showToast(_runtime.hiddenToast);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final padding = media.padding;
    final layout = _runtime.layout;
    final palette = _runtime.palette;
    final label = launcherLabel(_runtime.openCount, _runtime.needsYou);
    final actions = <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(label: layout.tucked ? 'Show the round button' : 'Tuck to the edge'): () =>
          _tuck(!layout.tucked),
      if (_runtime.canHide) const CustomSemanticsAction(label: 'Hide Viper'): _hide,
    };

    final Rect rect;
    final Widget body;
    if (layout.tucked) {
      final tab = layout.tabRect(size, padding);
      final top = _drag == null
          ? tab.top
          : _drag!.dy.clamp(padding.top, size.height - padding.bottom - tab.height).toDouble();
      rect = Rect.fromLTWH(tab.left, top, tab.width, tab.height);
      body = _EdgeTab(
        palette: palette,
        open: _runtime.openCount,
        needsYou: _runtime.needsYou,
        left: layout.edgeSide == 'left',
      );
    } else {
      final at = _drag ?? layout.buttonOffset(size, padding, lift: _lift);
      rect = Rect.fromLTWH(at.dx, at.dy, launcherSize, launcherSize);
      body = _RoundButton(
        palette: palette,
        open: _runtime.openCount,
        needsYou: _runtime.needsYou,
        lifted: _drag != null,
      );
    }

    return Stack(
      children: [
        if (_menu)
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _menu = false)),
          ),
        Positioned.fromRect(
          rect: rect,
          child: Semantics(
            container: true,
            button: true,
            label: label,
            hint: 'Opens Viper',
            customSemanticsActions: actions,
            onTap: _open,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: launcherButtonKey,
                behavior: HitTestBehavior.opaque,
                onTap: _open,
                onLongPress: () => setState(() => _menu = true),
                onPanStart: (details) => setState(() {
                  _menu = false;
                  _drag = rect.topLeft;
                }),
                onPanUpdate: (details) => setState(() {
                  final next = (_drag ?? rect.topLeft) + details.delta;
                  _drag = layout.tucked ? Offset(rect.left, next.dy) : next;
                }),
                onPanEnd: (_) => _dropAt(size, padding),
                onPanCancel: () => setState(() => _drag = null),
                child: body,
              ),
            ),
          ),
        ),
        if (_menu)
          _Menu(
            palette: palette,
            anchor: rect,
            screen: size,
            tucked: layout.tucked,
            canHide: _runtime.canHide,
            onTuck: () => _tuck(!layout.tucked),
            onHide: _hide,
            onCancel: () => setState(() => _menu = false),
          ),
      ],
    );
  }

  void _dropAt(Size size, EdgeInsets padding) {
    final drag = _drag;
    if (drag == null) return;
    final layout = _runtime.layout;
    if (layout.tucked) {
      final middle = drag.dy + edgeTabSize.height / 2;
      _runtime.moveLauncher(layout.copyWith(edgePosition: (middle / size.height * 100).clamp(0, 100).toDouble()));
    } else {
      _runtime.moveLauncher(layout.copyWith(spot: nearestSpot(drag, size, padding, lift: _lift)));
    }
    setState(() => _drag = null);
  }
}

/// The round launcher (W01): ink, the eye, the open count and the needs-you dot.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.palette, required this.open, required this.needsYou, required this.lifted});

  final ViperPalette palette;
  final int open;
  final int needsYou;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: launcherSize,
          height: launcherSize,
          decoration: BoxDecoration(
            color: viperInk,
            shape: BoxShape.circle,
            border: Border.all(color: viperInk),
            boxShadow: [
              BoxShadow(color: palette.shadow, blurRadius: lifted ? 36 : 24, offset: Offset(0, lifted ? 18 : 10)),
              BoxShadow(color: palette.halo, spreadRadius: 3),
            ],
          ),
          alignment: Alignment.center,
          child: const CustomPaint(size: Size.square(28), painter: ProbePainter()),
        ),
        if (open > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: palette.countBackground,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: viperInk, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                open > 99 ? '99+' : '$open',
                textScaler: scale,
                style: const TextStyle(color: viperInk, fontSize: 11, fontWeight: FontWeight.w700, height: 1),
              ),
            ),
          ),
        if (needsYou > 0)
          Positioned(
            bottom: -1,
            right: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: viperNeeds,
                shape: BoxShape.circle,
                border: Border.all(color: palette.dark ? const Color(0xFF171A1F) : const Color(0xFFFFFFFF), width: 2.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// The edge tab (D295): slim ink, flush on its side, the eye over the open count, the dot below.
class _EdgeTab extends StatelessWidget {
  const _EdgeTab({required this.palette, required this.open, required this.needsYou, required this.left});

  final ViperPalette palette;
  final int open;
  final int needsYou;
  final bool left;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(12);
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Container(
      padding: EdgeInsets.only(left: left ? 6 : 0, right: left ? 0 : 6),
      decoration: BoxDecoration(
        color: viperInk,
        borderRadius: left ? const BorderRadius.horizontal(right: radius) : const BorderRadius.horizontal(left: radius),
        boxShadow: [
          BoxShadow(color: palette.shadow, blurRadius: 24, offset: Offset(left ? 6 : -6, 8)),
          BoxShadow(color: palette.halo, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CustomPaint(size: Size.square(20), painter: ProbePainter(small: true)),
          if (open > 0) ...[
            const SizedBox(height: 6),
            Text(
              open > 99 ? '99+' : '$open',
              textScaler: scale,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: FontWeight.w700, height: 1),
            ),
          ],
          if (needsYou > 0) ...[
            const SizedBox(height: 6),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: viperNeeds, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

/// The long press's choices, beside the launcher.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.palette,
    required this.anchor,
    required this.screen,
    required this.tucked,
    required this.canHide,
    required this.onTuck,
    required this.onHide,
    required this.onCancel,
  });

  final ViperPalette palette;
  final Rect anchor;
  final Size screen;
  final bool tucked;
  final bool canHide;
  final VoidCallback onTuck;
  final VoidCallback onHide;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    const width = 220.0;
    final rows = <Widget>[
      _MenuRow(label: tucked ? 'Show the round button' : 'Tuck to the edge', palette: palette, onTap: onTuck),
      if (canHide) _MenuRow(label: 'Hide Viper', palette: palette, onTap: onHide),
      _MenuRow(label: 'Cancel', palette: palette, onTap: onCancel, subtle: true),
    ];
    final height = rows.length * 48.0 + 8;
    final below = anchor.top < screen.height / 2;
    final left = (anchor.center.dx - width / 2).clamp(12, math.max(12, screen.width - width - 12)).toDouble();
    final top = below ? anchor.bottom + 10 : anchor.top - height - 10;
    return Positioned(
      left: left,
      top: top.clamp(12, math.max(12, screen.height - height - 12)).toDouble(),
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.line),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, required this.palette, required this.onTap, this.subtle = false});

  final String label;
  final ViperPalette palette;
  final VoidCallback onTap;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(color: subtle ? palette.subtle : palette.text, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// A short note at the bottom of the screen, such as how to bring a hidden Viper back.
class ViperToastLayer extends StatelessWidget {
  /// The toast for [runtime].
  const ViperToastLayer({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final text = runtime.toast;
    if (text == null) return const SizedBox.shrink();
    final padding = MediaQuery.paddingOf(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: padding.bottom + 24,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: viperInk, borderRadius: BorderRadius.circular(10)),
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Viper mark (PROBE_SVG in the loader): a white ring, the lime eye, and on the large one the
/// three legs.
class ProbePainter extends CustomPainter {
  /// The mark, [small] without the legs.
  const ProbePainter({this.small = false});

  /// Leaves the legs off, as the edge tab's mark does.
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(const Offset(12, 11), 7, ring);
    canvas.drawCircle(const Offset(14.4, 10.2), 2.4, Paint()..color = viperSignal);
    if (small) return;
    final legs = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawLine(const Offset(9, 18.6), const Offset(8, 21), legs);
    canvas.drawLine(const Offset(12, 19), const Offset(12, 21.4), legs);
    canvas.drawLine(const Offset(15, 18.6), const Offset(16, 21), legs);
  }

  @override
  bool shouldRepaint(ProbePainter oldDelegate) => oldDelegate.small != small;
}
