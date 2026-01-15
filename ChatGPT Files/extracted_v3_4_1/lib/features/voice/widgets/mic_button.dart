import 'package:flutter/material.dart';
import '../screens/voice_screen.dart';

class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  final VoiceUiState state;
  final VoidCallback onPressed;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _press;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    _press.dispose();
    super.dispose();
  }

  bool get _listening => widget.state == VoiceUiState.listening;
  bool get _thinking => widget.state == VoiceUiState.thinking;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = _listening
        ? Colors.red
        : _thinking
            ? cs.secondary
            : cs.primary;

    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) => _press.reverse(),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _press]),
        builder: (_, __) {
          final t = _pulse.value;
          final ringOpacity = _listening ? (0.12 + (1 - t) * 0.16) : 0.0;
          final ringScale = _listening ? (1.0 + t * 0.65) : 1.0;

          return Transform.scale(
            scale: _pressScale.value,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulse ring
                if (_listening)
                  Opacity(
                    opacity: ringOpacity,
                    child: Transform.scale(
                      scale: ringScale,
                      child: Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: baseColor, width: 10),
                        ),
                      ),
                    ),
                  ),
                // Main button
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseColor,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                        color: Colors.black.withOpacity(0.18),
                      ),
                    ],
                  ),
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
