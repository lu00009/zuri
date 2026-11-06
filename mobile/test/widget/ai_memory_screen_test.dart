import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbrain/data/datasources/remote/ai_remote_data_source.dart';
import 'package:pocketbrain/presentation/providers/ai_provider.dart';
import 'package:pocketbrain/presentation/screens/ai_memory_screen.dart';

class FakeAiRemoteDataSource implements AiRemoteDataSource {
  final GroundedAnswer? stubbedAnswer;
  final List<ConversationSummary>? stubbedConversations;
  final bool shouldThrow;
  String? lastQuery;

  FakeAiRemoteDataSource({
    this.stubbedAnswer,
    this.stubbedConversations,
    this.shouldThrow = false,
  });

  @override
  Future<GroundedAnswer> askMemory({
    required String query,
    double similarityThreshold = 0.25,
    int topK = 3,
  }) async {
    lastQuery = query;
    if (shouldThrow) {
      throw Exception('Network connection refused');
    }
    return stubbedAnswer ??
        const GroundedAnswer(
          answer: 'Default grounded answer for test.',
          hasSufficientEvidence: true,
          citations: [
            MemoryCitation(
              noteId: 'test-note-1',
              noteTitle: 'Flutter Decisions',
              excerpt: 'Riverpod was chosen for dependency injection.',
              similarity: 0.85,
            ),
          ],
          latencyMs: 12.0,
          modelName: 'pocketbrain-grounded-v1',
          tokensUsed: 25,
        );
  }

  @override
  Future<List<SemanticSearchResult>> semanticSearch({
    required String query,
    int topK = 5,
  }) async {
    return [];
  }

  @override
  Future<ConversationDetail> createConversation({String? title}) async {
    return ConversationDetail(
      id: 'test-conv-1',
      userId: 'test-user-1',
      title: title ?? 'New Conversation',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [],
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({int limit = 30}) async {
    return stubbedConversations ?? [];
  }

  @override
  Future<ConversationDetail> getConversation(String conversationId) async {
    return ConversationDetail(
      id: conversationId,
      userId: 'test-user-1',
      title: 'Test Conversation',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [],
    );
  }

  @override
  Future<ConversationSummary> renameConversation({
    required String conversationId,
    required String title,
  }) async {
    return ConversationSummary(
      id: conversationId,
      userId: 'test-user-1',
      title: title,
      messageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {}

  @override
  Future<ConversationMessageItem> sendConversationMessage({
    required String conversationId,
    required String query,
    int topK = 5,
    double similarityThreshold = 0.20,
  }) async {
    lastQuery = query;
    return ConversationMessageItem(
      id: 'msg-1',
      conversationId: conversationId,
      role: 'assistant',
      content: stubbedAnswer?.answer ?? 'Test assistant answer',
      citations: stubbedAnswer?.citations ?? [],
      hasSufficientEvidence: stubbedAnswer?.hasSufficientEvidence ?? true,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<RelatedMemory>> getRelatedMemories(
    String noteId, {
    int limit = 5,
    double minSimilarity = 0.15,
  }) async {
    return [];
  }

  @override
  Future<MemoryRecap> getMemoryRecap({
    String period = 'weekly',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    return MemoryRecap(
      period: period,
      startDate: startDate ?? now.subtract(const Duration(days: 7)),
      endDate: endDate ?? now,
      totalNotes: 0,
      overview: 'Test recap overview',
      categories: [],
      importantDecisions: [],
      recurringTopics: [],
      unfinishedIdeas: [],
    );
  }
}

Widget createTestWidget({required FakeAiRemoteDataSource fakeDataSource}) {
  return ProviderScope(
    overrides: [
      aiRemoteDataSourceProvider.overrideWithValue(fakeDataSource),
    ],
    child: const MaterialApp(
      home: AiMemoryScreen(),
    ),
  );
}

void main() {
  testWidgets('Renders initial state with title, prompt chips, and welcome card',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource();

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pump();

    // Verify title and prompts
    expect(find.text('Zuri'), findsOneWidget);
    expect(find.text('Say hello to Zuri 👋'), findsOneWidget);
    expect(find.text('What can you do?'), findsOneWidget);
    expect(find.text('Meet Zuri, Your AI Assistant'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Clicking suggested chip triggers query and displays grounded response with citations',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource(
      stubbedAnswer: const GroundedAnswer(
        answer: 'Riverpod was chosen for Flutter state management due to compile-safety.',
        hasSufficientEvidence: true,
        citations: [
          MemoryCitation(
            noteId: 'eval-note-2',
            noteTitle: 'Flutter State Management',
            excerpt: 'We selected Riverpod 2.x for compile-time safety and provider composition.',
            similarity: 0.92,
          ),
        ],
        latencyMs: 15.0,
        modelName: 'pocketbrain-grounded-v1',
        tokensUsed: 30,
      ),
    );

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pump();

    // Enter query in TextField
    await tester.enterText(find.byType(TextField), 'Project notes & goals');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(); // Start request
    await tester.pump(); // Finish future and rebuild

    // Verify query was sent
    expect(fakeSource.lastQuery, 'Project notes & goals');

    // Verify answer card displayed
    expect(find.text('Grounded in Notes'), findsOneWidget);
    expect(
      find.text('Riverpod was chosen for Flutter state management due to compile-safety.'),
      findsOneWidget,
    );

    // Verify citation card displayed
    expect(find.text('Referenced Notes (1)'), findsOneWidget);
    expect(find.text('92% match'), findsOneWidget);
    expect(
      find.text('We selected Riverpod 2.x for compile-time safety and provider composition.'),
      findsOneWidget,
    );
  });

  testWidgets('Displays insufficient evidence banner when notes lack required information',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource(
      stubbedAnswer: const GroundedAnswer(
        answer: 'Insufficient information in your saved notes to answer this question.',
        hasSufficientEvidence: false,
        citations: [],
        latencyMs: 5.0,
        modelName: 'pocketbrain-grounded-v1',
        tokensUsed: 8,
      ),
    );

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pump();

    // Enter query in TextField
    await tester.enterText(find.byType(TextField), 'What is the recipe for chocolate cake?');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    // Verify insufficient evidence badge
    expect(find.text('No Matching Notes'), findsOneWidget);
    expect(find.text('Insufficient information in your saved notes to answer this question.'), findsOneWidget);
    expect(find.textContaining('Referenced Notes'), findsNothing);
  });

  testWidgets('Displays error banner and retry button on query failure',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource(shouldThrow: true);

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Project notes & goals');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();

    expect(find.text('Query Failed'), findsOneWidget);
    expect(find.textContaining('Network connection refused'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Tapping hamburger menu opens chat history drawer with previous conversations and New Chat button',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource(
      stubbedConversations: [
        ConversationSummary(
          id: 'conv-101',
          userId: 'user-1',
          title: 'Zuri Brainstorming',
          messageCount: 4,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ],
    );

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pumpAndSettle();

    // Verify hamburger icon is present
    expect(find.byIcon(Icons.menu), findsOneWidget);

    // Tap hamburger icon
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Verify drawer contents
    expect(find.text('Chat History'), findsOneWidget);
    expect(find.text('New Chat'), findsOneWidget);
    expect(find.text('Zuri Brainstorming'), findsOneWidget);
    expect(find.textContaining('4 msgs'), findsOneWidget);
  });
}
