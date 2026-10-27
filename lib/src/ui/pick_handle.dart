// While picking on a phone, the sheet is a handle across the bottom edge, where the thumb is
// (D169, W13), and the rest of the screen is the app to tap: a tap picks what's under it, a drag
// draws a box (D39). While the finger is down, what lifting it would pick is outlined and named
// in the handle, and sliding moves the aim, so a person sees what they'll get under their finger.
// The handle offers the whole screen, the dialog on top (W03's edge choices), or going back.
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/pick.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// The layer that takes the pick's tap or drag, under the handle.
class PickCatcher extends StatefulWidget {
  /// The catcher for [runtime].
  const PickCatcher({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  @override
  State<PickCatcher> createState() => _PickCatcherState();
}

class _PickCatcherState extends State<PickCatcher> {
  Offset? _start;
  Offset? _end;

  /// The finger that's aiming; a second finger is ignored.
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    if (runtime.pickMode != 'box') {
      // A tap picks on lift; a held finger aims first, outlined and named, and slides to change it.
      return Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: 'Tap what you mean',
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (_pointer != null) return;
                    _pointer = event.pointer;
                    runtime.aimAt(event.position);
                  },
                  onPointerMove: (event) {
                    if (event.pointer == _pointer) runtime.aimAt(event.position);
                  },
                  onPointerUp: (event) {
                    if (event.pointer != _pointer) return;
                    _pointer = null;
                    runtime.pickAt(event.position);
                  },
                  onPointerCancel: (event) {
                    if (event.pointer != _pointer) return;
                    _pointer = null;
                    runtime.clearAim();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            ValueListenableBuilder<PickAim?>(
              valueListenable: runtime.aim,
              builder: (context, aim, _) {
                final rect = aim?.rect;
                return rect == null ? const SizedBox.shrink() : PickOutline(rect: rect);
              },
            ),
          ],
        ),
      );
    }
    final box = runtime.pickMode == 'box';
    final rect = _start != null && _end != null ? Rect.fromPoints(_start!, _end!) : null;
    return Positioned.fill(
      child: Semantics(
        label: box ? 'Drag a box around what you mean' : 'Tap what you mean',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: box ? null : (details) => widget.runtime.pickAt(details.globalPosition),
          onPanStart: box ? (details) => setState(() => _start = _end = details.globalPosition) : null,
          onPanUpdate: box ? (details) => setState(() => _end = details.globalPosition) : null,
          onPanEnd: box
              ? (_) {
                  // Read the fields: the recognizer keeps the callback it started the drag with.
                  final drawn = _start != null && _end != null ? Rect.fromPoints(_start!, _end!) : null;
                  setState(() => _start = _end = null);
                  if (drawn != null) widget.runtime.pickBox(drawn);
                }
              : null,
          child: CustomPaint(painter: _BoxPainter(rect), child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter(this.rect);

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = rect;
    if (drawn == null) return;
    canvas.drawRect(drawn, Paint()..color = const Color(0x33C6F432));
    canvas.drawRect(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = viperSignal,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter oldDelegate) => oldDelegate.rect != rect;
}

/// The outline on what was picked, while the person writes about it (W03).
class PickOutline extends StatelessWidget {
  /// An outline around [rect].
  const PickOutline({required this.rect, super.key});

  /// What was picked, on the screen.
  final Rect rect;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect.inflate(3),
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: viperSignal, width: 2.5),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Color(0x6615171C), spreadRadius: 1)],
          ),
        ),
      ),
    );
  }
}

/// The picking handle.
class PickHandle extends StatelessWidget {
  /// The handle for [runtime].
  const PickHandle({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  /// The handle's Whole screen button, for tests and integration tests to find.
  static const ValueKey<String> wholeScreenKey = ValueKey<String>('viper-pick-whole-screen');

  /// The handle's This dialog button.
  static const ValueKey<String> dialogKey = ValueKey<String>('viper-pick-dialog');

  /// The handle's line naming what's aimed at, or what to do.
  static const ValueKey<String> aimKey = ValueKey<String>('viper-pick-aim');

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final dialog = runtime.pickDialogOpen;
    final words = runtime.pickMode == 'box' ? 'Drag a box around it' : 'Tap what you mean';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
        decoration: const BoxDecoration(
          color: viperInk,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x5215171C), blurRadius: 24, offset: Offset(0, -6))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<PickAim?>(
              valueListenable: runtime.aim,
              // Only the instruction is announced: a screen reader reading each aim as a finger
              // slides would never stop talking.
              builder: (context, aim, _) => Semantics(
                liveRegion: aim == null,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        aim?.label ?? words,
                        key: aimKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      if (runtime.pickMode != 'box') ...[
                        const SizedBox(height: 2),
                        Text(
                          aim != null
                              ? 'Lift to pick it, or slide to something else'
                              : "Or hold and slide to see what you'd pick",
                          style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _Button(
                    key: wholeScreenKey,
                    label: 'Whole screen',
                    primary: true,
                    onTap: runtime.pickWholeScreen,
                  ),
                ),
                if (dialog) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Button(key: dialogKey, label: 'This dialog', primary: false, onTap: runtime.pickDialog),
                  ),
                ],
                const SizedBox(width: 10),
                _Button(label: 'Cancel', primary: false, onTap: runtime.cancelPick),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.primary, required this.onTap, super.key});

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? viperSignal : const Color(0x00000000),
              borderRadius: BorderRadius.circular(10),
              border: primary ? null : Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: primary ? viperInk : const Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
