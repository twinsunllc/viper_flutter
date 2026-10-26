// The sheet the panel lives in (D169's phone layout, W13): up from the bottom, below the top
// safe area, rising with the keyboard. The web view inside is made once and kept; until the panel
// says viper:ready the sheet shows a skeleton in the panel's layout, never a blank view (D44).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/skeleton.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// The sheet's height on a screen of [height] with the keyboard taking [keyboard] and the top
/// safe area [top]: 82% of the screen and at most 720, never above the safe area.
double sheetHeight({required double height, required double top, required double keyboard}) {
  final room = height - top - keyboard - 8;
  final wanted = (height * 0.82).clamp(0, 720).toDouble();
  return wanted < room ? wanted : room.clamp(0, double.infinity).toDouble();
}

/// The sheet.
class ViperSheet extends StatefulWidget {
  /// The sheet for [runtime].
  const ViperSheet({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  @override
  State<ViperSheet> createState() => _ViperSheetState();
}

class _ViperSheetState extends State<ViperSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.runtime.sheetOpen ? 1 : 0,
  );

  @override
  void didUpdateWidget(ViperSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  void _follow() {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final open = widget.runtime.sheetOpen;
    if (open && _shown.value < 1) {
      if (reduced) {
        _shown.value = 1;
      } else {
        unawaited(_shown.forward());
      }
    } else if (!open && _shown.value > 0) {
      if (reduced) {
        _shown.value = 0;
      } else {
        unawaited(_shown.reverse());
      }
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final panel = runtime.panel;
    if (panel == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final height = sheetHeight(height: media.size.height, top: media.padding.top, keyboard: keyboard);
    final palette = runtime.palette;
    return AnimatedBuilder(
      animation: _shown,
      builder: (context, child) {
        final hidden = _shown.value == 0 && !runtime.sheetOpen;
        final offset = (1 - Curves.easeOutCubic.transform(_shown.value)) * (height + 24);
        return Positioned(
          left: 0,
          right: 0,
          bottom: keyboard,
          height: height,
          // Closed, it's kept but not drawn and never takes a touch; the web view stays alive.
          child: Offstage(
            offstage: hidden,
            // Closed, nothing in it animates: the skeleton's shimmer never costs a frame.
            child: TickerMode(
              enabled: !hidden,
              child: Transform.translate(offset: Offset(0, offset), child: child),
            ),
          ),
        );
      },
      child: Semantics(
        explicitChildNodes: true,
        scopesRoute: true,
        namesRoute: true,
        label: 'Viper',
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: palette.dark ? const Color(0xFF5A606A) : viperInk)),
            boxShadow: const [BoxShadow(color: Color(0x4015171C), blurRadius: 32, offset: Offset(0, -8))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: panel.build(context)),
                    if (!runtime.panelReady)
                      Positioned.fill(
                        child: runtime.loadFailed
                            ? _LoadFailed(palette: palette, onRetry: runtime.retryLoad)
                            : PanelSkeleton(palette: palette),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The panel didn't load: say so, and offer to try again.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.palette, required this.onRetry});

  final ViperPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.surface,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Viper can't be reached right now.",
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Check the connection, then try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.subtle, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: onRetry,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: viperInk, borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  'Try again',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
