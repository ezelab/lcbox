import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for Anthropic Claude.
///
/// Claude uses a textarea as primary input plus a ProseMirror/tiptap div.
class ClaudeJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  var overlays = document.querySelectorAll('[role="dialog"], .modal, [class*="overlay"][class*="blocking"]');
  for (var i = 0; i < overlays.length; i++) {
    var o = overlays[i];
    var style = window.getComputedStyle(o);
    if (style.display !== 'none' && style.visibility !== 'hidden') {
      var rect = o.getBoundingClientRect();
      if (rect.width > window.innerWidth * 0.4 && rect.height > window.innerHeight * 0.3) {
        return 'unavailable';
      }
    }
  }
  var input = document.querySelector('textarea[aria-label*="prompt" i], textarea[placeholder*="help" i], div[contenteditable="true"].ProseMirror, div[contenteditable="true"].tiptap');
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

  // Strategy 1: ProseMirror/tiptap contenteditable (primary input for Claude)
  var pm = document.querySelector('div.tiptap.ProseMirror[contenteditable="true"], div[contenteditable="true"][role="textbox"]');
  if (pm) {
    console.log('LlmChat: Claude - using ProseMirror input');
    pm.focus();
    // Select all + insertText to work with ProseMirror's command handling
    var range = document.createRange();
    range.selectNodeContents(pm);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    document.execCommand('selectAll', false);
    document.execCommand('insertText', false, msg);
  } else {
    // Strategy 2: Fallback to textarea with React _valueTracker reset
    var input = document.querySelector('textarea[aria-label*="prompt" i], textarea[placeholder*="help" i]');
    if (!input) { console.error('LlmChat: Claude - No input found'); return; }
    console.log('LlmChat: Claude - using textarea fallback');
    input.focus();
    var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    nativeSetter.call(input, msg);
    var tracker = input._valueTracker;
    if (tracker) tracker.setValue('');
    input.dispatchEvent(new Event('input', {bubbles: true}));
    input.dispatchEvent(new Event('change', {bubbles: true}));
  }

  setTimeout(function() {
    var btns = document.querySelectorAll('button[aria-label*="Send" i]');
    var sendBtn = null;
    for (var i = 0; i < btns.length; i++) {
      var lbl = btns[i].getAttribute('aria-label') || '';
      if (lbl.toLowerCase().includes('send') && !btns[i].disabled) {
        sendBtn = btns[i];
        break;
      }
    }
    if (sendBtn) {
      console.log('LlmChat: Claude - clicking send button:', sendBtn.getAttribute('aria-label'));
      sendBtn.click();
    } else {
      // Try Enter key on the focused element
      console.log('LlmChat: Claude - no enabled send btn found, trying Enter');
      var active = document.activeElement;
      if (active) {
        active.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      }
    }
  }, 800);
})();
''';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
