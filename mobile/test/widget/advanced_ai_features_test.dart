import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbrain/data/datasources/remote/ai_remote_data_source.dart';
import 'package:pocketbrain/presentation/providers/ai_provider.dart';
import 'package:pocketbrain/presentation/screens/ai_memory_screen.dart';
import 'package:pocketbrain/presentation/screens/memory_recap_screen.dart';

class MockAdvancedAiRemoteDataSource implements AiRemoteDataSource {
  final List<ConversationSummary> mockConversations = [
    ConversationSummary(
      id: 'conv-1',
      userId: 'user-1',
      title: 'Database Choices',
      messageCount: 2,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
  ];

  @override
  Future<List<ConversationSummary>> listConversations({int limit = 30}) async {
    return mockConversations;
  }

  @override
  Future<ConversationDetail> getConversation(String conversationId) async {
    return ConversationDetail(
      id: conversationId,
      userId: 'user-1',
      title: 'Database Choices',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      updatedAt: DateTime.now(),
      messages: [
        ConversationMessageItem(
          id: 'msg-1',
          conversationId: conversationId,
          role: 'user',
          content: 'What database did I choose for my project?',
          citations: const [],
          hasSufficientEvidence: true,
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
        ConversationMessageItem(
          id: 'msg-2',
          conversationId: conversationId,
          role: 'assistant',
          content: 'Your notes indicate that you selected PostgreSQL.',
          citations: const [
            MemoryCitation(
              noteId: 'note-db-1',
              noteTitle: 'Database Architecture Plan',
              excerpt: 'We selected PostgreSQL for relational data persistence.',
              similarity: 0.91,
            ),
          ],
          hasSufficientEvidence: true,
          createdAt: DateTime.now().subtract(const Duration(minutes: 9)),
        ),
      ],
    );
  }

  @override
  Future<ConversationDetail> createConversation({String? title}) async {
    final conv = ConversationDetail(
      id: 'conv-new',
      userId: 'user-1',
      title: title ?? 'New Conversation',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [],
    );
    mockConversations.insert(
      0,
      ConversationSummary(
        id: conv.id,
        userId: conv.userId,
        title: conv.title,
        messageCount: 0,
        createdAt: conv.createdAt,
        updatedAt: conv.updatedAt,
      ),
    );
    return conv;
  }

  @override
  Future<ConversationSummary> renameConversation({
    required String conversationId,
    required String title,
  }) async {
    return ConversationSummary(
      id: conversationId,
      userId: 'user-1',
      title: title,
      messageCount: 2,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    mockConversations.removeWhere((c) => c.id == conversationId);
  }

  @override
  Future<ConversationMessageItem> sendConversationMessage({
    required String conversationId,
    required String query,
    int topK = 5,
    double similarityThreshold = 0.20,
  }) async {
    return ConversationMessageItem(
      id: 'msg-followup',
      conversationId: conversationId,
      role: 'assistant',
      content: 'PostgreSQL was selected because it guarantees ACID transactions and structured querying.',
      citations: const [
        MemoryCitation(
          noteId: 'note-db-1',
          noteTitle: 'Database Architecture Plan',
          excerpt: 'PostgreSQL provides ACID compliance for multi-tenant data.',
          similarity: 0.89,
        ),
      ],
      hasSufficientEvidence: true,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<RelatedMemory>> getRelatedMemories(
    String noteId, {
    int limit = 5,
    double minSimilarity = 0.15,
  }) async {
    return const [
      RelatedMemory(
        noteId: 'note-rel-1',
        title: 'Backend Project Architecture',
        excerpt: 'Discusses database migration and schema setup.',
        similarity: 0.84,
        tags: ['backend', 'postgres'],
        sharedTags: ['postgres'],
        explanation: 'Both notes cover database architecture and PostgreSQL configuration.',
      ),
    ];
  }

  @override
  Future<MemoryRecap> getMemoryRecap({
    String period = 'weekly',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return MemoryRecap(
      period: period,
      startDate: DateTime.now().subtract(const Duration(days: 7)),
      endDate: DateTime.now(),
      totalNotes: 4,
      overview: 'Over this week, you focused heavily on AI memory and backend database setup.',
      categories: [
        MemoryRecapCategory(
          category: 'Projects',
          description: 'Project development notes',
          highlights: [
            MemoryRecapHighlight(
              noteId: 'note-db-1',
              noteTitle: 'Database Architecture Plan',
              summary: 'Selected PostgreSQL for structured relational data.',
              tags: const ['postgres', 'architecture'],
              updatedAt: DateTime.now(),
            ),
          ],
        ),
        MemoryRecapCategory(
          category: 'Learning',
          description: 'Technical learning',
          highlights: [
            MemoryRecapHighlight(
              noteId: 'note-ai-learn',
              noteTitle: 'Vector Embeddings in SQLite',
              summary: 'Studied cosine distance and hybrid retrieval.',
              tags: const ['ai', 'sqlite'],
              updatedAt: DateTime.now(),
            ),
          ],
        ),
      ],
      importantDecisions: const [
        'Chose PostgreSQL for structured application data.',
      ],
      recurringTopics: const ['PostgreSQL', 'Embeddings'],
      unfinishedIdeas: const [
        'Explore automatic relationships between saved memories.',
      ],
    );
  }

  @override
  Future<GroundedAnswer> askMemory({
    required String query,
    double similarityThreshold = 0.20,
    int topK = 5,
  }) async {
    return const GroundedAnswer(
      answer: 'Your notes indicate that you selected PostgreSQL.',
      hasSufficientEvidence: true,
      citations: [
        MemoryCitation(
          noteId: 'note-db-1',
          noteTitle: 'Database Architecture Plan',
          excerpt: 'We selected PostgreSQL for relational data persistence.',
          similarity: 0.91,
        ),
      ],
      latencyMs: 10.0,
      modelName: 'pocketbrain-grounded-v1',
      tokensUsed: 20,
    );
  }

  @override
  Future<List<SemanticSearchResult>> semanticSearch({
    required String query,
    int topK = 5,
  }) async {
    return [];
  }
}

void main() {
  group('Advanced AI Features Widget Tests', () {
    testWidgets('Conversational Chat renders history and handles follow-up message',
        (tester) async {
      final fakeDataSource = MockAdvancedAiRemoteDataSource();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRemoteDataSourceProvider.overrideWithValue(fakeDataSource),
          ],
          child: const MaterialApp(
            home: AiMemoryScreen(),
          ),
        ),
      );

      // Wait for initial conversation loading
      await tester.pumpAndSettle();

      // Check that existing conversation messages are displayed
      expect(find.text('What database did I choose for my project?'), findsOneWidget);
      expect(find.text('Your notes indicate that you selected PostgreSQL.'), findsOneWidget);
      expect(find.text('Grounded in Notes'), findsWidgets);
      expect(find.text('Database Architecture Plan'), findsWidgets);

      // Now enter a follow-up question
      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);
      await tester.enterText(inputField, 'Why did I choose it?');
      await tester.tap(find.byIcon(Icons.send_rounded));

      // Pump to trigger send message
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify follow-up user message and AI response appear in the conversation thread
      expect(find.text('Why did I choose it?'), findsOneWidget);
      expect(
        find.text('PostgreSQL was selected because it guarantees ACID transactions and structured querying.'),
        findsOneWidget,
      );
    });

    testWidgets('Memory Recap Screen renders overview, categories, and decisions',
        (tester) async {
      final fakeDataSource = MockAdvancedAiRemoteDataSource();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRemoteDataSourceProvider.overrideWithValue(fakeDataSource),
          ],
          child: const MaterialApp(
            home: MemoryRecapScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and period selector
      expect(find.text('Memory Recap'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('4 notes'), findsOneWidget);
      expect(find.textContaining('focused heavily on AI memory'), findsOneWidget);

      // Verify Categories
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Database Architecture Plan'), findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Vector Embeddings in SQLite'), findsOneWidget);

      // Scroll down to reveal Decisions and Unfinished Ideas
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Verify Decisions and Unfinished Ideas
      expect(find.text('Important Decisions'), findsOneWidget);
      expect(find.text('Chose PostgreSQL for structured application data.'), findsOneWidget);
      expect(find.text('Unfinished Ideas'), findsOneWidget);
      expect(find.text('Explore automatic relationships between saved memories.'), findsOneWidget);
    });
  });
}
