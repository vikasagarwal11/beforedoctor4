import 'dart:async';
import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../app/app_state.dart';
import '../widgets/teddy_bear_character.dart';
import '../widgets/floating_decorations.dart';
import '../widgets/teddy_speech_bubble.dart';
import '../widgets/teddy_mic_button.dart';
import '../widgets/teddy_header.dart';
import '../widgets/friendly_character.dart';
import '../widgets/floating_shapes.dart';
import '../widgets/kid_friendly_caption_card.dart';
import '../widgets/kid_friendly_mic_button.dart';
import '../widgets/health_buddy_character.dart' show HealthBuddyCharacter, HealthBuddyState;
import '../widgets/health_buddy_decorations.dart';
import '../widgets/health_buddy_caption_card.dart';
import '../widgets/health_buddy_mic_button.dart';

/// Teddy Bear voice health UI for BeforeDoctor
/// - Maximum emotional warmth + zero intimidation
/// - Teddy bear character with stethoscope (trusted doctor friend)
/// - Pink-dominant palette (nurturing, maternal love, compassion)
/// - Speech bubble with waveform inside (magical, alive)
/// - Floating hearts & sparkles (pure joy, no medical icons)
/// - Therapeutic UI designed to reduce anxiety before doctor visit
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.repo,
    required this.activeProfile,
  });

  final MockRepo repo;
  final PersonProfile activeProfile;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

enum VoiceUiState { idle, listening, thinking, speaking }

class _VoiceScreenState extends State<VoiceScreen> {
  VoiceUiState _state = VoiceUiState.idle;

  // Captions - will be set based on character style
  String _caption = "Hi friend! I'm Teddy, your health buddy! 💕 How are you feeling?";
  Timer? _captionTimer;
  int _captionStep = 0;

  bool get _isListening => _state == VoiceUiState.listening;

  CharacterMood get _characterMood {
    if (_isListening) return CharacterMood.listening;
    if (_state == VoiceUiState.thinking) return CharacterMood.thinking;
    return CharacterMood.happy;
  }

  HealthBuddyState get _healthBuddyState {
    if (_isListening) return HealthBuddyState.listening;
    if (_state == VoiceUiState.thinking) return HealthBuddyState.thinking;
    return HealthBuddyState.happy;
  }

  @override
  void initState() {
    super.initState();
    _updateCaptionForStyle();
  }

  void _updateCaptionForStyle() {
    // This will be updated based on the selected style
    _caption = "Hi friend! I'm Teddy, your health buddy! 💕 How are you feeling?";
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    super.dispose();
  }

  void _toggleListening(AppState appState) {
    if (_isListening) {
      _stopListening(appState);
      return;
    }
    _startListening(appState);
  }

  void _startListening(AppState appState) {
    final style = appState.voiceCharacterStyle;
    final isTeddyBear = style == VoiceCharacterStyle.teddyBear;
    final isHealthBuddy = style == VoiceCharacterStyle.healthBuddy;
    
    setState(() {
      _state = VoiceUiState.listening;
      _captionStep = 0;
      if (isTeddyBear) {
        _caption = 'I\'m listening carefully...';
      } else if (isHealthBuddy) {
        _caption = 'Listening...';
      } else {
        _caption = 'I\'m listening...';
      }
    });

    _captionTimer?.cancel();

    // Style-specific simulated caption flow
    final steps = isTeddyBear
        ? const <String>[
            'I\'m listening carefully...',
            'My tummy hurts a little...',
            'It started after the ice cream...',
            'I feel hot and tired...',
            'Don\'t worry, we\'ll make you feel better! 💖',
          ]
        : isHealthBuddy
            ? const <String>[
                'Listening...',
                'My stomach hurts...',
                'It started after I ate lunch...',
                'And I feel kind of tired too...',
                'Maybe I ate too fast?',
              ]
            : const <String>[
                'I\'m listening...',
                'My tummy hurts a little...',
                'It started after I ate ice cream...',
                'And I feel kinda sleepy too...',
                'Can you help me feel better?',
              ];

    _captionTimer = Timer.periodic(const Duration(milliseconds: 2800), (t) {
      if (!mounted || !_isListening) return;
      if (_captionStep >= steps.length) {
        // Transition to thinking state
        setState(() {
          _state = VoiceUiState.thinking;
          if (isTeddyBear) {
            _caption = 'Got it! Let me think how to help you...';
          } else if (isHealthBuddy) {
            _caption = 'Got it! Let me think about how to help you...';
          } else {
            _caption = 'Hmm... let me think how to help you best 🧐';
          }
        });
        // After thinking, provide response
        Timer(const Duration(milliseconds: 2500), () {
          if (!mounted) return;
          setState(() {
            _state = VoiceUiState.idle;
            if (isTeddyBear) {
              _caption = 'Okay! Try drinking some water and resting. I\'ll stay with you 💕';
            } else if (isHealthBuddy) {
              _caption = 'Thanks for sharing! Here\'s what I think we should do...';
            } else {
              _caption = 'I think you might have a little tummy ache from too much ice cream! 🍦 Try drinking some water and resting a bit. Feel better soon! 💕';
            }
          });
        });
        _captionTimer?.cancel();
        return;
      }
      setState(() {
        _caption = steps[_captionStep];
        _captionStep += 1;
      });
    });
  }

