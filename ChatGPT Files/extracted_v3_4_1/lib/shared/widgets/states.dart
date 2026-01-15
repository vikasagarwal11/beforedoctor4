import 'package:flutter/material.dart';
import '../../core/constants/tokens.dart';
import '../../app/app_state.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    if (!state.offline) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.md),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.35)),
        color: AppColors.textSecondary.withOpacity(0.08),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              'Offline mode: logs are saved locally and queued for sync (wireframe).',
              style: t.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class InlineEmptyState extends StatelessWidget {
  const InlineEmptyState({super.key, required this.title, required this.subtitle, required this.icon, this.action});

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: AppTokens.sm),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.xs),
          Text(subtitle, style: t.bodySmall, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: AppTokens.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class InlineErrorState extends StatelessWidget {
  const InlineErrorState({super.key, required this.title, required this.subtitle, required this.onRetry});

  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
        color: AppColors.danger.withOpacity(0.07),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 32, color: AppColors.danger),
          const SizedBox(height: AppTokens.sm),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.xs),
          Text(subtitle, style: t.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Very lightweight skeleton block (no external deps).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.height, this.radius = AppTokens.rMd});

  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkOutline.withOpacity(0.35)
        : AppColors.outline.withOpacity(0.55);
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkOutline.withOpacity(0.18)
        : AppColors.outline.withOpacity(0.25);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}
