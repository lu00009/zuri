import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbrain/data/datasources/remote/ai_remote_data_source.dart';
import 'package:pocketbrain/presentation/providers/ai_provider.dart';
import 'package:pocketbrain/presentation/screens/ai_memory_screen.dart';

class FakeAiRemoteDataSource implements AiRemoteDataSource {
  final GroundedAnswer? stubbedAnswer;
  final bool shouldThrow;
  String? lastQuery;

  FakeAiRemoteDataSource({this.stubbedAnswer, this.shouldThrow = false});

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
    expect(find.text('PocketBrain AI'), findsOneWidget);
    expect(find.text('Flutter State Management'), findsOneWidget);
    expect(find.text('Database & Migrations'), findsOneWidget);
    expect(find.text('Personal AI Memory'), findsOneWidget);
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

    // Tap the 'Flutter State Management' chip
    await tester.tap(find.text('Flutter State Management'));
    await tester.pump(); // Start request
    await tester.pump(); // Finish future and rebuild

    // Verify query was sent
    expect(fakeSource.lastQuery, 'Flutter State Management');

    // Verify answer card displayed
    expect(find.text('Grounded in Notes'), findsOneWidget);
    expect(
      find.text('Riverpod was chosen for Flutter state management due to compile-safety.'),
      findsOneWidget,
    );

    // Verify citation card displayed
    expect(find.text('Sources & Citations (1)'), findsOneWidget);
    expect(find.text('Flutter State Management'), findsNWidgets(3)); // Input text + Chip + Citation Title
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
    expect(find.text('Insufficient Evidence'), findsOneWidget);
    expect(find.text('Insufficient information in your saved notes to answer this question.'), findsOneWidget);
    expect(find.textContaining('Sources & Citations'), findsNothing);
  });

  testWidgets('Displays error banner and retry button on query failure',
      (tester) async {
    final fakeSource = FakeAiRemoteDataSource(shouldThrow: true);

    await tester.pumpWidget(createTestWidget(fakeDataSource: fakeSource));
    await tester.pump();

    await tester.tap(find.text('Database & Migrations'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Query Failed'), findsOneWidget);
    expect(find.textContaining('Network connection refused'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
