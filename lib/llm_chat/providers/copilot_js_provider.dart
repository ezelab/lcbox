import '../llm_js_provider.dart';
import 'default_js_snippets.dart';

/// JavaScript provider for Microsoft Copilot.
///
/// Copilot uses a specific textarea/input with shadow DOM elements.
class CopilotJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() {
    return '''
(function() {
  // Check for blocking modals
  var dialogs = document.querySelectorAll('[role="dialog"], .modal, [class*="overlay"]');
  for (var i = 0; i < dialogs.length; i++) {
    var d = dialogs[i];
    var style = window.getComputedStyle(d);
    if (style.display !== 'none' && style.visibility !== 'hidden') {
      var rect = d.getBoundingClientRect();
      if (rect.width > window.innerWidth * 0.4 && rect.height > window.innerHeight * 0.3) {
        return 'unavailable';
      }
    }
  }
  // Check for input area - Copilot uses #userInput textarea
  var input = document.querySelector('#userInput, textarea#searchbox, textarea[name="searchbox"], textarea[placeholder*="message" i], textarea[placeholder*="ask" i], textarea[aria-label*="chat" i]');
  if (!input) {
    var cib = document.querySelector('cib-serp');
    if (cib && cib.shadowRoot) {
      var actionBar = cib.shadowRoot.querySelector('cib-action-bar');
      if (actionBar && actionBar.shadowRoot) {
        input = actionBar.shadowRoot.querySelector('textarea');
      }
    }
  }
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
  var input = document.querySelector('#userInput, textarea#searchbox, textarea[placeholder*="message" i]');
  if (!input) return JSON.stringify({error: 'no_input'});
  input.focus();

  var strategy = 'none';

  // Strategy 1: execCommand('insertText') fires trusted InputEvent
  input.select();
  var execOk = document.execCommand('insertText', false, msg);
  if (execOk && input.value.length > 0) {
    strategy = 'execCommand';
  }

  // Always also do: reset _valueTracker + fire InputEvent (belt and suspenders)
  var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
  if (input.value !== msg) {
    nativeSetter.call(input, msg);
    strategy = 'nativeSetter';
  }
  var tracker = input._valueTracker;
  if (tracker) tracker.setValue('');
  input.dispatchEvent(new InputEvent('input', {
    bubbles: true, cancelable: false, inputType: 'insertText', data: msg
  }));

  // Also call React onChange directly
  var propsKey = Object.keys(input).find(function(k) { return k.startsWith('__reactProps\$'); });
  if (propsKey && input[propsKey] && input[propsKey].onChange) {
    try { input[propsKey].onChange({target: input, currentTarget: input}); strategy += '+onChange'; } catch(e) {}
  }

  var valLen = input.value.length;

  // Wait 800ms then try to submit
  setTimeout(function() {
    var curVal = input.value.length;
    try { window.__llmBridge('__LLMDBG__:pre_submit_val=' + curVal + '_url=' + location.href.substring(0,60)); } catch(e) {}

    // Find submit button
    var submitBtn = document.querySelector('button[aria-label="Submit message"], button[title="Submit message"]');
    if (!submitBtn || submitBtn.disabled) {
      // Search broader
      var allBtns = document.querySelectorAll('button');
      for (var i = 0; i < allBtns.length; i++) {
        var b = allBtns[i];
        if (b.offsetWidth <= 0 || b.disabled) continue;
        var lbl = (b.getAttribute('aria-label') || '').toLowerCase();
        if (lbl.includes('submit') || lbl.includes('send')) {
          submitBtn = b;
          break;
        }
      }
    }

    if (submitBtn && !submitBtn.disabled) {
      try { window.__llmBridge('__LLMDBG__:found_btn_' + submitBtn.getAttribute('aria-label')); } catch(e) {}

      // Try button's React onClick directly
      var btnPropsKey = Object.keys(submitBtn).find(function(k) { return k.startsWith('__reactProps\$'); });
      if (btnPropsKey && submitBtn[btnPropsKey] && submitBtn[btnPropsKey].onClick) {
        try {
          submitBtn[btnPropsKey].onClick({
            target: submitBtn, currentTarget: submitBtn,
            preventDefault: function(){}, stopPropagation: function(){},
            nativeEvent: new MouseEvent('click', {bubbles: true})
          });
          try { window.__llmBridge('__LLMDBG__:react_onClick_called'); } catch(e) {}
        } catch(e) {
          try { window.__llmBridge('__LLMDBG__:react_onClick_error=' + e.message); } catch(e2) {}
        }
      }

      // Also do DOM click
      submitBtn.click();
    } else {
      try { window.__llmBridge('__LLMDBG__:no_submit_btn'); } catch(e) {}
    }

    // Check URL after 3 seconds to see if submit worked
    setTimeout(function() {
      try { window.__llmBridge('__LLMDBG__:post_submit_url=' + location.href.substring(0,80) + '_val=' + input.value.length); } catch(e) {}
    }, 3000);

    // Also start watching for copy buttons
    var copyPoll = setInterval(function() {
      var copyBtns = document.querySelectorAll('button[aria-label*="opy"], button[title*="opy"], [data-tooltip*="opy"]');
      for (var k = 0; k < copyBtns.length; k++) {
        if (!window.__llmClickedCopyBtns.has(copyBtns[k]) && copyBtns[k].offsetWidth > 0) {
          window.__llmClickedCopyBtns.add(copyBtns[k]);
          try { window.__llmBridge('__LLMDBG__:clicking_copy_' + (copyBtns[k].getAttribute('aria-label')||'?')); } catch(e) {}
          copyBtns[k].click();
          clearInterval(copyPoll);
          return;
        }
      }
    }, 1000);
    setTimeout(function() { clearInterval(copyPoll); }, 55000);

    // Also start watching for response text directly from DOM
    // Copilot may not have copy buttons - extract response text instead
    var lastResponseText = '';
    var responseStable = 0;
    var responsePoll = setInterval(function() {
      // Find response text - look for elements after "You said"
      var mainEl = document.querySelector('main') || document.body;
      var fullText = (mainEl.innerText || '').trim();
      // Response comes after the last "You said..." section
      var parts = fullText.split(/You said/i);
      var responseCandidate = '';
      if (parts.length > 1) {
        // Last part after all "You said" sections, minus input area
        var tail = parts[parts.length - 1].trim();
        // Remove known UI elements from tail
        tail = tail.replace(/Message Copilot.*/s, '').replace(/Smart\$/m, '').trim();
        // Remove our sent message if it appears at the start
        if (tail.indexOf(msg.substring(0, 30)) === 0) {
          tail = tail.substring(msg.length).trim();
        }
        responseCandidate = tail;
      }

      if (responseCandidate.length > 0 && responseCandidate === lastResponseText) {
        responseStable++;
        if (responseStable >= 3) {
          clearInterval(responsePoll);
          clearInterval(copyPoll);
          try { window.__llmBridge(responseCandidate); } catch(e) {}
          return;
        }
      } else if (responseCandidate.length > 0) {
        responseStable = 0;
      }
      lastResponseText = responseCandidate;
    }, 2000);
    setTimeout(function() { clearInterval(responsePoll); }, 55000);
  }, 800);

  return JSON.stringify({strategy: strategy, valueLen: valLen});
})();
''';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
