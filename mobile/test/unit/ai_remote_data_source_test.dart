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

    test('ConversationSummary and ConversationDetail correctly parse JSON', () {
      final summaryJson = {
        'id': 'conv-101',
        'user_id': 'user-1',
        'title': 'Database Choices',
        'message_count': 4,
        'last_message_preview': 'PostgreSQL was selected for structured data.',
        'created_at': '2026-11-05T10:00:00Z',
        'updated_at': '2026-11-05T10:15:00Z',
      };

      final summary = ConversationSummary.fromJson(summaryJson);
      expect(summary.id, 'conv-101');
      expect(summary.title, 'Database Choices');
      expect(summary.messageCount, 4);
      expect(summary.lastMessagePreview, contains('PostgreSQL'));

      final detailJson = {
        'id': 'conv-101',
        'user_id': 'user-1',
        'title': 'Database Choices',
        'created_at': '2026-11-05T10:00:00Z',
        'updated_at': '2026-11-05T10:15:00Z',
        'messages': [
          {
            'id': 'msg-1',
            'conversation_id': 'conv-101',
            'role': 'user',
            'content': 'What database did I choose?',
            'citations': [],
            'has_sufficient_evidence': true,
            'created_at': '2026-11-05T10:00:00Z',
          },
          {
            'id': 'msg-2',
            'conversation_id': 'conv-101',
            'role': 'assistant',
            'content': 'You chose PostgreSQL.',
            'citations': [
              {
                'note_id': 'note-db',
                'note_title': 'DB Architecture',
                'excerpt': 'PostgreSQL is our primary DB.',
                'similarity': 0.95,
              }
            ],
            'has_sufficient_evidence': true,
            'created_at': '2026-11-05T10:00:05Z',
          }
        ],
      };

      final detail = ConversationDetail.fromJson(detailJson);
      expect(detail.id, 'conv-101');
      expect(detail.messages.length, 2);
      expect(detail.messages.last.citations.length, 1);
      expect(detail.messages.last.citations.first.noteTitle, 'DB Architecture');
    });

    test('RelatedMemory correctly parses JSON with explanation', () {
      final json = {
        'note_id': 'note-rel-1',
        'title': 'FastAPI Development Guide',
        'excerpt': 'FastAPI is used for our backend microservices.',
        'similarity': 0.82,
        'project_id': 'backend',
        'tags': ['python', 'fastapi'],
        'shared_tags': ['fastapi'],
        'explanation': 'Both notes cover FastAPI backend API patterns.',
      };

      final related = RelatedMemory.fromJson(json);
      expect(related.noteId, 'note-rel-1');
      expect(related.title, 'FastAPI Development Guide');
      expect(related.similarity, 0.82);
      expect(related.sharedTags, contains('fastapi'));
      expect(related.explanation, contains('FastAPI backend API patterns'));
    });

    test('MemoryRecap correctly parses JSON categories and decisions', () {
      final json = {
        'period': 'weekly',
        'start_date': '2026-10-29T00:00:00Z',
        'end_date': '2026-11-05T23:59:59Z',
        'total_notes': 3,
        'overview': 'Over this weekly period, you worked on AI assistant features.',
        'categories': [
          {
            'category': 'Projects',
            'description': 'Project-specific work',
            'highlights': [
              {
                'note_id': 'note-ai',
                'note_title': 'PocketBrain AI',
                'summary': 'Built conversational memory engine.',
                'tags': ['ai', 'memory'],
                'updated_at': '2026-11-05T12:00:00Z',
              }
            ],
          }
        ],
        'important_decisions': ['Selected PostgreSQL for relational data.'],
        'recurring_topics': ['embeddings', 'retrieval'],
        'unfinished_ideas': ['Explore automated memory clustering graph.'],
      };

      final recap = MemoryRecap.fromJson(json);
      expect(recap.period, 'weekly');
      expect(recap.totalNotes, 3);
      expect(recap.categories.length, 1);
      expect(recap.categories.first.category, 'Projects');
      expect(recap.categories.first.highlights.first.noteTitle, 'PocketBrain AI');
      expect(recap.importantDecisions, contains('Selected PostgreSQL for relational data.'));
      expect(recap.recurringTopics, contains('embeddings'));
      expect(recap.unfinishedIdeas, contains('Explore automated memory clustering graph.'));
    });
  });
}
