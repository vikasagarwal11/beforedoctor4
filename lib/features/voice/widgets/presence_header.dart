import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';

class PresenceHeader extends StatelessWidget {
  const PresenceHeader({
    super.key,
    required this.status,
    required this.toneLabel,
    required this.onToneTap,
  });

  final String status;
  final String toneLabel;
  final VoidCallback onToneTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Row(
      children: [
        const _BreathingDot(),
        const SizedBox(width: AppTokens.sm),
        Expanded(
          child: Text(status, style: t.titleMedium),
        ),
        OutlinedButton.icon(
          onPressed: onToneTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm, vertical: AppTokens.xs),
            textStyle: t.bodySmall?.copyWith(fontSize: 12),
            foregroundColor: c.onSurfaceVariant,
            side: BorderSide(color: c.outlineVariant),
          ),
          icon: const Icon(Icons.tune, size: 16),
          label: Text(toneLabel),
        ),
      ],
    );
  }
}

class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        final s = 18 + (_a.value * 6);
        return Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withOpacity(0.16 + _a.value * 0.08),
            border: Border.all(color: c.withOpacity(0.35 + _a.value * 0.35)),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.85)),
            ),
          ),
        );
      },
    );
  }
}

