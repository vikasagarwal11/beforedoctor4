import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/tokens.dart';

enum WaveformMode { idle, listening, thinking }

class WaveformBars extends StatefulWidget {
  const WaveformBars({super.key, required this.mode});

  final WaveformMode mode;

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _rnd = math.Random(7);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _ampFor(int i, double t) {
    // Different feel per mode (wireframe only)
    final base = widget.mode == WaveformMode.idle ? 0.18 : widget.mode == WaveformMode.thinking ? 0.28 : 0.55;
    final wobble = widget.mode == WaveformMode.thinking ? 0.18 : 0.35;
    final phase = (i * 0.7) + (_rnd.nextDouble() * 0.25);
    final s = math.sin((t * 2 * math.pi) + phase).abs();
    return (base + s * wobble).clamp(0.12, 0.95);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: AppTokens.sm),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final bars = List.generate(12, (i) => _ampFor(i, t));
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final a in bars)
                _Bar(heightFactor: a, color: cs.primary.withOpacity(widget.mode == WaveformMode.thinking ? 0.55 : 0.75)),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.heightFactor, required this.color});

  final double heightFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}
