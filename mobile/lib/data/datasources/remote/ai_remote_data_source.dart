import 'api_client.dart';

class MemoryCitation {
  final String noteId;
  final String noteTitle;
  final String excerpt;
  final double similarity;

  const MemoryCitation({
    required this.noteId,
    required this.noteTitle,
    required this.excerpt,
    required this.similarity,
  });

  factory MemoryCitation.fromJson(Map<String, dynamic> json) {
    return MemoryCitation(
      noteId: json['note_id'] as String? ?? '',
      noteTitle: json['note_title'] as String? ?? 'Untitled Note',
      excerpt: json['excerpt'] as String? ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class GroundedAnswer {
  final String answer;
  final bool hasSufficientEvidence;
  final List<MemoryCitation> citations;
  final double latencyMs;
  final String modelName;
  final int tokensUsed;

  const GroundedAnswer({
    required this.answer,
    required this.hasSufficientEvidence,
    required this.citations,
    required this.latencyMs,
    required this.modelName,
    required this.tokensUsed,
  });

  factory GroundedAnswer.fromJson(Map<String, dynamic> json) {
    final rawCitations = json['citations'] as List<dynamic>? ?? [];
    return GroundedAnswer(
      answer: json['answer'] as String? ?? '',
      hasSufficientEvidence: json['has_sufficient_evidence'] as bool? ?? false,
      citations: rawCitations
          .map((c) => MemoryCitation.fromJson(c as Map<String, dynamic>))
          .toList(),
      latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0.0,
      modelName: json['model_name'] as String? ?? 'unknown',
      tokensUsed: json['tokens_used'] as int? ?? 0,
    );
  }
}

class SemanticSearchResult {
  final String noteId;
  final String title;
  final String content;
  final String? projectId;
  final List<String> tags;
  final double similarity;

  const SemanticSearchResult({
    required this.noteId,
    required this.title,
    required this.content,
    this.projectId,
    required this.tags,
    required this.similarity,
  });

  factory SemanticSearchResult.fromJson(Map<String, dynamic> json) {
    final rawTags = (json['tags'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .toList() ??
        [];
    return SemanticSearchResult(
      noteId: json['note_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      content: json['content'] as String? ?? '',
      projectId: json['project_id'] as String?,
      tags: rawTags,
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced AI Memory Models
// ---------------------------------------------------------------------------

class ConversationSummary {
  final String id;
  final String userId;
  final String title;
  final int messageCount;
  final String? lastMessagePreview;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationSummary({
    required this.id,
    required this.userId,
    required this.title,
    required this.messageCount,
    this.lastMessagePreview,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'New Conversation',
      messageCount: json['message_count'] as int? ?? 0,
      lastMessagePreview: json['last_message_preview'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ConversationMessageItem {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final List<MemoryCitation> citations;
  final bool hasSufficientEvidence;
  final DateTime createdAt;

  const ConversationMessageItem({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.citations,
    required this.hasSufficientEvidence,
    required this.createdAt,
  });

  factory ConversationMessageItem.fromJson(Map<String, dynamic> json) {
    final rawCitations = json['citations'] as List<dynamic>? ?? [];
    return ConversationMessageItem(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      citations: rawCitations
          .map((c) => MemoryCitation.fromJson(c as Map<String, dynamic>))
          .toList(),
      hasSufficientEvidence: json['has_sufficient_evidence'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ConversationDetail {
  final String id;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ConversationMessageItem> messages;

  const ConversationDetail({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    final rawMsgs = json['messages'] as List<dynamic>? ?? [];
    return ConversationDetail(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'New Conversation',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messages: rawMsgs
          .map((m) => ConversationMessageItem.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RelatedMemory {
  final String noteId;
  final String title;
  final String excerpt;
  final double similarity;
  final String? projectId;
  final List<String> tags;
  final List<String> sharedTags;
  final String explanation;

  const RelatedMemory({
    required this.noteId,
    required this.title,
    required this.excerpt,
    required this.similarity,
    this.projectId,
    required this.tags,
    required this.sharedTags,
    required this.explanation,
  });

  factory RelatedMemory.fromJson(Map<String, dynamic> json) {
    final rawTags = (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
    final rawShared = (json['shared_tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
    return RelatedMemory(
      noteId: json['note_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      excerpt: json['excerpt'] as String? ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
      projectId: json['project_id'] as String?,
      tags: rawTags,
      sharedTags: rawShared,
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

class MemoryRecapHighlight {
  final String noteId;
  final String noteTitle;
  final String summary;
  final List<String> tags;
  final DateTime updatedAt;

  const MemoryRecapHighlight({
    required this.noteId,
    required this.noteTitle,
    required this.summary,
    required this.tags,
    required this.updatedAt,
  });

  factory MemoryRecapHighlight.fromJson(Map<String, dynamic> json) {
    final rawTags = (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
    return MemoryRecapHighlight(
      noteId: json['note_id'] as String? ?? '',
      noteTitle: json['note_title'] as String? ?? 'Untitled',
      summary: json['summary'] as String? ?? '',
      tags: rawTags,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class MemoryRecapCategory {
  final String category;
  final String description;
  final List<MemoryRecapHighlight> highlights;

  const MemoryRecapCategory({
    required this.category,
    required this.description,
    required this.highlights,
  });

  factory MemoryRecapCategory.fromJson(Map<String, dynamic> json) {
    final rawHighlights = json['highlights'] as List<dynamic>? ?? [];
    return MemoryRecapCategory(
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      highlights: rawHighlights
          .map((h) => MemoryRecapHighlight.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MemoryRecap {
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final int totalNotes;
  final String overview;
  final List<MemoryRecapCategory> categories;
  final List<String> importantDecisions;
  final List<String> recurringTopics;
  final List<String> unfinishedIdeas;

  const MemoryRecap({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.totalNotes,
    required this.overview,
    required this.categories,
    required this.importantDecisions,
    required this.recurringTopics,
    required this.unfinishedIdeas,
  });

  factory MemoryRecap.fromJson(Map<String, dynamic> json) {
    final rawCats = json['categories'] as List<dynamic>? ?? [];
    final rawDecs = (json['important_decisions'] as List<dynamic>?)?.map((d) => d.toString()).toList() ?? [];
    final rawTopics = (json['recurring_topics'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
    final rawIdeas = (json['unfinished_ideas'] as List<dynamic>?)?.map((i) => i.toString()).toList() ?? [];

    return MemoryRecap(
      period: json['period'] as String? ?? 'weekly',
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      totalNotes: json['total_notes'] as int? ?? 0,
      overview: json['overview'] as String? ?? '',
      categories: rawCats
          .map((c) => MemoryRecapCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
      importantDecisions: rawDecs,
      recurringTopics: rawTopics,
      unfinishedIdeas: rawIdeas,
    );
  }
}

class AiRemoteDataSource {
  final ApiClient _apiClient;

  AiRemoteDataSource(this._apiClient);

  Future<GroundedAnswer> askMemory({
    required String query,
    double similarityThreshold = 0.20,
    int topK = 5,
  }) async {
    final response = await _apiClient.dio.post(
      '/ai/ask',
      data: {
        'query': query,
        'similarity_threshold': similarityThreshold,
        'top_k': topK,
      },
    );

    return GroundedAnswer.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<SemanticSearchResult>> semanticSearch({
    required String query,
    int topK = 5,
  }) async {
    final response = await _apiClient.dio.get(
      '/ai/semantic-search',
      queryParameters: {
        'query': query,
        'top_k': topK,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final rawResults = data['results'] as List<dynamic>? ?? [];
    return rawResults
        .map((r) => SemanticSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Conversations ---

  Future<ConversationDetail> createConversation({String? title}) async {
    final response = await _apiClient.dio.post(
      '/ai/conversations',
      data: {'title': title},
    );
    return ConversationDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ConversationSummary>> listConversations({int limit = 30}) async {
    final response = await _apiClient.dio.get(
      '/ai/conversations',
      queryParameters: {'limit': limit},
    );
    final rawList = response.data as List<dynamic>? ?? [];
    return rawList
        .map((item) => ConversationSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ConversationDetail> getConversation(String conversationId) async {
    final response = await _apiClient.dio.get(
      '/ai/conversations/$conversationId',
    );
    return ConversationDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ConversationSummary> renameConversation({
    required String conversationId,
    required String title,
  }) async {
    final response = await _apiClient.dio.patch(
      '/ai/conversations/$conversationId',
      data: {'title': title},
    );
    return ConversationSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteConversation(String conversationId) async {
    await _apiClient.dio.delete('/ai/conversations/$conversationId');
  }

  Future<ConversationMessageItem> sendConversationMessage({
    required String conversationId,
    required String query,
    int topK = 5,
    double similarityThreshold = 0.20,
  }) async {
    final response = await _apiClient.dio.post(
      '/ai/conversations/$conversationId/messages',
      data: {
        'query': query,
        'top_k': topK,
        'similarity_threshold': similarityThreshold,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final assistantMap = data['assistant_message'] as Map<String, dynamic>;
    return ConversationMessageItem.fromJson(assistantMap);
  }

  // --- Related Memories ---

  Future<List<RelatedMemory>> getRelatedMemories(
    String noteId, {
    int limit = 5,
    double minSimilarity = 0.15,
  }) async {
    final response = await _apiClient.dio.get(
      '/ai/notes/$noteId/related',
      queryParameters: {
        'limit': limit,
        'min_similarity': minSimilarity,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final rawList = data['related'] as List<dynamic>? ?? [];
    return rawList
        .map((r) => RelatedMemory.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Memory Recap ---

  Future<MemoryRecap> getMemoryRecap({
    String period = 'weekly',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, dynamic>{'period': period};
    if (startDate != null) params['start_date'] = startDate.toIso8601String();
    if (endDate != null) params['end_date'] = endDate.toIso8601String();

    final response = await _apiClient.dio.get(
      '/ai/recap',
      queryParameters: params,
    );
    return MemoryRecap.fromJson(response.data as Map<String, dynamic>);
  }
}
