import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/tokens.dart';
import '../../../services/audio/native_audio_engine.dart';
import '../../../services/audio/vad_processor.dart';
import '../../../services/gateway/gateway_client.dart';
import '../../../services/logging/app_logger.dart';
import '../voice_session_controller_v2.dart';
import '../widgets/chat_message_list.dart';

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
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  final AppLogger _logger = AppLogger.instance;
  bool _updatingFromController = false; // Prevent circular updates

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

    // Sync voice transcript to text field (never override while user edits)
    _controller.addListener(() {
      // Do not overwrite text if user is editing
      if (_textFocusNode.hasFocus) {
        return;
      }

      // Show accumulated draft + live partial transcript
      String displayText = _controller.userDraftText;

      // If listening and there's a partial, append it for live preview
      if (_controller.uiState == VoiceUiState.listening &&
          _controller.userTranscriptPartial.isNotEmpty) {
        // Only show partial if it's different from what's already in draft
        if (!_controller.userDraftText
            .contains(_controller.userTranscriptPartial)) {
          final needsSpace = displayText.trim().isNotEmpty;
          displayText = needsSpace
              ? '${displayText.trim()} ${_controller.userTranscriptPartial}'
              : _controller.userTranscriptPartial;
        }
      }

      // Only sync if text is different
      if (displayText != _textController.text) {
        _updatingFromController = true; // Prevent onChanged from firing
        _textController.text = displayText;
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
        _updatingFromController = false;
      }
    });

    // Track manual editing state
    _textFocusNode.addListener(() {
      _controller.setUserDraftEditing(_textFocusNode.hasFocus);
    });

    // Connect gateway immediately on screen load (not on mic press)
    // This eliminates connection delay when user presses mic
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    if (!mounted) return;
    if (widget.firebaseIdToken.isEmpty) {
      _logger.warn('voice.firebase_token_empty_on_init');
      return;
    }

    try {
      _logger.info('voice.session_init_starting');
      await _controller.start(
        gatewayUrl: widget.gatewayUrl,
        firebaseIdToken: widget.firebaseIdToken,
        sessionConfig: widget.sessionConfig,
      );
      _logger.info('voice.session_init_success');
    } catch (e) {
      _logger.error('voice.session_init_failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(VoiceLiveScreenV2 oldWidget) {
    super.didUpdateWidget(oldWidget);

    // When token becomes available or changes, reinitialize session
    if (widget.firebaseIdToken.isNotEmpty &&
        widget.firebaseIdToken != oldWidget.firebaseIdToken) {
      _logger.info('voice.token_received',
          data: {'token_length': widget.firebaseIdToken.length});
      _initializeSession();
    }
  }

  void _onControllerUpdate() {
    setState(() {}); // Rebuild on controller changes
  }

  Future<void> _startAudioCapture() async {
    if (!mounted) return;
    if (_controller.uiState == VoiceUiState.listening) return;

    _logger.info('voice.mic_button_pressed');

    // Check if session is active
    if (_controller.uiState == VoiceUiState.idle ||
        _controller.uiState == VoiceUiState.stopped) {
      // Session exists, just need permission
    } else {
      _logger.warn('voice.session_not_ready', data: {
        'state': _controller.uiState.toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connecting... Please wait'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

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

    // Start mic capture
    try {
      _logger.info('voice.starting_mic_capture');
      _controller.startMicCapture();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎤 Listening... Speak now'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF6366F1),
          ),
        );
      }
    } catch (e) {
      _logger.error('voice.capture_start_failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start mic: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopMicCapture() {
    _logger.info('voice.stopping_mic_capture');
    _controller.stopMicCapture();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mic stopped'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _auraController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    _controller.dispose();
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
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Modern gradient header with glass effect
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF6366F1), // Indigo
                          const Color(0xFF8B5CF6), // Purple
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.lg),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.medical_services_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: AppTokens.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BeforeDoctor AI',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  Text(
                                    _getStatusText(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Error banner
                  _buildErrorBanner(context),
                  // Modern chat area with gradient
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.surface,
                            cs.surfaceContainerLowest,
                          ],
                        ),
                      ),
                      child: ChatMessageList(
                        messages: _controller.messages,
                        userPartialText: null,
                        userDraftText: null,
                        userDraftEditing: false,
                        showDraftPlaceholder: false,
                        onDraftEditingChanged: null,
                        onDraftChanged: null,
                        onDraftSend: null,
                        assistantPartialText: null,
                        onMessageEdit: (messageId, newContent) {
                          _controller.updateMessageContent(
                            messageId: messageId,
                            newContent: newContent,
                          );
                        },
                      ),
                    ),
                  ),
                  // Modern bottom bar with floating mic button
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.md),
                        child: Row(
                          children: [
                            // Text input field
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                child: SingleChildScrollView(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: cs.outline.withOpacity(0.2),
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _textController,
                                      focusNode: _textFocusNode,
                                      maxLines: 6,
                                      minLines: 1,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      onChanged: (text) {
                                        if (!_updatingFromController) {
                                          _controller.updateUserDraftText(text);
                                        }
                                      },
                                      style:
                                          Theme.of(context).textTheme.bodyLarge,
                                      decoration: InputDecoration(
                                        hintText: _getInputHint(),
                                        hintStyle: TextStyle(
                                            color: cs.onSurfaceVariant
                                                .withOpacity(0.6)),
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: AppTokens.lg,
                                          vertical: AppTokens.md,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTokens.sm),
                            // Large circular mic/send button
                            _textController.text.trim().isEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      if (_controller.uiState ==
                                          VoiceUiState.listening) {
                                        _stopMicCapture();
                                      } else {
                                        _startAudioCapture();
                                      }
                                    },
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: _controller.uiState ==
                                                VoiceUiState.listening
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFEF4444),
                                                  Color(0xFFDC2626),
                                                ],
                                              )
                                            : const LinearGradient(
                                                colors: [
                                                  Color(0xFF6366F1),
                                                  Color(0xFF8B5CF6),
                                                ],
                                              ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_controller.uiState ==
                                                        VoiceUiState.listening
                                                    ? const Color(0xFFEF4444)
                                                    : const Color(0xFF6366F1))
                                                .withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _controller.uiState ==
                                                VoiceUiState.listening
                                            ? Icons.stop_rounded
                                            : Icons.mic_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: _sendTextMessage,
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF10B981),
                                            Color(0xFF059669),
                                          ],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981)
                                                .withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.send_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
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
        // Status chip hidden - user doesn't want to see technical states
        const SizedBox.shrink(),
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
    return Column(
      children: [
        Row(
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
        ),
        const SizedBox(height: AppTokens.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _controller.messages.isNotEmpty ? _downloadSummary : null,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download Summary'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
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

  String _getStatusText() {
    // Always show simple status - no technical states visible to user
    return 'Online';
  }

  String _getInputHint() {
    // Simple hint - no technical state mentions
    if (_textController.text.isNotEmpty) {
      return '';
    } else {
      return 'Type a message or tap mic';
    }
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // End the audio turn cleanly if the mic is still running.
    if (_controller.uiState == VoiceUiState.listening) {
      _controller.stopMicCapture();
    }

    // Send message through controller (this will save it)
    _controller.sendUserDraftMessage();

    // Clear input field
    _textController.clear();
    _textFocusNode.unfocus();
  }

  Future<void> _downloadSummary() async {
    try {
      // Show loading
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Generating summary...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Generate summary
      final summary = await _controller.generateSummary();

      if (summary == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate summary'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Format as readable text
      final summaryText = summary.toReadableText();

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: summaryText));

      if (!mounted) return;

      // Show options dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Summary Ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your conversation summary has been copied to clipboard.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '${summary.keyPoints.length} key points identified',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Share.share(
                  summaryText,
                  subject: 'Conversation Summary',
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
          ],
        ),
      );
    } catch (e) {
      _logger.error('voice.summary_download_failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
