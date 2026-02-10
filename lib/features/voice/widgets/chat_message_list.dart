// Chat Message List Widget
// Production-grade: Displays full conversation history in chat format
// Real-time updates, auto-scroll, context-aware display

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/models/conversation.dart';

/// Chat-style message list widget
class ChatMessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? userPartialText;
  final String? userDraftText;
  final bool userDraftEditing;
  final bool showDraftPlaceholder;
  final ValueChanged<bool>? onDraftEditingChanged;
  final ValueChanged<String>? onDraftChanged;
  final VoidCallback? onDraftSend;
  final String? assistantPartialText;
  final bool showAssistantTyping;
  final bool showUserTyping;
  final String? userTypingLabel;
  final String? assistantTypingLabel;
  final ScrollController? scrollController;
  final Function(String messageId, String newContent)? onMessageEdit;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.userPartialText,
    this.userDraftText,
    this.userDraftEditing = false,
    this.showDraftPlaceholder = false,
    this.onDraftEditingChanged,
    this.onDraftChanged,
    this.onDraftSend,
    this.assistantPartialText,
    this.showAssistantTyping = false,
    this.showUserTyping = false,
    this.userTypingLabel,
    this.assistantTypingLabel,
    this.scrollController,
    this.onMessageEdit,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  late ScrollController _scrollController;
  bool _autoScroll = true;
  String? _lastMessageSignature;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: false);
    });
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.messages.length != oldWidget.messages.length && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: true);
      });
    }

    ChatMessage? latest;
    for (final message in widget.messages) {
      if (latest == null || message.timestamp.isAfter(latest.timestamp)) {
        latest = message;
      }
    }
    final signature = latest == null
        ? null
        : '${latest.id}:${latest.timestamp.millisecondsSinceEpoch}';
    if (signature != _lastMessageSignature && _autoScroll) {
      _lastMessageSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: true);
      });
    }

    if (widget.userDraftText != oldWidget.userDraftText && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: true);
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final scrolledToBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 50;

    if (_autoScroll != scrolledToBottom) {
      setState(() {
        _autoScroll = scrolledToBottom;
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;

    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedMessages = [...widget.messages]..sort((a, b) {
        final t = a.timestamp.compareTo(b.timestamp);
        if (t != 0) return t;

        // If timestamps are equal, keep user messages before assistant
        if (a.role != b.role) {
          if (a.role == MessageRole.user) return -1;
          if (b.role == MessageRole.user) return 1;
        }

        return a.id.compareTo(b.id);
      });
    final showDraft =
        widget.userDraftText != null || widget.showDraftPlaceholder;

    final showAssistantTyping = widget.showAssistantTyping &&
        (widget.assistantPartialText == null ||
            widget.assistantPartialText!.isEmpty);

    final showUserTyping = widget.showUserTyping &&
        (widget.userPartialText == null || widget.userPartialText!.isEmpty);

    // Show empty state only if there's absolutely nothing to display
    if (sortedMessages.isEmpty &&
        widget.userPartialText == null &&
        !showDraft &&
        widget.assistantPartialText == null &&
        !showAssistantTyping &&
        !showUserTyping) {
      return _EmptyState();
    }

    final itemCount = sortedMessages.length +
        (showDraft ? 1 : 0) +
        (!showDraft && widget.userPartialText != null ? 1 : 0) +
        (widget.assistantPartialText != null ? 1 : 0) +
        (showAssistantTyping ? 1 : 0) +
        (showUserTyping ? 1 : 0);

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppTokens.lg),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < sortedMessages.length) {
              final message = sortedMessages[index];
              return ChatBubble(
                message: message,
                isPartial: false,
                onEdit: widget.onMessageEdit,
              );
            }

            var cursor = sortedMessages.length;

            if (showDraft && index == cursor) {
              return DraftBubble(
                text: widget.userDraftText ?? '',
                isEditing: widget.userDraftEditing,
                onEditingChanged: widget.onDraftEditingChanged,
                onChanged: widget.onDraftChanged,
                onSend: widget.onDraftSend,
              );
            }

            if (showDraft) {
              cursor++;
            }

            if (!showDraft &&
                widget.userPartialText != null &&
                index == cursor) {
              return ChatBubble(
                message: ChatMessage(
                  id: 'partial-user',
                  conversationId: '',
                  role: MessageRole.user,
                  content: widget.userPartialText!,
                  timestamp: DateTime.now(),
                ),
                isPartial: true,
              );
            }

            if (!showDraft && widget.userPartialText != null) {
              cursor++;
            }

            if (showUserTyping && index == cursor) {
              return _TypingIndicatorBubble(
                isUser: true,
                label: widget.userTypingLabel,
              );
            }

            if (showUserTyping) {
              cursor++;
            }

            if (widget.assistantPartialText != null && index == cursor) {
              return ChatBubble(
                message: ChatMessage(
                  id: 'partial-assistant',
                  conversationId: '',
                  role: MessageRole.assistant,
                  content: widget.assistantPartialText!,
                  timestamp: DateTime.now(),
                ),
                isPartial: true,
              );
            }

            if (widget.assistantPartialText != null) {
              cursor++;
            }

            if (showAssistantTyping && index == cursor) {
              return _TypingIndicatorBubble(
                isUser: false,
                label: widget.assistantTypingLabel,
              );
            }

            return const SizedBox.shrink();
          },
        ),
        if (!_autoScroll)
          Positioned(
            bottom: AppTokens.lg,
            right: AppTokens.lg,
            child: FloatingActionButton.small(
              onPressed: () => _scrollToBottom(animated: true),
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }
}

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble({required this.isUser, this.label});

  final bool isUser;
  final String? label;

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isUser = widget.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.xs,
        horizontal: AppTokens.sm,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.md,
            vertical: AppTokens.sm,
          ),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final phase = (_animation.value * 3).floor() % 3;
              final dots =
                  List.generate(3, (i) => i <= phase ? '•' : '·').join(' ');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.label != null && widget.label!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.label!,
                        style: t.labelSmall?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  Text(
                    dots,
                    style: t.bodyMedium?.copyWith(
                      color: Colors.black54,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Individual chat bubble
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isPartial;
  final Function(String messageId, String newContent)? onEdit;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isPartial,
    this.onEdit,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  late TextEditingController _editController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.message.content;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
    });
  }

  void _saveEdit(BuildContext context) {
    final newContent = _editController.text.trim();
    if (newContent.isNotEmpty && newContent != widget.message.content) {
      widget.onEdit?.call(widget.message.id, newContent);

      setState(() {
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transcript updating...'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {},
          ),
        ),
      );
    } else {
      _cancelEdit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final isUser = widget.message.role == MessageRole.user;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // WhatsApp colors: green for user, white for assistant
    final bubbleColor = isUser
        ? const Color(0xFFDCF8C6) // WhatsApp user message green
        : Colors.white;
    final textColor = Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.xs,
        horizontal: AppTokens.sm,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            if (!_isEditing)
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(8),
                    topRight: const Radius.circular(8),
                    bottomLeft: Radius.circular(isUser ? 8 : 2),
                    bottomRight: Radius.circular(isUser ? 2 : 8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.md,
                  vertical: AppTokens.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MarkdownBody(
                      data: widget.message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(
                        p: t.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatMeta(widget.message.timestamp),
                          style: t.labelSmall?.copyWith(
                            color: Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                        if (isUser) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all,
                            size: 14,
                            color:
                                const Color(0xFF4FC3F7), // WhatsApp blue tick
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  border: Border.all(color: cs.primary, width: 2),
                  borderRadius: BorderRadius.circular(AppTokens.rLg),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(AppTokens.md),
                child: Column(
                  children: [
                    TextField(
                      controller: _editController,
                      minLines: 2,
                      maxLines: 6,
                      style: t.bodyLarge?.copyWith(color: textColor),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: 'Edit transcript...',
                        hintStyle: t.bodyLarge?.copyWith(
                          color: textColor.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _cancelEdit,
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                        const SizedBox(width: AppTokens.sm),
                        FilledButton(
                          onPressed: () => _saveEdit(context),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(
                left: AppTokens.md,
                right: AppTokens.md,
                top: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUser && !widget.isPartial && !_isEditing)
                    GestureDetector(
                      onTap: _startEdit,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: Colors.black45,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMeta(DateTime timestamp) {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    final time = '${hour.toString().padLeft(2, '0')}:$minute $ampm';
    return time;
  }
}

/// Draft bubble for live, editable user transcript
class DraftBubble extends StatefulWidget {
  final String text;
  final bool isEditing;
  final ValueChanged<bool>? onEditingChanged;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSend;

  const DraftBubble({
    super.key,
    required this.text,
    required this.isEditing,
    this.onEditingChanged,
    this.onChanged,
    this.onSend,
  });

  @override
  State<DraftBubble> createState() => _DraftBubbleState();
}

class _DraftBubbleState extends State<DraftBubble> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(DraftBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text) {
      final selection = _controller.selection;
      _controller.text = widget.text;
      final end = _controller.text.length;
      _controller.selection = selection.isValid
          ? selection.copyWith(baseOffset: end, extentOffset: end)
          : TextSelection.collapsed(offset: end);
    }
  }

  void _handleFocusChange() {
    widget.onEditingChanged?.call(_focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.xs,
        horizontal: AppTokens.sm,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFDCF8C6), // WhatsApp user green
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
                border: Border.all(
                  color: const Color(0xFF25D366).withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(AppTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 6,
                    onChanged: widget.onChanged,
                    style: t.bodyMedium?.copyWith(color: Colors.black87),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Live transcript…',
                      hintStyle: t.bodyMedium?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF075E54).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mic,
                                size: 10, color: Color(0xFF075E54)),
                            const SizedBox(width: 2),
                            Text(
                              'Draft',
                              style: t.labelSmall?.copyWith(
                                color: const Color(0xFF075E54),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            widget.text.trim().isEmpty ? null : widget.onSend,
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label:
                            const Text('Send', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: cs.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: AppTokens.lg),
          Text(
            'Start speaking to begin',
            style: t.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.sm),
          Text(
            'Your conversation will appear here',
            style: t.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
