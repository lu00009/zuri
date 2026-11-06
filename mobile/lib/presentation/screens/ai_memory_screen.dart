import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/remote/ai_remote_data_source.dart';
import '../providers/ai_provider.dart';
import '../providers/sync_provider.dart';

class AiMemoryScreen extends ConsumerStatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  ConsumerState<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends ConsumerState<AiMemoryScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<String> _suggestedPrompts = [
    'Say hello to Zuri 👋',
    'What can you do?',
    'Project notes & goals',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).syncNow();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    _queryController.clear();
    FocusScope.of(context).unfocus();

    // Flush pending notes so the AI retrieval has the latest knowledge
    final syncState = ref.read(syncProvider);
    if (syncState.pendingCount > 0) {
      await ref.read(syncProvider.notifier).syncNow();
    }

    // Call conversation notifier for persistent conversational memory
    await ref.read(conversationProvider.notifier).sendMessage(clean);

    // Also call legacy aiNotifier for backwards-compatibility with tests & single-shot answers
    await ref.read(aiNotifierProvider.notifier).ask(clean);

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showRenameDialog(String conversationId, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Conversation Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(conversationProvider.notifier)
                  .renameConversation(conversationId, controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }

  Widget _buildDrawer(
    BuildContext context,
    ConversationState convState,
    ThemeData theme,
  ) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header with Zuri branding & New Chat
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zuri',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Personal AI Assistant',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _queryController.clear();
                      ref.read(aiNotifierProvider.notifier).clear();
                      ref
                          .read(conversationProvider.notifier)
                          .startNewConversation();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Chat'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Chat history heading
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chat History',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // Conversations list
            Expanded(
              child: convState.conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 40,
                              color: Colors.grey.withAlpha(150),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No previous conversations yet.\nSay hello to start chatting!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: convState.conversations.length,
                      itemBuilder: (ctx, idx) {
                        final item = convState.conversations[idx];
                        final isSelected =
                            convState.currentConversation?.id == item.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Material(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer.withAlpha(70)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              isSelected
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                              size: 20,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              '${item.messageCount} msgs • ${_formatDate(item.updatedAt)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (action) {
                                if (action == 'rename') {
                                  Navigator.of(context).pop();
                                  _showRenameDialog(item.id, item.title);
                                } else if (action == 'delete') {
                                  ref
                                      .read(conversationProvider.notifier)
                                      .deleteConversation(item.id);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16),
                                      SizedBox(width: 8),
                                      Text('Rename'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline,
                                          size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              ref
                                  .read(conversationProvider.notifier)
                                  .selectConversation(item.id);
                            },
                          ),
                        ),
                      );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiNotifierProvider);
    final convState = ref.watch(conversationProvider);
    final currentConv = convState.currentConversation;
    final theme = Theme.of(context);

    final currentTitle = currentConv?.title ?? 'Zuri';

    return Scaffold(
      drawer: _buildDrawer(context, convState, theme),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Chat History',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Builder(
          builder: (ctx) => InkWell(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology_outlined, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Zuri',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (currentConv != null)
                          Text(
                            currentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Conversation',
            onPressed: () {
              _queryController.clear();
              ref.read(aiNotifierProvider.notifier).clear();
              ref.read(conversationProvider.notifier).startNewConversation();
            },
          ),
          if (currentConv != null)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'rename') {
                  _showRenameDialog(currentConv.id, currentConv.title);
                } else if (action == 'delete') {
                  ref
                      .read(conversationProvider.notifier)
                      .deleteConversation(currentConv.id);
                } else if (action == 'clear') {
                  _queryController.clear();
                  ref.read(aiNotifierProvider.notifier).clear();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Rename Chat'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Chat', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Back to Notes',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Suggested prompt chips (shown when no messages or only 1 message)
            if ((currentConv == null || currentConv.messages.isEmpty) &&
                aiState.answer == null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: _suggestedPrompts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final prompt = _suggestedPrompts[index];
                      return ActionChip(
                        avatar: const Icon(Icons.lightbulb_outline, size: 16),
                        label: Text(prompt),
                        onPressed: () => _submitQuery(prompt),
                      );
                    },
                  ),
                ),
              ),

            // Content Area
            Expanded(
              child: _buildChatContent(context, convState, aiState),
            ),

            // Bottom Input Bar
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _submitQuery,
                      decoration: InputDecoration(
                        hintText: 'Ask Zuri anything or search your memories...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(120),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send_rounded),
                    onPressed: () => _submitQuery(_queryController.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatContent(
    BuildContext context,
    ConversationState convState,
    AiState aiState,
  ) {
    // If an error occurred
    if (aiState.errorMessage != null || convState.errorMessage != null) {
      final err = aiState.errorMessage ?? convState.errorMessage!;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Query Failed',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                err,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _submitQuery(_queryController.text),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final currentConv = convState.currentConversation;
    final messages = currentConv?.messages ?? [];

    // Fallback: If legacy aiState has answer and conv messages is empty, show legacy answer
    if (messages.isEmpty && aiState.answer != null) {
      return _buildLegacyAnswerView(context, aiState.answer!);
    }

    // Empty State
    if (messages.isEmpty && !aiState.isLoading && !convState.isSendingMessage) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Meet Zuri, Your AI Assistant',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Say hello, brainstorm ideas, or ask anything about your saved notes and learnings. Zuri remembers your conversation and references your notes when helpful.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // Message List
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      itemCount: messages.length +
          (convState.isSendingMessage || aiState.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _buildLoadingBubble(context);
        }
        final msg = messages[index];
        if (msg.role == 'user') {
          return _buildUserBubble(context, msg.content);
        } else {
          return _buildAssistantBubble(context, msg);
        }
      },
    );
  }

  Widget _buildLoadingBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primary.withAlpha(30),
            child: Icon(
              Icons.psychology,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(90),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Searching your memories...'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context, String content) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(
                content,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withAlpha(40),
            child: Icon(Icons.person,
                size: 18, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(
      BuildContext context, ConversationMessageItem msg) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primary.withAlpha(30),
                child: Icon(Icons.auto_awesome,
                    size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(90),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: !msg.hasSufficientEvidence
                          ? Colors.amber.withAlpha(100)
                          : (msg.citations.isNotEmpty
                              ? Colors.green.withAlpha(60)
                              : theme.colorScheme.outlineVariant.withAlpha(50)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge header: only show for grounded memory or insufficient evidence, never for pure conversational
                      if (!msg.hasSufficientEvidence || msg.citations.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: msg.hasSufficientEvidence
                                ? Colors.green.withAlpha(30)
                                : Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                msg.hasSufficientEvidence
                                    ? Icons.verified_outlined
                                    : Icons.info_outline,
                                size: 14,
                                color: msg.hasSufficientEvidence
                                    ? Colors.green[700]
                                    : Colors.amber[800],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                msg.hasSufficientEvidence
                                    ? 'Grounded in Notes'
                                    : 'No Matching Notes',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: msg.hasSufficientEvidence
                                      ? Colors.green[700]
                                      : Colors.amber[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _buildAssistantContent(context, msg.content),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Citations list
          if (msg.citations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 42.0, top: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.format_quote, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Referenced Notes (${msg.citations.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...msg.citations.map((c) => _buildCitationCard(context, c)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssistantContent(BuildContext context, String content) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final parts = content.split(RegExp(r'\n\n💡\s*(\*\*)?Recommendation:?(\*\*)?\s*', caseSensitive: false));
    final mainText = parts[0].trim();
    final recommendation = parts.length > 1 ? parts[1].trim() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mainText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14.5,
            height: 1.5,
          ),
        ),
        if (recommendation != null && recommendation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B).withAlpha(120) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF3B82F6).withAlpha(80) : const Color(0xFFBFDBFE),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommendation',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        recommendation,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLegacyAnswerView(BuildContext context, GroundedAnswer answer) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: answer.hasSufficientEvidence
                  ? Colors.green.withAlpha(80)
                  : Colors.amber.withAlpha(120),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: answer.hasSufficientEvidence
                            ? Colors.green.withAlpha(30)
                            : Colors.amber.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            answer.hasSufficientEvidence
                                ? Icons.verified_outlined
                                : Icons.info_outline,
                            size: 16,
                            color: answer.hasSufficientEvidence
                                ? Colors.green[700]
                                : Colors.amber[800],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            answer.hasSufficientEvidence
                                ? 'Grounded in Notes'
                                : 'No Matching Notes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: answer.hasSufficientEvidence
                                  ? Colors.green[700]
                                  : Colors.amber[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${answer.latencyMs.toStringAsFixed(0)}ms',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildAssistantContent(context, answer.answer),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (answer.citations.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                const Icon(Icons.format_quote, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Referenced Notes (${answer.citations.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...answer.citations.map((c) => _buildCitationCard(context, c)),
        ],
      ],
    );
  }

  Widget _buildCitationCard(BuildContext context, MemoryCitation citation) {
    final matchPercent = (citation.similarity * 100).toInt();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(40)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/note/${citation.noteId}');
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.article_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      citation.noteTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$matchPercent% match',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withAlpha(150),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  citation.excerpt,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
