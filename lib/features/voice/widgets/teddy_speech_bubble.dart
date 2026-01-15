import 'package:flutter/material.dart';
import 'dart:math' as math;

class TeddySpeechBubble extends StatefulWidget {
  const TeddySpeechBubble({
    super.key,
    required this.caption,
    required this.isListening,
  });

  final String caption;
  final bool isListening;

  @override
  State<TeddySpeechBubble> createState() => _TeddySpeechBubbleState();
}

class _TeddySpeechBubbleState extends State<TeddySpeechBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  final List<double> _waveAmplitudes = List.generate(12, (_) => 0.1);
  final _random = math.Random();
  bool _isListenerAdded = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat();
  }

  @override
  void dispose() {
    if (_isListenerAdded) {
      _waveController.removeListener(_updateWaveAmplitudes);
    }
    _waveController.dispose();
    super.dispose();
  }

  void _updateWaveAmplitudes() {
    setState(() {
      for (int i = 0; i < _waveAmplitudes.length; i++) {
        _waveAmplitudes[i] = (_random.nextDouble() * 0.8) + 0.2;
      }
    });
  }

  @override
  void didUpdateWidget(TeddySpeechBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening && !_isListenerAdded) {
      _waveController.addListener(_updateWaveAmplitudes);
      _isListenerAdded = true;
    } else if (!widget.isListening && oldWidget.isListening && _isListenerAdded) {
      _waveController.removeListener(_updateWaveAmplitudes);
      _isListenerAdded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 540),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFFFE4E8).withOpacity(0.8),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEC407A).withOpacity(0.15),
            blurRadius: 40,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // CC Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC407A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Text(
                    'CC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Caption text with animation
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    widget.caption,
                    key: ValueKey(widget.caption),
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.5,
                      color: Color(0xFFD81B60),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Waveform inside speech bubble
                if (widget.isListening)
                  Container(
                    height: 50,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(12, (index) {
                            final amplitude = _waveAmplitudes[index];
                            return Container(
                              width: 4,
                              height: 40 * amplitude.clamp(0.2, 1.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEC407A),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

