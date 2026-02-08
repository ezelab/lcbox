import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for OpenAI ChatGPT.
///
/// ChatGPT uses a `<textarea>` or `contenteditable` div for input and
/// a specific send button with a `data-testid` attribute.
class ChatGptJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  // Check for blocking modals/overlays
  var modals = document.querySelectorAll('[role="dialog"], .modal, [data-state="open"][class*="overlay"]');
  for (var i = 0; i < modals.length; i++) {
    var m = modals[i];
    var style = window.getComputedStyle(m);
    if (style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0') {
      // Check if it's a blocking overlay (covers significant area)
      var rect = m.getBoundingClientRect();
      if (rect.width > window.innerWidth * 0.5 && rect.height > window.innerHeight * 0.3) {
        return 'unavailable';
      }
    }
  }
  // Check for prompt textarea/input
  var input = document.querySelector('#prompt-textarea, textarea[data-id="root"], div#prompt-textarea[contenteditable="true"], textarea[placeholder*="Message"], div[contenteditable="true"][data-placeholder*="Message"]');
  if (!input) return 'unavailable';
  return 'available';
})();
''';
  }

  @override
  String jsSendMessage(String message) {
    final escaped = DefaultJsSnippets.escapeJs(message);
    return '''
(function() {
  window.__llmReadyForResponse = true;
  var msg = $escaped;
  var input = document.querySelector('#prompt-textarea, textarea[data-id="root"], div#prompt-textarea[contenteditable="true"], textarea[placeholder*="Message"], div[contenteditable="true"][data-placeholder*="Message"]');
  if (!input) { console.error('LlmChat: No input found'); return; }
  input.focus();
  if (input.tagName === 'TEXTAREA') {
    var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    nativeSetter.call(input, msg);
    input.dispatchEvent(new Event('input', {bubbles: true}));
  } else {
    input.innerHTML = '<p>' + msg + '</p>';
    input.dispatchEvent(new Event('input', {bubbles: true}));
  }
  setTimeout(function() {
    var sendBtn = document.querySelector('button[data-testid="send-button"], button[aria-label="Send prompt"], form button[type="submit"], button[aria-label*="Send"]');
    if (sendBtn && !sendBtn.disabled) { sendBtn.click(); }
    else { 
      input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
    }
  }, 500);
})();
''';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
