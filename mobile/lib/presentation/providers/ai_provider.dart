import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/friendly_error.dart';
import '../../data/datasources/remote/ai_remote_data_source.dart';
import '../../data/datasources/remote/conversational_intent.dart';
import 'sync_provider.dart';

final aiRemoteDataSourceProvider = Provider<AiRemoteDataSource>((ref) {
  final client = ref.watch(apiClientProvider);
  return AiRemoteDataSource(client);
});

// ---------------------------------------------------------------------------
// Single Ask AI State & Notifier (Preserved for backwards-compatibility)
// ---------------------------------------------------------------------------

class AiState {
  final bool isLoading;
  final String currentQuery;
  final GroundedAnswer? answer;
  final String? errorMessage;
  final bool isNetworkError;
  final String? lastQuery;

  const AiState({
    this.isLoading = false,
    this.currentQuery = '',
    this.answer,
    this.errorMessage,
    this.isNetworkError = false,
    this.lastQuery,
  });

  AiState copyWith({
    bool? isLoading,
    String? currentQuery,
    GroundedAnswer? answer,
    String? errorMessage,
    bool? isNetworkError,
    String? lastQuery,
    bool clearAnswer = false,
    bool clearError = false,
  }) {
    return AiState(
      isLoading: isLoading ?? this.isLoading,
      currentQuery: currentQuery ?? this.currentQuery,
      answer: clearAnswer ? null : (answer ?? this.answer),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isNetworkError: clearError ? false : (isNetworkError ?? this.isNetworkError),
      lastQuery: lastQuery ?? this.lastQuery,
    );
  }
}

class AiNotifier extends StateNotifier<AiState> {
  final AiRemoteDataSource _dataSource;

  AiNotifier(this._dataSource) : super(const AiState());

  Future<void> ask(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    state = state.copyWith(
      isLoading: true,
      currentQuery: cleanQuery,
      lastQuery: cleanQuery,
      clearError: true,
    );

    final conversationalReply = ConversationalIntent.detect(cleanQuery);

    try {
      var result = await _dataSource.askMemory(query: cleanQuery);
      if (conversationalReply != null) {
        result = GroundedAnswer(
          answer: conversationalReply,
          hasSufficientEvidence: true,
          citations: const [],
          latencyMs: result.latencyMs,
          modelName: 'zuri-conversational-v1',
          tokensUsed: conversationalReply.split(' ').length,
        );
      }
      state = state.copyWith(
        isLoading: false,
        answer: result,
        clearError: true,
      );
    } catch (e) {
      if (conversationalReply != null) {
        state = state.copyWith(
          isLoading: false,
          answer: GroundedAnswer(
            answer: conversationalReply,
            hasSufficientEvidence: true,
            citations: const [],
            latencyMs: 1.0,
            modelName: 'zuri-conversational-v1',
            tokensUsed: conversationalReply.split(' ').length,
          ),
          clearError: true,
        );
      } else {
        final friendly = FriendlyError.toFriendlyMessage(e);
        final isNet = FriendlyError.isNetworkError(e);
        state = state.copyWith(
          isLoading: false,
          errorMessage: friendly,
          isNetworkError: isNet,
          lastQuery: cleanQuery,
        );
      }
    }
  }

  Future<void> retry() async {
    if (state.lastQuery != null && state.lastQuery!.isNotEmpty) {
      await ask(state.lastQuery!);
    }
  }

  void clear() {
    state = const AiState();
  }
}

final aiNotifierProvider =
    StateNotifierProvider<AiNotifier, AiState>((ref) {
  final dataSource = ref.watch(aiRemoteDataSourceProvider);
  return AiNotifier(dataSource);
});

// ---------------------------------------------------------------------------
// Conversational Memory State & Notifier
// ---------------------------------------------------------------------------

class ConversationState {
  final bool isLoadingList;
  final bool isLoadingConversation;
  final bool isSendingMessage;
  final List<ConversationSummary> conversations;
  final ConversationDetail? currentConversation;
  final String? errorMessage;
  final bool isNetworkError;
  final String? lastFailedQuery;

  const ConversationState({
    this.isLoadingList = false,
    this.isLoadingConversation = false,
    this.isSendingMessage = false,
    this.conversations = const [],
    this.currentConversation,
    this.errorMessage,
    this.isNetworkError = false,
    this.lastFailedQuery,
  });

  ConversationState copyWith({
    bool? isLoadingList,
    bool? isLoadingConversation,
    bool? isSendingMessage,
    List<ConversationSummary>? conversations,
    ConversationDetail? currentConversation,
    String? errorMessage,
    bool? isNetworkError,
    String? lastFailedQuery,
    bool clearCurrentConversation = false,
    bool clearError = false,
  }) {
    return ConversationState(
      isLoadingList: isLoadingList ?? this.isLoadingList,
      isLoadingConversation:
          isLoadingConversation ?? this.isLoadingConversation,
      isSendingMessage: isSendingMessage ?? this.isSendingMessage,
      conversations: conversations ?? this.conversations,
      currentConversation: clearCurrentConversation
          ? null
          : (currentConversation ?? this.currentConversation),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isNetworkError: clearError ? false : (isNetworkError ?? this.isNetworkError),
      lastFailedQuery: lastFailedQuery ?? this.lastFailedQuery,
    );
  }
}

