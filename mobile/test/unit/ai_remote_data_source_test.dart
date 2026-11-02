import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/data/datasources/remote/ai_remote_data_source.dart';

void main() {
  group('AI Data Models & JSON Serialization', () {
    test('MemoryCitation correctly parses JSON', () {
      final json = {
        'note_id': 'note-123',
        'note_title': 'Architecture Decision',
        'excerpt': 'We chose SQLite for local offline persistence.',
        'similarity': 0.88,
      };

      final citation = MemoryCitation.fromJson(json);

      expect(citation.noteId, 'note-123');
      expect(citation.noteTitle, 'Architecture Decision');
      expect(citation.excerpt, 'We chose SQLite for local offline persistence.');
      expect(citation.similarity, 0.88);
    });

    test('GroundedAnswer correctly parses JSON with citations', () {
      final json = {
        'answer': 'We decided on SQLite because it guarantees ACID transactions.',
        'has_sufficient_evidence': true,
        'citations': [
          {
            'note_id': 'note-123',
            'note_title': 'Architecture Decision',
            'excerpt': 'We chose SQLite for local offline persistence.',
            'similarity': 0.88,
          }
        ],
        'latency_ms': 14.5,
        'model_name': 'pocketbrain-grounded-v1',
        'tokens_used': 32,
      };

      final answer = GroundedAnswer.fromJson(json);

      expect(answer.answer, contains('SQLite'));
      expect(answer.hasSufficientEvidence, isTrue);
      expect(answer.citations.length, 1);
      expect(answer.citations.first.noteId, 'note-123');
      expect(answer.latencyMs, 14.5);
      expect(answer.modelName, 'pocketbrain-grounded-v1');
      expect(answer.tokensUsed, 32);
    });

    test('GroundedAnswer handles empty/insufficient evidence gracefully', () {
      final json = {
        'answer': 'Insufficient information in your saved notes to answer this question.',
        'has_sufficient_evidence': false,
        'citations': [],
        'latency_ms': 3.2,
        'model_name': 'pocketbrain-grounded-v1',
        'tokens_used': 5,
      };

      final answer = GroundedAnswer.fromJson(json);

      expect(answer.hasSufficientEvidence, isFalse);
      expect(answer.citations, isEmpty);
      expect(answer.answer, contains('Insufficient information'));
    });

    test('SemanticSearchResult correctly parses JSON', () {
      final json = {
        'note_id': 'note-456',
        'title': 'Flutter Riverpod Notes',
        'content': 'Riverpod provides compile-safe dependency injection.',
        'project_id': 'proj-1',
        'tags': ['flutter', 'state-management'],
        'similarity': 0.76,
      };

      final result = SemanticSearchResult.fromJson(json);

      expect(result.noteId, 'note-456');
      expect(result.title, 'Flutter Riverpod Notes');
      expect(result.projectId, 'proj-1');
      expect(result.tags, contains('flutter'));
      expect(result.similarity, 0.76);
    });
  });
}
