/// Supported LLM provider types.
///
/// Each variant maps to a specific LLM web interface URL.
/// Use [llmUrl] to get the URL for a given type.
///
/// ```dart
/// final url = LlmType.chatGpt.url; // 'https://chat.openai.com/'
/// final label = LlmType.chatGpt.displayName; // 'ChatGPT'
/// ```
enum LlmType {
  /// Google Gemini (formerly Bard)
  gemini,

  /// OpenAI ChatGPT
  chatGpt,

  /// Anthropic Claude
  claude,

  /// Microsoft Copilot
  copilot,

  /// Meta AI
  metaAi,

  /// DeepSeek
  deepSeek,
}

/// Extension providing URL and display name for each [LlmType].
extension LlmTypeExtension on LlmType {
  /// The web interface URL for this LLM.
  String get url {
    switch (this) {
      case LlmType.gemini:
        return 'https://gemini.google.com/app';
      case LlmType.chatGpt:
        return 'https://chat.openai.com/';
      case LlmType.claude:
        return 'https://claude.ai/new';
      case LlmType.copilot:
        return 'https://copilot.microsoft.com/';
      case LlmType.metaAi:
        return 'https://www.meta.ai/';
      case LlmType.deepSeek:
        return 'https://chat.deepseek.com/';
    }
  }

  /// Human-readable display name for this LLM.
  String get displayName {
    switch (this) {
      case LlmType.gemini:
        return 'Gemini';
      case LlmType.chatGpt:
        return 'ChatGPT';
      case LlmType.claude:
        return 'Claude';
      case LlmType.copilot:
        return 'Copilot';
      case LlmType.metaAi:
        return 'Meta AI';
      case LlmType.deepSeek:
        return 'DeepSeek';
    }
  }
}