  void _stopListening(AppState appState) {
    _captionTimer?.cancel();
    final style = appState.voiceCharacterStyle;
    final isTeddyBear = style == VoiceCharacterStyle.teddyBear;
    final isHealthBuddy = style == VoiceCharacterStyle.healthBuddy;
    
    setState(() {
      if (_isListening) {
        _state = VoiceUiState.thinking;
        if (isTeddyBear) {
          _caption = 'Got it! Let me think how to help you...';
        } else if (isHealthBuddy) {
          _caption = 'Got it! Let me think about how to help you...';
        } else {
          _caption = 'Okay! Let me think...';
        }
        // After thinking, return to idle
        Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          setState(() {
            _state = VoiceUiState.idle;
            if (isTeddyBear) {
              _caption = 'Hi friend! I\'m Teddy, your health buddy! 💕 How are you feeling?';
            } else if (isHealthBuddy) {
              _caption = 'Hi friend! I\'m here to help you feel better. What\'s going on?';
            } else {
              _caption = 'Hi there, friend! 😊 I\'m here to listen. What\'s on your mind?';
            }
          });
        });
      } else {
        _state = VoiceUiState.idle;
        if (isTeddyBear) {
          _caption = 'Hi friend! I\'m Teddy, your health buddy! 💕 How are you feeling?';
        } else if (isHealthBuddy) {
          _caption = 'Hi friend! I\'m here to help you feel better. What\'s going on?';
        } else {
          _caption = 'Hi there, friend! 😊 I\'m here to listen. What\'s on your mind?';
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return AppStateBuilder(builder: (context, appState) {
      final style = appState.voiceCharacterStyle;
      final isTeddyBear = style == VoiceCharacterStyle.teddyBear;
      final isHealthBuddy = style == VoiceCharacterStyle.healthBuddy;
      
      // Update caption when style changes (only if idle)
      if (_state == VoiceUiState.idle) {
        final expectedCaption = isTeddyBear
            ? "Hi friend! I'm Teddy, your health buddy! 💕 How are you feeling?"
            : isHealthBuddy
                ? "Hi friend! I'm here to help you feel better. What's going on?"
                : "Hi there, friend! 😊 I'm here to listen. What's on your mind?";
        if (_caption != expectedCaption) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _state == VoiceUiState.idle) {
              setState(() {
                _caption = expectedCaption;
              });
            }
          });
        }
      }

      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isTeddyBear
                  ? const [
                      Color(0xFFFFF0F5), // very light pink
                      Color(0xFFFFE4E8), // light pink
                      Color(0xFFFFB6C1), // soft pink
                    ]
                  : isHealthBuddy
                      ? const [
                          Color(0xFFE8F5E9), // light green
                          Color(0xFFFFF9C4), // light yellow
                          Color(0xFFFFE0B2), // light orange
                        ]
                      : const [
                          Color(0xFFE0F7FA), // soft mint
                          Color(0xFFC8E6C9), // soft green
                          Color(0xFFFFF3E0), // warm peach
                        ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header (always visible at top)
                const TeddyHeader(),
                // Main content - scrollable to prevent overflow
                Expanded(
                  child: Stack(
                    children: [
                      // Floating decorations - different for each style
                      if (isTeddyBear)
                        const FloatingDecorations()
                      else if (isHealthBuddy)
                        const HealthBuddyDecorations()
                      else
                        const FloatingShapes(),
                      // Scrollable content
                      SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height -
                                MediaQuery.of(context).padding.top -
                                MediaQuery.of(context).padding.bottom -
                                160, // Account for header + bottom nav
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                          // Character - Teddy Bear, Friendly Character, or Health Buddy
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isSmallScreen = constraints.maxHeight < 700;
                              final scale = isSmallScreen ? 0.85 : 1.0;
                              return Transform.scale(
                                scale: scale,
                                child: isTeddyBear
                                    ? TeddyBearCharacter(isListening: _isListening)
                                    : isHealthBuddy
                                        ? HealthBuddyCharacter(
                                            state: _healthBuddyState,
                                            isListening: _isListening,
                                          )
                                        : FriendlyCharacter(
                                            mood: _characterMood,
                                            isListening: _isListening,
                                          ),
                              );
                            },
                          ),
                          SizedBox(height: MediaQuery.of(context).size.height < 700 ? 20 : 28),
                          // Speech Bubble or Caption Card
                          if (isTeddyBear)
                            TeddySpeechBubble(
                              caption: _caption,
                              isListening: _isListening,
                            )
                          else if (isHealthBuddy)
                            HealthBuddyCaptionCard(
                              caption: _caption,
                              isListening: _isListening,
                              captionIndex: _captionStep,
                            )
                          else
                            KidFriendlyCaptionCard(
                              caption: _caption,
                              isListening: _isListening,
                            ),
                          SizedBox(height: MediaQuery.of(context).size.height < 700 ? 24 : 32),
                          // Mic Button - Pink, Green/Red, or Health Buddy style
                          if (isTeddyBear)
                            TeddyMicButton(
                              isListening: _isListening,
                              onPressed: () => _toggleListening(appState),
                            )
                          else if (isHealthBuddy)
                            HealthBuddyMicButton(
                              isListening: _isListening,
                              onPressed: () => _toggleListening(appState),
                            )
                          else
                            KidFriendlyMicButton(
                              isListening: _isListening,
                              onPressed: () => _toggleListening(appState),
                            ),
                          const SizedBox(height: 16),
                          // Helper text - style-specific
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _isListening
                                  ? (isTeddyBear
                                      ? 'Tap when you\'re done 💕'
                                      : isHealthBuddy
                                          ? 'Tap again when you\'re finished'
                                          : 'Tap when you\'re done talking')
                                  : (isTeddyBear
                                      ? 'Tap Teddy to talk!'
                                      : isHealthBuddy
                                          ? 'Tap to start talking'
                                          : 'Tap to talk to me! 💬'),
                              style: TextStyle(
                                fontSize: 18,
                                color: isTeddyBear
                                    ? const Color(0xFFD81B60)
                                    : isHealthBuddy
                                        ? const Color(0xFF7CB342)
                                        : const Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

