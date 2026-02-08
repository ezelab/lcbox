import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for DeepSeek.
///
/// DeepSeek uses a textarea input similar to ChatGPT's layout.
class DeepSeekJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  // Check for login/blocking overlays
  var overlays = document.querySelectorAll('[role="dialog"], .modal, [class*="modal"], [class*="overlay"]');
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
  // Check for message input
  var input = document.querySelector('textarea#chat-input, textarea[placeholder*="Message" i], textarea[placeholder*="Send" i], div[contenteditable="true"][class*="input"]');
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
  var dbg = function(s) { try { window.__llmBridge('__LLMDBG__:' + s); } catch(e) { console.log('LlmChat: ' + s); } };

  var input = document.querySelector('textarea[placeholder*="Message" i], textarea[placeholder*="Send" i], textarea#chat-input, div[contenteditable="true"][role="textbox"]');
  if (!input) { dbg('DeepSeek: No input found'); return 'no_input'; }
  dbg('DeepSeek: Found input tag=' + input.tagName);

  input.focus();

  if (input.tagName === 'TEXTAREA') {
    input.value = '';
    var ok = document.execCommand('insertText', false, msg);
    dbg('DeepSeek: execCommand ok=' + ok + ' value.len=' + input.value.length);
    if (!ok || input.value.length === 0) {
      var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
      nativeSetter.call(input, msg);
      var tracker = input._valueTracker;
      if (tracker) tracker.setValue('');
      input.dispatchEvent(new Event('input', {bubbles: true}));
    }
  } else {
    document.execCommand('selectAll');
    document.execCommand('insertText', false, msg);
  }

  // Submit via Enter key (proven to work for DeepSeek)
  setTimeout(function() {
    input.focus();
    input.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
      bubbles: true, cancelable: true, composed: true
    }));
    input.dispatchEvent(new KeyboardEvent('keypress', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
    }));
    input.dispatchEvent(new KeyboardEvent('keyup', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true
    }));
    dbg('DeepSeek: Enter key dispatched');
  }, 500);

  return 'submitted';
})();
''';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
