import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/remote/ai_remote_data_source.dart';
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

  const AiState({
    this.isLoading = false,
    this.currentQuery = '',
    this.answer,
    this.errorMessage,
  });

  AiState copyWith({
    bool? isLoading,
    String? currentQuery,
    GroundedAnswer? answer,
    String? errorMessage,
    bool clearAnswer = false,
    bool clearError = false,
  }) {
    return AiState(
      isLoading: isLoading ?? this.isLoading,
      currentQuery: currentQuery ?? this.currentQuery,
      answer: clearAnswer ? null : (answer ?? this.answer),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
      clearError: true,
    );

    try {
      final result = await _dataSource.askMemory(query: cleanQuery);
      state = state.copyWith(
        isLoading: false,
        answer: result,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to retrieve grounded memory: $e',
      );
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

  const ConversationState({
    this.isLoadingList = false,
    this.isLoadingConversation = false,
    this.isSendingMessage = false,
    this.conversations = const [],
    this.currentConversation,
    this.errorMessage,
  });

  ConversationState copyWith({
    bool? isLoadingList,
    bool? isLoadingConversation,
    bool? isSendingMessage,
    List<ConversationSummary>? conversations,
    ConversationDetail? currentConversation,
    String? errorMessage,
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
        errorMessage: 'Failed to load conversations: $e',
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
        errorMessage: 'Failed to open conversation: $e',
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
        errorMessage: 'Failed to create conversation: $e',
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
      state = state.copyWith(errorMessage: 'Failed to rename conversation: $e');
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
      state = state.copyWith(errorMessage: 'Failed to delete conversation: $e');
    }
  }

  Future<void> sendMessage(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // If no active conversation exists, create one first
    if (state.currentConversation == null) {
      final titlePreview = clean.length > 30 ? '${clean.substring(0, 30)}...' : clean;
      final created = await startNewConversation(title: titlePreview);
      if (created == null) return;
    }

    final activeId = state.currentConversation!.id;

    // Optimistically append user message to local state
    final optimisticUserMsg = ConversationMessageItem(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: activeId,
      role: 'user',
      content: clean,
      citations: const [],
      hasSufficientEvidence: true,
      createdAt: DateTime.now(),
    );

    final currentMessages = [
      ...state.currentConversation!.messages,
      optimisticUserMsg,
    ];

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

    try {
      final assistantMsg = await _dataSource.sendConversationMessage(
        conversationId: activeId,
        query: clean,
      );

      final withAssistant = [
        ...currentMessages,
        assistantMsg,
      ];

      // Also refresh the conversation summary title if it was default
      final updatedList = state.conversations.map((c) {
        if (c.id == activeId) {
          return ConversationSummary(
            id: c.id,
            userId: c.userId,
            title: c.title == 'New Conversation' ? (clean.length > 25 ? '${clean.substring(0, 25)}...' : clean) : c.title,
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
        errorMessage: 'Failed to send message: $e',
      );
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
