import 'llm_type.dart';
import 'providers/gemini_js_provider.dart';
import 'providers/chatgpt_js_provider.dart';
import 'providers/claude_js_provider.dart';
import 'providers/copilot_js_provider.dart';
import 'providers/meta_ai_js_provider.dart';
import 'providers/deepseek_js_provider.dart';

/// Base class providing LLM-specific JavaScript snippets for WebView interaction.
///
/// Each LLM web interface has different DOM structures. This abstraction provides
/// four JavaScript snippet methods that are injected into the WebView at various
/// lifecycle points. Override the base class for LLM-specific DOM selectors.
///
/// ## JavaScript Snippets
///
/// 1. **[jsDetectAvailability]** — Checks if the LLM is available (signed in,
///    no blocking popups, message input exists). Returns JS that evaluates to
///    `'available'` or `'unavailable'`.
///
/// 2. **[jsSendMessage]** — Sends a message to the LLM by programmatically
///    typing into the input field and clicking send. Takes a `message` parameter.
///
/// 3. **[jsInstallCopyMutationObserver]** — Installs a MutationObserver that
///    watches for new "copy" or "clipboard" buttons (by aria-label, tooltip, or
///    alt text) and auto-clicks them to trigger clipboard write.
///
/// 4. **[jsHookClipboard]** — Overrides `navigator.clipboard.writeText` and
///    `navigator.clipboard.write` to intercept copied text and send it to Dart
///    via `LlmBridge.receiveFromLlm(text)` JavaScript channel.
///
/// ## Factory
///
/// Use [LlmJsProvider.forType] to get the correct provider for a given [LlmType]:
/// ```dart
/// final provider = LlmJsProvider.forType(LlmType.chatGpt);
/// final js = provider.jsDetectAvailability();
/// ```
abstract class LlmJsProvider {
  /// Factory method returning the correct provider for the given [llmType].
  ///
  /// Each LLM type has a dedicated subclass with DOM-specific selectors.
  factory LlmJsProvider.forType(LlmType llmType) {
    switch (llmType) {
      case LlmType.gemini:
        return GeminiJsProvider();
      case LlmType.chatGpt:
        return ChatGptJsProvider();
      case LlmType.claude:
        return ClaudeJsProvider();
      case LlmType.copilot:
        return CopilotJsProvider();
      case LlmType.metaAi:
        return MetaAiJsProvider();
      case LlmType.deepSeek:
        return DeepSeekJsProvider();
    }
  }

  /// Returns JavaScript that checks if the LLM interface is available.
  ///
  /// The JS should:
  /// - Check for blocking popups/overlays/modals that cover the page
  /// - Check that a message input textarea/contenteditable exists
  /// - Return the string `'available'` or `'unavailable'`
  ///
  /// Called after page load completes.
  String jsDetectAvailability();

  /// Returns JavaScript that sends [message] to the LLM.
  ///
  /// The JS should:
  /// - Find the message input element (textarea, contenteditable, etc.)
  /// - Set its value/textContent to [message]
  /// - Dispatch appropriate input events so the UI recognizes the text
  /// - Find and click the send/submit button
  ///
  /// The [message] is pre-escaped for embedding in JS strings.
  String jsSendMessage(String message);

  /// Returns JavaScript that installs a MutationObserver for copy buttons.
  ///
  /// The observer should:
  /// - Watch the document body for added nodes
  /// - Look for buttons/elements with aria-label, title, or tooltip containing
  ///   "copy" or "clipboard" (case-insensitive)
  /// - Auto-click newly appearing copy buttons to trigger clipboard write
  /// - Track already-clicked buttons to avoid re-clicking
  String jsInstallCopyMutationObserver();

  /// Returns JavaScript that hooks `navigator.clipboard.writeText` and
  /// `navigator.clipboard.write`.
  ///
  /// The hook should:
  /// - Save references to the original clipboard methods
  /// - Override them to intercept the text being written
  /// - Call `LlmBridge.postMessage(text)` to send the text to Dart
  /// - Optionally still call the original method so the UI doesn't break
  String jsHookClipboard();

  /// Helper: escapes a Dart string for safe embedding in a JS string literal.
  static String escapeForJs(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
