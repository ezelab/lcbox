import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for Google Gemini.
///
/// Gemini uses a Quill rich-text editor. Text entry works via
/// `execCommand('selectAll')` + `execCommand('insertText')` after focus.
class GeminiJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  var dialogs = document.querySelectorAll('dialog[open], [role="dialog"], .modal-overlay');
  for (var i = 0; i < dialogs.length; i++) {
    var d = dialogs[i];
    var style = window.getComputedStyle(d);
    if (style.display !== 'none' && style.visibility !== 'hidden') {
      return 'unavailable';
    }
  }
  var selectors = [
    'rich-textarea .ql-editor',
    'rich-textarea div[contenteditable="true"]',
    'div[contenteditable="true"][aria-label*="prompt" i]',
    '.ql-editor[contenteditable="true"]',
    'div[contenteditable="true"][data-placeholder]'
  ];
  for (var i = 0; i < selectors.length; i++) {
    if (document.querySelector(selectors[i])) return 'available';
  }
  return 'unavailable';
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

  var selectors = [
    'rich-textarea .ql-editor',
    'rich-textarea div[contenteditable="true"]',
    'div[contenteditable="true"][aria-label*="prompt" i]',
    '.ql-editor[contenteditable="true"]',
    'div[contenteditable="true"][data-placeholder]'
  ];
  var input = null;
  for (var i = 0; i < selectors.length; i++) {
    input = document.querySelector(selectors[i]);
    if (input) break;
  }
  if (!input) { dbg('Gemini: No input found'); return 'no_input'; }

  input.focus();
  document.execCommand('selectAll');
  var ok = document.execCommand('insertText', false, msg);
  dbg('Gemini: execCommand ok=' + ok + ' innerText.len=' + input.innerText.length);

  setTimeout(function() {
    var btnSelectors = [
      'button.send-button',
      'button[aria-label="Send message"]',
      'button[aria-label*="Send" i]',
    ];
    for (var i = 0; i < btnSelectors.length; i++) {
      var btn = document.querySelector(btnSelectors[i]);
      if (btn && !btn.disabled) {
        dbg('Gemini: Clicking send: ' + btnSelectors[i]);
        btn.click();
        return;
      }
    }
    dbg('Gemini: No send button, trying Enter');
    input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', keyCode: 13, bubbles: true}));
  }, 500);

  return 'submitted';
})();
''';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
