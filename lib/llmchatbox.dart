/// # llmchatbox
///
/// A reusable Flutter package that wraps 6 LLM web interfaces in a WebView
/// widget with programmatic message send/receive via clipboard interception.
///
/// ## Supported LLMs
/// - Google Gemini
/// - OpenAI ChatGPT
/// - Anthropic Claude
/// - Microsoft Copilot
/// - Meta AI
/// - DeepSeek
///
/// ## Quick Start
/// ```dart
/// import 'package:llmchatbox/llmchatbox.dart';
///
/// final controller = LlmChatController(
///   llmType: LlmType.chatGpt,
///   basePrompt: 'You are a helpful assistant.',
///   onMessageFromLlm: (message) => print('LLM: $message'),
///   onLlmAvailabilityChanged: (ok) => print('Available: $ok'),
///   debug: true,
/// );
///
/// // In your widget tree:
/// LlmChatWidget(
///   controller: controller,
///   cookiePersistence: FileCookiePersistence(directory: myDir),
/// )
///
/// // Send messages programmatically:
/// controller.sendToLlm('What is 2+2?');
///
/// // Switch LLM or reset:
/// controller.resetLlm();
///
/// // Clean up:
/// controller.dispose();
/// ```
///
/// See [README.md](https://github.com/user/llmchatbox) for full documentation.
library;

export 'llm_chat/llm_type.dart';
export 'llm_chat/llm_js_provider.dart';
export 'llm_chat/llm_chat_controller.dart';
export 'llm_chat/llm_chat_widget.dart';
export 'llm_chat/cookie_persistence.dart';
export 'llm_chat/platform/platform_webview.dart';
export 'llm_chat/platform/platform_webview_factory.dart';
