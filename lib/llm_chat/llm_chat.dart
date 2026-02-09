/// # LLM Chat Widget Library
///
/// A reusable Flutter component that wraps LLM web interfaces (Gemini, ChatGPT,
/// Claude, Copilot, Meta AI, DeepSeek) in a WebView widget with programmatic
/// message send/receive capabilities.
///
/// ## Quick Start
/// ```dart
/// import 'package:llmchatbox/llmchatbox.dart';
///
/// final controller = LlmChatController(
///   llmType: LlmType.chatGpt,
///   basePrompt: 'You are a helpful assistant.',
///   onMessageFromLlm: (message) => print('LLM said: $message'),
///   onLlmAvailabilityChanged: (available) => print('Available: $available'),
///   debug: true,
/// );
///
/// // In your widget tree:
/// LlmChatWidget(
///   controller: controller,
///   cookiePersistence: myCookiePersistence, // caller-provided implementation
/// )
///
/// // Send messages:
/// controller.sendToLlm('Hello, world!');
///
/// // Reset to reload:
/// controller.resetLlm();
///
/// // Clean up:
/// controller.dispose();
/// ```
///
/// ## Architecture
/// - [LlmType] — Enum of supported LLM providers
/// - [LlmJsProvider] — Base class for LLM-specific JavaScript snippets (with factory)
/// - [LlmChatController] — Core controller managing queue, state, and callbacks
/// - [LlmChatWidget] — The Flutter widget embedding the WebView (cross-platform via `flutter_inappwebview`)
/// - [CookiePersistence] — Abstract interface for cookie/state persistence (caller-provided)
library;

export 'llm_type.dart';
export 'llm_js_provider.dart';
export 'llm_chat_controller.dart';
export 'llm_chat_widget.dart';
export 'cookie_persistence.dart';
