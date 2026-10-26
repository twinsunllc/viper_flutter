// The skeleton the sheet shows until the panel is ready (D44): the panel's layout (the ink header,
// the screen's name, the Report row, a list of items) in shimmering blocks, so the sheet is never
// blank. Still when the phone asks for reduced motion.
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/ui/tokens.dart';

/// The panel's layout in blocks.
class PanelSkeleton extends StatefulWidget {
  /// A skeleton in [palette].
  const PanelSkeleton({required this.palette, super.key});

  /// The theme's colors.
  final ViperPalette palette;

  @override
  State<PanelSkeleton> createState() => _PanelSkeletonState();
}

class _PanelSkeletonState extends State<PanelSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Semantics(
      label: 'Loading Viper',
      child: ExcludeSemantics(
        child: Container(
          color: palette.surface,
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (context, _) {
              final t = _shimmer.value;
              Widget block(double width, double height, {double radius = 6, Color? color}) => Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment(-1.5 + 3 * t, 0),
                    end: Alignment(-0.5 + 3 * t, 0),
                    colors: [color ?? palette.skeleton, palette.skeletonHighlight, color ?? palette.skeleton],
                  ),
                ),
              );
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 52,
                      color: palette.bar,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 120,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0x1AFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(child: block(double.infinity, 44, radius: 10)),
                          const SizedBox(width: 10),
                          block(44, 44, radius: 10),
                        ],
                      ),
                    ),
                    for (var i = 0; i < 5; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: palette.line)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            block(22, 22, radius: 11),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  block(i.isEven ? 210 : 160, 12),
                                  const SizedBox(height: 8),
                                  block(i.isEven ? 120 : 150, 10),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
