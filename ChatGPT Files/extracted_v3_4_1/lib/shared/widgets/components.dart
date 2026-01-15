import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/tokens.dart';

export 'states.dart';
export 'link_pills.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: t.titleMedium),
        if (action != null) action!,
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.icon, this.color, this.onTap});

  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.rPill),
      onTap: onTap,
      child: Container(
        height: AppTokens.chipH,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          border: Border.all(color: c.withOpacity(0.35)),
          color: c.withOpacity(0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: AppTokens.xs),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

class MicFab extends StatelessWidget {
  const MicFab({super.key, required this.isRecording, required this.onPressed});

  final bool isRecording;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isRecording ? AppColors.danger : scheme.primary;
    return GestureDetector(
      onLongPressStart: (_) => onPressed(),
      onLongPressEnd: (_) => onPressed(),
      child: AnimatedContainer(
        duration: AppTokens.medium,
        width: AppTokens.fab,
        height: AppTokens.fab,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: bg.withOpacity(0.35),
              blurRadius: isRecording ? 22 : 14,
              spreadRadius: isRecording ? 2 : 0,
            ),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 28),
      ),
    );
  }
}

/// Pure UI waveform placeholder (no audio lib). Feels "alive" for wireframing.
class FakeWaveform extends StatefulWidget {
  const FakeWaveform({super.key, required this.isActive});

  final bool isActive;

  @override
  State<FakeWaveform> createState() => _FakeWaveformState();
}

class _FakeWaveformState extends State<FakeWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.isActive) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant FakeWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_c.isAnimating) _c.repeat();
    if (!widget.isActive && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return CustomPaint(
            painter: _WavePainter(progress: t, color: scheme.primary),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.8);

    final mid = size.height / 2;
    final w = size.width;
    final n = 32;
    final dx = w / (n - 1);

    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = i * dx;
      final phase = (i / n * pi * 2) + (progress * pi * 2);
      final amp = (sin(progress * pi * 2) * 0.5 + 0.5) * 10 + 4;
      final y = mid + sin(phase) * amp * (0.55 + (i % 5) / 10);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
