import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for Meta AI.
///
/// Meta AI uses a Lexical contenteditable editor. Text entry works via
/// `execCommand('selectAll')` + `execCommand('insertText')` after focus.
class MetaAiJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  // Check for blocking modals/overlays
  var overlays = document.querySelectorAll('[role="dialog"], .modal, [class*="overlay"], [class*="modal"]');
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
  // Check for input
  var input = document.querySelector('div[contenteditable="true"][role="textbox"], textarea[placeholder*="Ask" i], textarea[placeholder*="message" i]');
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

  var input = document.querySelector('[aria-label="Ask anything..."]');
  if (!input) { dbg('MetaAI: No input found'); return 'no_input'; }

  input=input.parentNode;
  input.click(); 
  input.focus();

  dbg('MetaAI: focus clicked, trying execCommand');
  document.execCommand('selectAll');
  var ok = document.execCommand('insertText', false, msg);
  dbg('MetaAI: execCommand ok=' + ok + ' innerText.len=' + input.innerText.length);

  setTimeout(function() {
    var allBtns = document.querySelectorAll('button, [role="button"]');
    for (var i = 0; i < allBtns.length; i++) {
      var lbl = (allBtns[i].getAttribute('aria-label') || '').toLowerCase();
      if (lbl.includes('send') && allBtns[i].offsetWidth > 0) {
        dbg('MetaAI: Clicking send');
        allBtns[i].click();
        return;
      }
    }
    dbg('MetaAI: No send button found, trying Enter');
    input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', keyCode: 13, bubbles: true}));
  }, 500);

  return 'submitted';
})();
''';
  }

  /// Override clipboard hook to also listen for the 'copy' DOM event.
  /// Meta AI may use `document.execCommand('copy')` which bypasses
  /// `navigator.clipboard.writeText`, but fires a 'copy' event whose
  /// selection text we can capture.
  @override
  String jsHookClipboard() {
    // Get the standard clipboard hooks from the mixin first
    final base = DefaultJsSnippets.baseJsHookClipboard();
    return '''
$base
(function() {
  if (window.__llmCopyEventHooked) return;
  window.__llmCopyEventHooked = true;
  document.addEventListener('copy', function(event) {
    event.preventDefault();
    try { window.__llmBridge('__LLMDBG__:MetaAI copy event started'); } catch(e) {}
    try {
      var text = document.getSelection().toString();
      if (text && text.trim().length > 0) {
        try { window.__llmBridge('__LLMDBG__:MetaAI copy event, len=' + text.length); } catch(e) {}
        try { window.__llmBridge(text); } catch(e) {}
      }
    } catch(e) {}
  });
  console.log('LlmChat: MetaAI copy event listener installed');
})();
''';
  }

  // jsInstallCopyMutationObserver provided by DefaultJsSnippets mixin
}
