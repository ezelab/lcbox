import '../llm_js_provider.dart';

/// Mixin providing default implementations of the copy mutation observer
/// and clipboard hook JavaScript that work across most LLM web interfaces.
///
/// All LLM providers can use this mixin unless they need custom behavior
/// for copy button detection or clipboard interception.
///
/// ## Cross-Platform Bridge
/// The clipboard hook uses `window.__llmBridge(text)` which is set up by the
/// controller on page load to route to the correct platform-specific bridge:
/// `window.flutter_inappwebview.callHandler('LlmBridge', text)` (flutter_inappwebview).
mixin DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsInstallCopyMutationObserver() {
    return '''
(function() {
  if (window.__llmCopyObserverInstalled) return;
  window.__llmCopyObserverInstalled = true;
  window.__llmClickedCopyBtns = new WeakSet();
  window.__llmReadyForResponse = false;

  var dbg = function(s) { try { window.__llmBridge('__LLMDBG__:CopyObs: ' + s); } catch(e) { console.log('LlmChat CopyObs: ' + s); } };

  var observer = new MutationObserver(function(mutations) {
    if (!window.__llmReadyForResponse) return;
    var clicked = 0;
    var noLabel = 0;
    var skippedPrompt = 0;
    var skippedAlready = 0;
    var totalCandidates = 0;
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeType !== 1) return;
        var candidates = node.querySelectorAll ? 
          [node, ...node.querySelectorAll('button, [role="button"], [aria-label]')] : [node];
        totalCandidates += candidates.length;
        candidates.forEach(function(el) {
          var label = (el.getAttribute('aria-label') || el.getAttribute('title') || 
                       el.getAttribute('data-tooltip') || '').toLowerCase();
          if(!label){
            if(el.innerHTML.toLowerCase().includes('path d="m6.')){
              label = 'copy';
            }
          }
          if (label.includes('copy') || label.includes('clipboard')) {
            if (label.includes('prompt')) {
              skippedPrompt++;
            } else if (window.__llmClickedCopyBtns.has(el)) {
              skippedAlready++;
            } else {
              window.__llmClickedCopyBtns.add(el);
              clicked++;
              dbg('CLICKING copy button label="' + label + '"');
              setTimeout(function() { el.click(); }, 200);
            }
          } else {
            noLabel++;
          }
        });
      });
    });
    if (clicked === 0 && totalCandidates > 0) {
      dbg('no-click: candidates=' + totalCandidates + ' noMatch=' + noLabel + ' skippedPrompt=' + skippedPrompt + ' skippedAlready=' + skippedAlready);
    }
  });
  observer.observe(document.body, {childList: true, subtree: true});
  console.log('LlmChat: Copy mutation observer installed');
})();
''';
  }

  /// Base clipboard hook JS. Exposed as static so provider overrides can
  /// include the standard hooks and add extra logic on top.
  static String baseJsHookClipboard() {
    return '''
(function() {
  if (window.__llmClipboardHooked) return;
  window.__llmClipboardHooked = true;

  try {
    var origWriteText = navigator.clipboard.writeText.bind(navigator.clipboard);
    navigator.clipboard.writeText = function(text) {
      try { window.__llmBridge(text); } catch(e) {}
      try { return origWriteText(text).catch(function() { return undefined; }); } catch(e) { return Promise.resolve(); }
    };
  } catch(e) {
    console.log('LlmChat: Could not hook clipboard.writeText:', e);
  }

  try {
    var origWrite = navigator.clipboard.write.bind(navigator.clipboard);
    navigator.clipboard.write = function(data) {
      try {
        if (data && data.length > 0) {
          data[0].getType('text/plain').then(function(blob) {
            blob.text().then(function(text) {
              try { window.__llmBridge(text); } catch(e) {}
            });
          }).catch(function(e) {});
        }
      } catch(e) {}
      try { return origWrite(data).catch(function() { return undefined; }); } catch(e) { return Promise.resolve(); }
    };
  } catch(e) {
    console.log('LlmChat: Could not hook clipboard.write:', e);
  }

  console.log('LlmChat: Clipboard hooks installed');
})();
''';
  }

  @override
  String jsHookClipboard() {
    return baseJsHookClipboard();
  }

  /// Returns JavaScript that installs the cross-platform bridge shim.
  ///
  /// This must be run BEFORE [jsHookClipboard]. It sets up
  /// `window.__llmBridge(text)` to route messages to the Dart handler
  /// registered by `flutter_inappwebview`.
  static String jsInstallBridgeShim() {
    return '''
(function() {
  if (window.__llmBridge) return;
  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
    window.__llmBridge = function(text) { window.flutter_inappwebview.callHandler('LlmBridge', text); };
    console.log('LlmChat: Bridge shim installed (flutter_inappwebview)');
  } else {
    window.__llmBridge = function(text) { console.warn('LlmChat: No bridge available, message lost:', text.substring(0,100)); };
    console.warn('LlmChat: No bridge found, using fallback');
  }
})();
''';
  }

  /// Escapes a Dart string for safe embedding in a JavaScript string literal.
  static String escapeJs(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    return "'$escaped'";
  }
}
