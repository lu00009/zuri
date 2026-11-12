class ConversationalIntent {
  /// Detects whether a query is purely conversational (greetings, identity, capabilities, gratitude, farewells, feedback)
  /// rather than personal memory-search.
  /// Returns a friendly natural response if conversational, or `null` to trigger note retrieval.
  static String? detect(String query) {
    final clean = query.trim().toLowerCase();
    // Strip emojis and punctuation for clean token matching
    final normalized = clean
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return "Hey there! How can I help you today?";
    }

    final words = normalized.split(' ');
    final numWords = words.length;

    // If query has explicit memory-seeking keywords, it should search notes
    final memoryPattern = RegExp(
      r'\b(save|saved|my\s+notes?|notes?\s+about|notes?\s+on|did\s+i\s+save|what\s+did\s+i|what\s+do\s+i\s+have|my\s+projects?|my\s+ideas?|my\s+learnings?|my\s+meetings?|remind\s+me|search\s+for|find\s+notes?|look\s+up|what\s+were\s+my|check\s+my\s+notes?|in\s+my\s+notes?|from\s+my\s+notes?)\b',
    );
    final isAboutAi = RegExp(r'\b(who\s+are\s+you|what\s+can\s+you\s+do|who\s+made\s+you|are\s+you)\b').hasMatch(normalized);
    if (!isAboutAi && memoryPattern.hasMatch(normalized)) {
      return null;
    }

    // 0. Emotional expressions, corrections, and criticisms
    if (RegExp(r'\b(liar|lying|you\s+lie|you\s+are\s+a\s+liar|youre\s+a\s+liar|fake)\b').hasMatch(normalized)) {
      return "I'm sorry if I gave you an inaccurate or confusing response! I only aim to help you recall what you've saved. What can I look up or clarify for you?";
    }
    if (RegExp(r'\b(wrong|incorrect|not\s+true|thats\s+wrong|you\s+are\s+wrong|youre\s+wrong)\b').hasMatch(normalized)) {
      return "My apologies for the confusion! Let me know what information was incorrect or what you'd like me to look up in your notes.";
    }

    // 1. Reactions, interjections, and conversational acknowledgments
    // e.g., 'oh', 'ohh', 'ohhh', 'ooh', 'ah', 'ahh', 'aha', 'i see', 'got it', 'makes sense'
    if (const {'oh', 'ohh', 'ohhh', 'ooh', 'ah', 'ahh', 'aha', 'i see', 'got it', 'makes sense', 'understood', 'alright', 'all right'}.contains(normalized)) {
      return "Got it! Let me know if you want to explore more or jot down a new thought.";
    }

    // e.g., 'cool', 'nice', 'sweet', 'awesome', 'great', 'wonderful', 'perfect', 'sounds good'
    if (const {'cool', 'nice', 'sweet', 'awesome', 'great', 'wonderful', 'perfect', 'sounds good', 'dope', 'neat'}.contains(normalized)) {
      return "Glad to hear! What else is on your mind?";
    }

    // e.g., 'ok', 'okay', 'k', 'kk'
    if (const {'ok', 'okay', 'k', 'kk', 'okie', 'okies', 'alrighty'}.contains(normalized)) {
      return "Sounds good! I'm right here whenever you need me.";
    }

    // e.g., 'wow', 'whoa', 'really', 'seriously', 'for real', 'no way'
    if (const {'wow', 'whoa', 'really', 'seriously', 'for real', 'no way'}.contains(normalized)) {
      return "Yep! Let me know if you'd like to look deeper into anything.";
    }

    // e.g., 'haha', 'hahaha', 'hehe', 'lol', 'lmao', 'rofl'
    if (RegExp(r'\b(ha(ha)+|he(he)+|lol|lmao|rofl)\b').hasMatch(normalized)) {
      return "😄 Always happy to chat! What's next on your agenda?";
    }

    // e.g., 'hm', 'hmm', 'hmmm', 'um', 'umm', 'uh', 'idk', 'maybe'
    if (const {'hm', 'hmm', 'hmmm', 'um', 'umm', 'uh', 'idk', 'maybe', 'not sure'}.contains(normalized)) {
      return "Take your time! Anything specific you're trying to remember or brainstorm?";
    }

    // e.g., 'yeah', 'yep', 'yup', 'yes', 'sure', 'definitely', 'absolutely'
    if (const {'yeah', 'yea', 'yep', 'yup', 'yes', 'sure', 'definitely', 'absolutely'}.contains(normalized)) {
      return "Awesome! How can I help next?";
    }

    // e.g., 'nah', 'nope', 'no', 'nothing', 'not really'
    if (const {'nah', 'nope', 'no', 'nothing', 'not really', 'nevermind', 'never mind'}.contains(normalized)) {
      return "No problem at all! I'm here whenever you need to check your notes or organize your thoughts.";
    }

    // 2. Jokes and fun
    if (RegExp(r'\b(tell\s+me\s+a\s+joke|make\s+me\s+laugh|say\s+something\s+funny)\b').hasMatch(normalized)) {
      return "Why do programmers prefer dark mode? Because light attracts bugs! 😄 What would you like to explore next?";
    }

    // 3. How are you / check-ins (including shorthands like 'how is u', 'how r u', 'hru', 'wyd', 'wbu', 'what s up', 'sup')
    if (RegExp(
      r'\b(how\s*(are|is|r)\s*(you|u|ya|things|everything)|hru|how\s*u\s*(doin|doing)|hows\s*(it\s*going|everything|your\s*day)|how\s*is\s*it\s*going|whats?\s*(s\s*)?(up|new|good)|sup|wyd|wbu)\b',
    ).hasMatch(normalized)) {
      return "I'm doing great, thank you for asking! 😊 How are you doing today? We can chat, brainstorm, or explore your saved notes.";
    }

    // 4. User feelings and states (e.g. 'i am good', 'doing well', 'i'm tired', 'bored')
    if (RegExp(r'\b(i\s*am\s*(good|fine|well|great|okay|alright|ok)|doing\s*well|not\s*bad|all\s*good|pretty\s*good)\b').hasMatch(normalized)) {
      return "Glad to hear that! What would you like to work on or review today?";
    }
    if (RegExp(r'\b(i\s*am\s*(tired|exhausted|sleepy|bored|busy|stressed)|feeling\s*(tired|down|sad|exhausted|bored))\b').hasMatch(normalized)) {
      return "I hear you—take it easy! Whenever you feel like reviewing your notes or brain-dumping some thoughts, I'll be right here.";
    }

    // 5. Identity & About Zuri
    if (RegExp(r'\b(who\s+are\s+you|what\s+is\s+your\s+name|what\s+are\s+you|tell\s+me\s+about\s+yourself|introduce\s+yourself|who\s+made\s+you|who\s+created\s+you|are\s+you\s+(an\s+)?ai|are\s+you\s+(a\s+)?human|what\s+is\s+zuri|who\s+is\s+zuri|where\s+are\s+you\s+from|can\s+you\s+talk)\b').hasMatch(normalized)) {
      return "I'm Zuri, your personal AI assistant and memory companion! I help you remember ideas, organize notes, connect related thoughts, and chat with you naturally anytime.";
    }

    // 6. Capabilities & Help
    if (RegExp(r'\b(what\s+can\s+you\s+do|how\s+can\s+you\s+help|what\s+do\s+you\s+do|what\s+are\s+your\s+features|what\s+can\s+i\s+do(\s+here)?|how\s+(does\s+this|to\s+use\s+this)\s*work|help\s+me|help)\b').hasMatch(normalized)) {
      return "Here is what I can do for you:\n"
          "• Answer questions based on your saved notes and memories\n"
          "• Remember conversation context across follow-up questions\n"
          "• Connect related ideas across your notebooks\n"
          "• Chat with you naturally and keep your thoughts organized\n\n"
          "Feel free to ask me anything about your notes, or just chat!";
    }

    // 6b. Conversational prompts and questions
    if (RegExp(r'\b(tell\s+me\s+more|go\s+on|continue|elaborate)\b').hasMatch(normalized)) {
      return "I'd love to tell you more! Could you specify what topic, note, or idea you'd like to dive into?";
    }
    if (RegExp(r'\b(can\s+i\s+ask|i\s+have\s+a\s+question|got\s+a\s+question|quick\s+question)\b').hasMatch(normalized)) {
      return "Of course! Ask away—I'm listening and ready to help.";
    }
    if (RegExp(r'\b(tell\s+me\s+a\s+fact|interesting\s+fact|random\s+fact)\b').hasMatch(normalized)) {
      return "Did you know that taking handwritten or structured digital notes improves concept retention by over 30%? What would you like to explore next?";
    }
    if (RegExp(r'\b(nice\s+to\s+meet\s+you|pleased\s+to\s+meet\s+you|good\s+to\s+see\s+you)\b').hasMatch(normalized)) {
      return "Wonderful to connect with you too! What can I help you work on or remember today?";
    }

    // 7. Greetings (e.g. 'hi', 'hello', 'hey', 'good morning', 'yo', 'sup')
    if (RegExp(r'\b(hello|hi|hey|heyy|heyyy|howdy|greetings|good\s*(morning|afternoon|evening|day)|yo|greet|say\s+hello|say\s+hi)\b').hasMatch(normalized)) {
      final hasQuestion = RegExp(r'\b(what|which|where|when|why|who\s+did|how\s+to|how\s+do|how\s+did)\b').hasMatch(normalized);
      if (!hasQuestion || numWords <= 8) {
        if (normalized.contains('morning')) {
          return "Good morning! How can I help you today?";
        } else if (normalized.contains('afternoon')) {
          return "Good afternoon! How is your day going? Let me know if you need to recall or save anything.";
        } else if (normalized.contains('evening')) {
          return "Good evening! What would you like to review or brainstorm tonight?";
        }
        return "Hello! I'm Zuri, your personal AI assistant. How can I help you today? You can ask me anything about your notes, or share what's on your mind.";
      }
    }

    // 8. Farewells
    if (RegExp(r'\b(goodbye|bye|bye\s*bye|see\s*(you|ya|u)|farewell|talk\s*to\s*you\s*later|good\s*night|cya|catch\s*ya)\b').hasMatch(normalized) &&
        !RegExp(r'\b(what|why|which|how|where|when)\b').hasMatch(normalized)) {
      if (normalized.contains('night')) {
        return "Good night! Rest well, and I'll be right here whenever you're ready to pick up your notes again.";
      }
      return "Goodbye! Have a great day ahead. Whenever you have a new thought or question, I'll be right here.";
    }

    // 9. Thank you / Gratitude
    if (RegExp(r'\b(thank\s*you|thanks|thank\s+you\s+so\s+much|thanks\s+a\s+lot|appreciate\s+it|thx|ty)\b').hasMatch(normalized) &&
        !RegExp(r'\b(what|why|which|how|where|when)\b').hasMatch(normalized)) {
      return "You're very welcome! If there's anything else you'd like to check or remember, just let me know.";
    }

    // 10. Short conversational statements (1 to 2 words that aren't specific technical nouns)
    if (numWords <= 2 && !RegExp(r'\b(note|save|code|pass|key|email|task|todo|project|date|plan|meet|buy|call)\b').hasMatch(normalized)) {
      return "I'm listening! Feel free to ask me anything about your notes, or share what you'd like to talk about.";
    }

    return null;
  }
}