class ConversationNotifier extends StateNotifier<ConversationState> {
  final AiRemoteDataSource _dataSource;

  ConversationNotifier(this._dataSource) : super(const ConversationState()) {
    loadConversations();
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoadingList: true, clearError: true);
    try {
      final list = await _dataSource.listConversations();
      state = state.copyWith(
        isLoadingList: false,
        conversations: list,
        clearError: true,
      );

      // If we don't have an active conversation and list has items, select the most recent
      if (state.currentConversation == null && list.isNotEmpty) {
        await selectConversation(list.first.id);
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingList: false,
        errorMessage: FriendlyError.toFriendlyMessage(
          e,
          defaultFallback: 'Unable to load conversations.',
        ),
        isNetworkError: FriendlyError.isNetworkError(e),
      );
    }
  }

  Future<void> selectConversation(String conversationId) async {
    state = state.copyWith(isLoadingConversation: true, clearError: true);
    try {
      final detail = await _dataSource.getConversation(conversationId);
      state = state.copyWith(
        isLoadingConversation: false,
        currentConversation: detail,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingConversation: false,
        errorMessage: FriendlyError.toFriendlyMessage(
          e,
          defaultFallback: 'Unable to open conversation.',
        ),
        isNetworkError: FriendlyError.isNetworkError(e),
      );
    }
  }

  Future<ConversationDetail?> startNewConversation({String? title}) async {
    state = state.copyWith(isLoadingConversation: true, clearError: true);
    try {
      final newConv = await _dataSource.createConversation(title: title);
      final updatedList = [
        ConversationSummary(
          id: newConv.id,
          userId: newConv.userId,
          title: newConv.title,
          messageCount: newConv.messages.length,
          createdAt: newConv.createdAt,
          updatedAt: newConv.updatedAt,
        ),
        ...state.conversations,
      ];
      state = state.copyWith(
        isLoadingConversation: false,
        conversations: updatedList,
        currentConversation: newConv,
        clearError: true,
      );
      return newConv;
    } catch (e) {
      state = state.copyWith(
        isLoadingConversation: false,
        errorMessage: FriendlyError.toFriendlyMessage(
          e,
          defaultFallback: 'Unable to create conversation.',
        ),
        isNetworkError: FriendlyError.isNetworkError(e),
      );
      return null;
    }
  }

  Future<void> renameConversation(String conversationId, String newTitle) async {
    final cleanTitle = newTitle.trim();
    if (cleanTitle.isEmpty) return;
    try {
      final updated = await _dataSource.renameConversation(
        conversationId: conversationId,
        title: cleanTitle,
      );
      final updatedList = state.conversations.map((c) {
        if (c.id == conversationId) {
          return updated;
        }
        return c;
      }).toList();

      ConversationDetail? updatedCurrent = state.currentConversation;
      if (updatedCurrent != null && updatedCurrent.id == conversationId) {
        updatedCurrent = ConversationDetail(
          id: updatedCurrent.id,
          userId: updatedCurrent.userId,
          title: updated.title,
          createdAt: updatedCurrent.createdAt,
          updatedAt: updated.updatedAt,
          messages: updatedCurrent.messages,
        );
      }

      state = state.copyWith(
        conversations: updatedList,
        currentConversation: updatedCurrent,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: FriendlyError.toFriendlyMessage(
          e,
          defaultFallback: 'Unable to rename conversation.',
        ),
        isNetworkError: FriendlyError.isNetworkError(e),
      );
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await _dataSource.deleteConversation(conversationId);
      final updatedList =
          state.conversations.where((c) => c.id != conversationId).toList();
      ConversationDetail? nextCurrent;
      if (state.currentConversation?.id == conversationId) {
        nextCurrent = null;
      } else {
        nextCurrent = state.currentConversation;
      }

      state = state.copyWith(
        conversations: updatedList,
        currentConversation: nextCurrent,
        clearCurrentConversation: nextCurrent == null,
        clearError: true,
      );

      if (nextCurrent == null && updatedList.isNotEmpty) {
        await selectConversation(updatedList.first.id);
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: FriendlyError.toFriendlyMessage(
          e,
          defaultFallback: 'Unable to delete conversation.',
        ),
        isNetworkError: FriendlyError.isNetworkError(e),
      );
    }
  }

  Future<void> sendMessage(String query, {bool isRetry = false}) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // If no active conversation exists, create one first
    if (state.currentConversation == null) {
      final titlePreview = clean.length > 30 ? '${clean.substring(0, 30)}...' : clean;
      final created = await startNewConversation(title: titlePreview);
      if (created == null) return;
    }

    final activeId = state.currentConversation!.id;

    // Check if we can reuse existing optimistic message (on retry)
    List<ConversationMessageItem> currentMessages;
    final existingMsgs = state.currentConversation!.messages;
    if (isRetry &&
        existingMsgs.isNotEmpty &&
        existingMsgs.last.role == 'user' &&
        existingMsgs.last.content == clean) {
      currentMessages = existingMsgs;
    } else {
      final optimisticUserMsg = ConversationMessageItem(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: activeId,
        role: 'user',
        content: clean,
        citations: const [],
        hasSufficientEvidence: true,
        createdAt: DateTime.now(),
      );
      currentMessages = [
        ...existingMsgs,
        optimisticUserMsg,
      ];
    }

    state = state.copyWith(
      isSendingMessage: true,
      clearError: true,
      currentConversation: ConversationDetail(
        id: state.currentConversation!.id,
        userId: state.currentConversation!.userId,
        title: state.currentConversation!.title,
        createdAt: state.currentConversation!.createdAt,
        updatedAt: DateTime.now(),
        messages: currentMessages,
      ),
    );

    final conversationalReply = ConversationalIntent.detect(clean);

    // If it's pure chit-chat / greeting, reply locally and never fail due to network drops!
    if (conversationalReply != null) {
      try {
        await _dataSource.sendConversationMessage(
          conversationId: activeId,
          query: clean,
        );
      } catch (_) {
        // Silently tolerate server/network issues for conversational chitchat
      }

      final assistantMsg = ConversationMessageItem(
        id: 'chat_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: activeId,
        role: 'assistant',
        content: conversationalReply,
        citations: const [],
        hasSufficientEvidence: true,
        createdAt: DateTime.now(),
      );

      final withAssistant = [
        ...currentMessages,
        assistantMsg,
      ];

      final updatedList = state.conversations.map((c) {
        if (c.id == activeId) {
          return ConversationSummary(
            id: c.id,
            userId: c.userId,
            title: c.title == 'New Conversation'
                ? (clean.length > 25 ? '${clean.substring(0, 25)}...' : clean)
                : c.title,
            messageCount: withAssistant.length,
            lastMessagePreview: assistantMsg.content,
            createdAt: c.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        return c;
      }).toList();

      state = state.copyWith(
        isSendingMessage: false,
        conversations: updatedList,
        currentConversation: ConversationDetail(
          id: state.currentConversation!.id,
          userId: state.currentConversation!.userId,
          title: state.currentConversation!.title,
          createdAt: state.currentConversation!.createdAt,
          updatedAt: DateTime.now(),
          messages: withAssistant,
        ),
        clearError: true,
      );
      return;
    }

    // Memory-seeking query: requires retrieval
    try {
      final assistantMsg = await _dataSource.sendConversationMessage(
        conversationId: activeId,
        query: clean,
      );

      final withAssistant = [
        ...currentMessages,
        assistantMsg,
      ];

      // Refresh conversation summary title
      final updatedList = state.conversations.map((c) {
        if (c.id == activeId) {
          return ConversationSummary(
            id: c.id,
            userId: c.userId,
            title: c.title == 'New Conversation'
                ? (clean.length > 25 ? '${clean.substring(0, 25)}...' : clean)
                : c.title,
            messageCount: withAssistant.length,
            lastMessagePreview: assistantMsg.content,
            createdAt: c.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        return c;
      }).toList();

      state = state.copyWith(
        isSendingMessage: false,
        conversations: updatedList,
        currentConversation: ConversationDetail(
          id: state.currentConversation!.id,
          userId: state.currentConversation!.userId,
          title: state.currentConversation!.title,
          createdAt: state.currentConversation!.createdAt,
          updatedAt: DateTime.now(),
          messages: withAssistant,
        ),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isSendingMessage: false,
        errorMessage: FriendlyError.toFriendlyMessage(e),
        isNetworkError: FriendlyError.isNetworkError(e),
        lastFailedQuery: clean,
      );
    }
  }

  Future<void> retryLastMessage() async {
    final query = state.lastFailedQuery;
    if (query != null && query.isNotEmpty) {
      await sendMessage(query, isRetry: true);
    }
  }
}

final conversationProvider =
    StateNotifierProvider<ConversationNotifier, ConversationState>((ref) {
  final dataSource = ref.watch(aiRemoteDataSourceProvider);
  return ConversationNotifier(dataSource);
});

// ---------------------------------------------------------------------------
// Related Memories Provider
// ---------------------------------------------------------------------------

final relatedMemoriesProvider =
    FutureProvider.family<List<RelatedMemory>, String>((ref, noteId) async {
  final dataSource = ref.watch(aiRemoteDataSourceProvider);
  return dataSource.getRelatedMemories(noteId);
});

// ---------------------------------------------------------------------------
// Memory Recap Provider
// ---------------------------------------------------------------------------

final memoryRecapProvider =
    FutureProvider.family<MemoryRecap, String>((ref, period) async {
  final dataSource = ref.watch(aiRemoteDataSourceProvider);
  return dataSource.getMemoryRecap(period: period);
});
