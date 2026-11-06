import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/data/datasources/remote/conversational_intent.dart';

void main() {
  group('ConversationalIntent Tests', () {
    test('Separates conversational greetings from memory retrieval', () {
      // Greetings
      expect(ConversationalIntent.detect('Say hello to Zuri 👋'), isNotNull);
      expect(ConversationalIntent.detect('hi'), isNotNull);
      expect(ConversationalIntent.detect('hello'), isNotNull);
      expect(ConversationalIntent.detect('good morning'), isNotNull);
      expect(ConversationalIntent.detect('hey zuri'), isNotNull);

      // Identity & Capabilities
      expect(ConversationalIntent.detect('Who are you?'), isNotNull);
      expect(ConversationalIntent.detect('What can you do?'), isNotNull);
      expect(ConversationalIntent.detect('How are you doing?'), isNotNull);

      // Gratitude & Farewells
      expect(ConversationalIntent.detect('Thank you!'), isNotNull);
      expect(ConversationalIntent.detect('Goodbye!'), isNotNull);

      // Personal Memory Retrieval queries MUST NOT be intercepted as conversational
      expect(ConversationalIntent.detect('What did I save about my projects?'), isNull);
      expect(ConversationalIntent.detect('Find my notes on python'), isNull);
      expect(ConversationalIntent.detect('What do my notes say about the meeting?'), isNull);
      expect(ConversationalIntent.detect('Did I save any ideas about marketing?'), isNull);
      expect(ConversationalIntent.detect('Check my learning notes'), isNull);
    });
  });
}

