// While picking on a phone, the sheet is a handle across the bottom edge, where the thumb is
// (D169, W13). Tapping an element comes in slice 5; for now the handle offers the whole screen
// (W03's edge choices) or going back.
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/runtime.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// The picking handle.
class PickHandle extends StatelessWidget {
  /// The handle for [runtime].
  const PickHandle({required this.runtime, super.key});

  /// Viper running.
  final ViperRuntime runtime;

  /// The handle's Whole screen button, for tests and integration tests to find.
  static const ValueKey<String> wholeScreenKey = ValueKey<String>('viper-pick-whole-screen');

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
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
        child: Row(
          children: [
            Expanded(
              child: _Button(
                key: wholeScreenKey,
                label: 'Whole screen',
                primary: true,
                onTap: runtime.pickWholeScreen,
              ),
            ),
            const SizedBox(width: 10),
            _Button(label: 'Cancel', primary: false, onTap: runtime.cancelPick),
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
