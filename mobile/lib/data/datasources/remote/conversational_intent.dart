class ConversationalIntent {
  /// Detects whether a query is purely conversational (greetings, identity, capabilities, gratitude, farewells, feedback)
  /// rather than personal memory-search.
  /// Returns a friendly natural response if conversational, or `null` to trigger note retrieval.
  static String? detect(String query) {
    final clean = query.trim().toLowerCase();
    // Strip emojis and punctuation for clean token matching
    final normalized = clean.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalized.isEmpty) return null;

    // If query has explicit memory-seeking keywords, it should search notes
    final memoryPattern = RegExp(
      r'\b(save|saved|my\s+notes?|notes?\s+about|notes?\s+on|did\s+i|what\s+did\s+i|what\s+do\s+i\s+have|my\s+projects?|my\s+ideas?|my\s+learnings?|my\s+meetings?|remind\s+me|search\s+for|find\s+notes?|look\s+up|what\s+were\s+my|check\s+my)\b',
    );
    final isAboutAi = RegExp(r'\b(who\s+are\s+you|what\s+can\s+you\s+do)\b').hasMatch(normalized);
    if (!isAboutAi && memoryPattern.hasMatch(normalized)) {
      return null;
    }

    // 1. Emotional expressions, corrections, and criticisms
    if (RegExp(r'\b(liar|lying|you\s+lie|you\s+are\s+a\s+liar|youre\s+a\s+liar|fake)\b').hasMatch(normalized)) {
      return "I'm sorry if I gave you an inaccurate or confusing response! I only aim to help you recall what you've saved. What can I look up or clarify for you?";
    }
    if (RegExp(r'\b(wrong|incorrect|not\s+true|thats\s+wrong|you\s+are\s+wrong|youre\s+wrong)\b').hasMatch(normalized)) {
      return "My apologies for the confusion! Let me know what information was incorrect or what you'd like me to look up in your notes.";
    }

    // 2. Farewells
    if (RegExp(r'\b(goodbye|bye|bye\s*bye|see\s*(you|ya|u)|farewell|talk\s*to\s*you\s*later|good\s*night|cya)\b').hasMatch(normalized) &&
        !RegExp(r'\b(what|why|which|how|where|when)\b').hasMatch(normalized)) {
      if (normalized.contains('night')) {
        return "Good night! Rest well, and I'll be right here whenever you're ready to pick up your notes again.";
      }
      return "Goodbye! Have a great day ahead. Whenever you have a new thought or question, I'll be right here.";
    }

    // 3. Thank you / Gratitude
    if (RegExp(r'\b(thank\s*you|thanks|thank\s+you\s+so\s+much|thanks\s+a\s+lot|appreciate\s+it|thx)\b').hasMatch(normalized) &&
        !RegExp(r'\b(what|why|which|how|where|when)\b').hasMatch(normalized)) {
      return "You're very welcome! If there's anything else you'd like to check or remember, just let me know.";
    }

    // 4. How are you / Well-being
    if (RegExp(r'\b(how\s+are\s+you|how\s+are\s+you\s+doing|hows\s+it\s+going|how\s+do\s+you\s+do|hows\s+everything|how\s+is\s+it\s+going)\b').hasMatch(normalized)) {
      return "I'm doing great, thank you for asking! I'm ready to help you explore your notes and organize your thoughts. What would you like to work on today?";
    }

    // 5. Identity / Name / Nature
    if (RegExp(r'\b(who\s+are\s+you|what\s+is\s+your\s+name|what\s+are\s+you|tell\s+me\s+about\s+yourself|introduce\s+yourself|are\s+you\s+(an\s+)?ai|are\s+you\s+a\s+bot|are\s+you\s+real|what\s+is\s+zuri|who\s+is\s+zuri)\b').hasMatch(normalized)) {
      return "I'm Zuri, your personal AI assistant and memory companion. I help you remember important ideas, organize your thoughts, find connections across your notes, and answer questions based on what you've saved. You can chat with me naturally anytime!";
    }

    // 6. Capabilities / What can you do / Help
    if (RegExp(r'\b(what\s+can\s+you\s+do|how\s+can\s+you\s+help|what\s+do\s+you\s+do|what\s+are\s+your\s+features|help\s+me|help)\b').hasMatch(normalized)) {
      return "Here is what I can do for you:\n"
          "• Answer questions based on your saved notes and memories\n"
          "• Remember conversation context across follow-up questions\n"
          "• Discover related memories and connect similar ideas\n"
          "• Summarize your weekly, monthly, or daily learnings and decisions\n"
          "• Chat with you naturally whenever you need assistance\n\n"
          "Feel free to ask me anything about your notes, or just chat!";
    }

    // 7. Greetings ("Say hello to Zuri", "hello", "hi", "hey", "good morning", etc.)
    if (RegExp(r'\b(hello|hi|hey|howdy|greetings|good\s*(morning|afternoon|evening|day)|yo|sup|whats\s*up|wassup|greet|say\s+hello|say\s+hi)\b').hasMatch(normalized)) {
      final words = normalized.split(' ');
      final hasQuestion = RegExp(r'\b(what|which|where|when|why|who\s+did|how\s+to|how\s+do|how\s+did)\b').hasMatch(normalized);
      if (!hasQuestion || words.length <= 8) {
        if (normalized.contains('morning')) {
          return "Good morning! I'm Zuri, your personal AI assistant. How can I help you today?";
        } else if (normalized.contains('afternoon')) {
          return "Good afternoon! I'm Zuri. How is your day going? Let me know if you need to recall or save anything.";
        } else if (normalized.contains('evening')) {
          return "Good evening! I'm Zuri. What would you like to review or brainstorm tonight?";
        }
        return "Hello! I'm Zuri, your personal AI assistant. How can I help you today? You can ask me anything about your notes, or share what's on your mind.";
      }
    }

    // 8. Casual acknowledgments & reactions
    if (const {'ok', 'okay', 'cool', 'great', 'awesome', 'nice', 'got it', 'sounds good', 'understood', 'haha', 'lol', 'yes', 'no'}.contains(normalized)) {
      return "Sounds good! I'm here whenever you're ready to search your notes or save a new thought.";
    }

    return null;
  }
}
