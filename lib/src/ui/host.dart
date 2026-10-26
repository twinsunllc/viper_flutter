// What Viper.wrap puts over the app: the launcher and the sheet (W01, W13, D169, D335). The app
// stays first in the stack, in the same place whatever Viper does, so its state never resets.
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/launcher.dart';
import 'package:viper_flutter/src/ui/pick_handle.dart';
import 'package:viper_flutter/src/ui/sheet.dart';

/// The app with Viper over it.
class ViperHost extends StatelessWidget {
  /// Viper's [runtime] over [child].
  const ViperHost({required this.runtime, required this.child, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return Directionality(
      textDirection: direction,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // The app's own boundary: what the mask walk reads and toImage draws, never Viper's.
          RepaintBoundary(key: runtime.appKey, child: child),
          Positioned.fill(
            child: ListenableBuilder(
              listenable: runtime,
              builder: (context, _) => runtime.phase == ViperPhase.ready
                  // Hidden, not removed, for the frame a shot is taken: the web view stays alive.
                  ? Offstage(
                      offstage: runtime.capturing,
                      child: _ViperLayer(runtime: runtime),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViperLayer extends StatelessWidget {
  const _ViperLayer({required this.runtime});

  final ViperRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context) ?? MediaQueryData.fromView(View.of(context));
    return MediaQuery(
      data: media,
      // Viper's own layer: only its parts take touches; the rest of the screen is the app's.
      child: Stack(
        children: [
          ViperSheet(runtime: runtime),
          if (!runtime.sheetOpen && !runtime.layout.hidden) ViperLauncher(runtime: runtime),
          if (runtime.picking) PickHandle(runtime: runtime),
          ViperToastLayer(runtime: runtime),
        ],
      ),
    );
  }
}
