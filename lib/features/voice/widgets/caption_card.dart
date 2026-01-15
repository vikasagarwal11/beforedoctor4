import 'package:flutter/material.dart';
import '../screens/voice_screen.dart';
import '../../../core/constants/tokens.dart';
import 'waveform_bars.dart';

class CaptionCard extends StatelessWidget {
  const CaptionCard({
    super.key,
    required this.caption,
    required this.state,
  });

  final String caption;
  final VoiceUiState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    Widget captionWidget = Text(
      caption,
      style: t.headlineMedium?.copyWith(height: 1.15),
    );

    // Motion: fade + slight slide between caption changes
    captionWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim);
        final fade = Tween<double>(begin: 0, end: 1).animate(anim);
        return FadeTransition(opacity: fade, child: SlideTransition(position: offset, child: child));
      },
      child: KeyedSubtree(
        key: ValueKey<String>(caption),
        child: captionWidget,
      ),
    );

    return Card(
      elevation: 0,
      color: c.surfaceContainerHighest.withOpacity(0.55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live caption', style: t.titleSmall?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: AppTokens.sm),
            captionWidget,
            const SizedBox(height: AppTokens.md),
            WaveformBars(
              mode: state == VoiceUiState.listening
                  ? WaveformMode.listening
                  : state == VoiceUiState.thinking
                      ? WaveformMode.thinking
                      : WaveformMode.idle,
            ),
          ],
        ),
      ),
    );
  }
}

