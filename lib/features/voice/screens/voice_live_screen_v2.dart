import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/tokens.dart';
import '../../../services/audio/native_audio_engine.dart';
import '../../../services/audio/vad_processor.dart';
import '../../../services/gateway/gateway_client.dart';
import '../../../services/logging/app_logger.dart';
import '../voice_session_controller_v2.dart';
import '../widgets/mic_button.dart';
import '../widgets/waveform_bars.dart';

class VoiceLiveScreenV2 extends StatefulWidget {
  final Uri gatewayUrl;
  final String firebaseIdToken;
  final Map<String, dynamic> sessionConfig;
  final bool useMockGateway;

  const VoiceLiveScreenV2({
    super.key,
    required this.gatewayUrl,
    required this.firebaseIdToken,
    required this.sessionConfig,
    this.useMockGateway = false,
  });

  @override
  State<VoiceLiveScreenV2> createState() => _VoiceLiveScreenV2State();
}

class _VoiceLiveScreenV2State extends State<VoiceLiveScreenV2>
    with TickerProviderStateMixin {
  late VoiceSessionControllerV2 _controller;
  late AnimationController _auraController;
  Timer? _authFailsafeTimer;

  final AppLogger _logger = AppLogger.instance;
  bool _startTriggered = false;

  @override
  void initState() {
    super.initState();

    _auraController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    // Initialize controller
    final gateway = GatewayClient();
    final audio = NativeAudioEngine();

    _controller = VoiceSessionControllerV2(
      gateway: gateway,
      audio: audio,
      vadSensitivity: VadSensitivity.medium,
    );

    _controller.addListener(_onControllerUpdate);

    // Only auto-start if token is already available (normally won't be in initState)
    _triggerStartIfPossible();

    // FAILSAFE: If token doesn't arrive within 3 seconds, proceed anyway
    // This prevents stuck "Authenticating..." screen
    _authFailsafeTimer?.cancel();
    _authFailsafeTimer = Timer(const Duration(seconds: 3), () {
      if (!_startTriggered && mounted && widget.firebaseIdToken.isEmpty) {
        _logger.warn('voice.token_timeout_proceeding_without_token');
      }
    });
  }

  @override
  void didUpdateWidget(VoiceLiveScreenV2 oldWidget) {
    super.didUpdateWidget(oldWidget);

    // When token becomes available or changes, start the session
    if (widget.firebaseIdToken.isNotEmpty &&
        widget.firebaseIdToken != oldWidget.firebaseIdToken) {
      _authFailsafeTimer?.cancel();
      _authFailsafeTimer = null;
      _logger.info('voice.token_received',
          data: {'token_length': widget.firebaseIdToken.length});
      _triggerStartIfPossible();
    }
  }

  void _triggerStartIfPossible() {
    if (!mounted || _startTriggered) return;
    if (widget.firebaseIdToken.isEmpty) return;

    _startTriggered = true;
    _authFailsafeTimer?.cancel();
    _authFailsafeTimer = null;

    // Use Future.microtask to avoid permission dialog conflicts
    Future.microtask(() => _initializeAndStart());
  }

  void _onControllerUpdate() {
    setState(() {}); // Rebuild on controller changes
  }

  Future<void> _initializeAndStart() async {
    // Guard: Don't initialize if already disposed or session active
    if (!mounted) return;

    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _logger.warn('voice.permission_denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }

    // Validate token
    if (widget.firebaseIdToken.isEmpty) {
      _logger.error('voice.firebase_token_empty');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase token required')),
        );
      }
      // Allow auto-start later when token arrives.
      _startTriggered = false;
      return;
    }

    // Start session
    try {
      await _controller.start(
        gatewayUrl: widget.gatewayUrl,
        firebaseIdToken: widget.firebaseIdToken,
        sessionConfig: widget.sessionConfig,
      );
    } catch (e) {
      _logger.error('voice.start_failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _authFailsafeTimer?.cancel();
    _authFailsafeTimer = null;
    _controller.removeListener(_onControllerUpdate);
    _auraController.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Show loading if token is not yet available
    if (widget.firebaseIdToken.isEmpty) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Live Voice'),
        ),
        body: Stack(
          children: [
            _BackgroundGlow(color: cs.primary, animation: _auraController),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 40, color: cs.onSurfaceVariant),
                      const SizedBox(height: AppTokens.md),
                      Text(
                        'Authenticating…',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppTokens.sm),
                      Text(
                        'Preparing a secure voice session',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppTokens.xl),
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Live Voice'),
        actions: [
          IconButton(
            tooltip: 'Debug',
            onPressed: _showDebugSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _BackgroundGlow(
              color: _statusColor(context), animation: _auraController),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.lg),
              child: Column(
                children: [
                  _buildTopBar(context),
                  const SizedBox(height: AppTokens.lg),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _buildErrorBanner(context),
                        const SizedBox(height: AppTokens.md),
                        Center(
                          child: MicButton(
                            state: _controller.uiState,
                            onPressed: () {
                              final isStopped = _controller.uiState ==
                                      VoiceUiState.stopped ||
                                  _controller.uiState == VoiceUiState.idle ||
                                  _controller.uiState == VoiceUiState.error;
                              if (isStopped) {
                                _initializeAndStart();
                              } else {
                                _stopSession();
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: AppTokens.lg),
                        _TranscriptCard(
                          title: 'You',
                          tone: _TranscriptTone.user,
                          text: _controller.userTranscriptFinal.isNotEmpty
                              ? _controller.userTranscriptFinal
                              : _controller.userTranscriptPartial,
                          placeholder: _controller.uiState ==
                                  VoiceUiState.listening
                              ? 'Speak naturally… I’ll transcribe as you talk.'
                              : 'Waiting for your voice…',
                          isPartial: _controller.userTranscriptFinal.isEmpty &&
                              _controller.userTranscriptPartial.isNotEmpty,
                        ),
                        const SizedBox(height: AppTokens.md),
                        _TranscriptCard(
                          title: 'Assistant',
                          tone: _TranscriptTone.assistant,
                          text: _controller.assistantTextFinal.isNotEmpty
                              ? _controller.assistantTextFinal
                              : _controller.assistantTextPartial,
                          placeholder:
                              _controller.uiState == VoiceUiState.thinking
                                  ? 'Thinking…'
                                  : _controller.uiState == VoiceUiState.speaking
                                      ? 'Speaking…'
                                      : 'Ready when you are.',
                          isPartial: _controller.assistantTextFinal.isEmpty &&
                              _controller.assistantTextPartial.isNotEmpty,
                        ),
                        const SizedBox(height: AppTokens.md),
                        WaveformBars(
                          mode: _controller.uiState == VoiceUiState.listening
                              ? WaveformMode.listening
                              : _controller.uiState == VoiceUiState.thinking
                                  ? WaveformMode.thinking
                                  : WaveformMode.idle,
                        ),
                        const SizedBox(height: AppTokens.lg),
                        _buildQuickActions(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BeforeDoctor',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Real‑time voice intake',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        _StatusChip(state: _controller.uiState),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final error = _controller.lastError;
    final showReconnect = _controller.showReconnectPrompt;
    if (error == null && !showReconnect) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: AppTokens.medium,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.75),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(color: cs.error.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error ?? 'Connection issue',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onErrorContainer),
                ),
                if (showReconnect) ...[
                  const SizedBox(height: AppTokens.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _controller.reconnect(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reconnect'),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showDebugSheet,
            icon: const Icon(Icons.bar_chart_rounded),
            label: const Text('Metrics'),
            style: OutlinedButton.styleFrom(
              backgroundColor: cs.surface.withOpacity(0.55),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.rLg),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _controller.uiState != VoiceUiState.stopped
                ? _stopSession
                : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              backgroundColor: cs.surface.withOpacity(0.55),
              side: BorderSide(color: cs.error.withOpacity(0.35)),
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.rLg),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (_controller.uiState) {
      VoiceUiState.idle => cs.primary,
      VoiceUiState.connecting => AppColors.warning,
      VoiceUiState.listening => AppColors.success,
      VoiceUiState.thinking => cs.primary,
      VoiceUiState.speaking => cs.secondary,
      VoiceUiState.error => cs.error,
      VoiceUiState.reconnecting => AppColors.warning,
      VoiceUiState.stopped => cs.outline,
    };
  }

  void _showDebugSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session metrics', style: t.titleLarge),
                const SizedBox(height: AppTokens.md),
                _KeyValueRow(
                    label: 'State', value: _controller.uiState.toString()),
                _KeyValueRow(
                    label: 'Captured chunks',
                    value: _controller.capturedChunks.toString()),
                _KeyValueRow(
                    label: 'Sent chunks',
                    value: _controller.sentChunks.toString()),
                _KeyValueRow(
                    label: 'Audio out chunks',
                    value: _controller.receivedAudioChunks.toString()),
                _KeyValueRow(
                    label: 'Gateway', value: widget.gatewayUrl.toString()),
                const SizedBox(height: AppTokens.lg),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _stopSession() async {
    try {
      await _controller.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session stopped')),
        );
      }
    } catch (e) {
      _logger.error('voice.stop_failed', error: e);
    }
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.color, required this.animation});

  final Color color;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final t = animation.value;
        final glow = 0.35 + (t * 0.25);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface,
                cs.surface,
                Color.lerp(color, cs.surface, 0.82)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -120,
                right: -120,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(glow),
                  ),
                ),
              ),
              Positioned(
                bottom: -140,
                left: -140,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.secondary.withOpacity(0.10 + t * 0.10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final VoiceUiState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (label, icon, color) = switch (state) {
      VoiceUiState.idle => ('Ready', Icons.check_circle_outline, cs.primary),
      VoiceUiState.connecting => (
          'Connecting',
          Icons.wifi_tethering_rounded,
          AppColors.warning
        ),
      VoiceUiState.listening => (
          'Listening',
          Icons.hearing_rounded,
          AppColors.success
        ),
      VoiceUiState.thinking => (
          'Thinking',
          Icons.auto_awesome_rounded,
          cs.primary
        ),
      VoiceUiState.speaking => (
          'Speaking',
          Icons.volume_up_rounded,
          cs.secondary
        ),
      VoiceUiState.reconnecting => (
          'Reconnecting',
          Icons.refresh_rounded,
          AppColors.warning
        ),
      VoiceUiState.error => ('Error', Icons.error_outline, cs.error),
      VoiceUiState.stopped => (
          'Stopped',
          Icons.stop_circle_outlined,
          cs.outline
        ),
    };

    return AnimatedContainer(
      duration: AppTokens.medium,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md, vertical: AppTokens.sm),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTokens.rPill),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppTokens.sm),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

enum _TranscriptTone { user, assistant }

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.title,
    required this.tone,
    required this.text,
    required this.placeholder,
    required this.isPartial,
  });

  final String title;
  final _TranscriptTone tone;
  final String text;
  final String placeholder;
  final bool isPartial;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final accent = tone == _TranscriptTone.user ? cs.primary : cs.secondary;
    final bg = tone == _TranscriptTone.user
        ? cs.primaryContainer.withOpacity(0.45)
        : cs.secondaryContainer.withOpacity(0.45);

    final shownText = text.trim().isEmpty ? placeholder : text.trim();

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              Text(title, style: t.titleMedium),
              const Spacer(),
              if (isPartial)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Text(
                    'Live',
                    style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          AnimatedSwitcher(
            duration: AppTokens.medium,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final offset =
                  Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                      .animate(anim);
              return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offset, child: child));
            },
            child: Text(
              shownText,
              key: ValueKey<String>(shownText),
              style: t.bodyLarge?.copyWith(
                height: 1.25,
                color: text.trim().isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                fontStyle:
                    text.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: t.bodyMedium),
          ),
        ],
      ),
    );
  }
}
