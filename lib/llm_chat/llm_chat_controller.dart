import 'dart:async';
import 'dart:collection';

import 'llm_type.dart';
import 'llm_js_provider.dart';
import 'providers/default_js_snippets.dart';

/// Callback type for messages received from the LLM.
///
/// [message] is the text content extracted from the LLM's response.
typedef MessageFromLlmCallback = void Function(String message);

/// Callback type for LLM availability changes.
///
/// [available] is `true` when the LLM web interface is detected as usable
/// (signed in, no blocking popups, message input exists).
typedef LlmAvailabilityCallback = void Function(bool available);

/// Core controller managing the message queue, LLM state, and callbacks.
///
/// This controller is the primary programmatic interface for interacting with
/// an LLM web interface via the [LlmChatWidget].
///
/// ## Usage
/// ```dart
/// final controller = LlmChatController(
///   llmType: LlmType.chatGpt,
///   basePrompt: 'You are a helpful assistant. Respond concisely.',
///   onMessageFromLlm: (msg) => print('Got: $msg'),
///   onLlmAvailabilityChanged: (ok) => print('Available: $ok'),
///   debug: true,
/// );
///
/// // Send a message (queued, sent when LLM is ready):
/// controller.sendToLlm('What is 2+2?');
///
/// // Reset and reload:
/// controller.resetLlm();
///
/// // Dispose when done:
/// controller.dispose();
/// ```
///
/// ## Internal Flow
/// 1. [resetLlm] clears the queue, pushes [basePrompt], and navigates to the LLM URL.
/// 2. On page load, JavaScript checks availability via [LlmJsProvider.jsDetectAvailability].
/// 3. If available, clipboard hooks and mutation observer are installed.
/// 4. [drainSendToLlmQueue] sends the next queued message if not waiting for a response.
/// 5. When the LLM responds (clipboard intercepted), [receiveFromLlm] is called.
/// 6. [receiveFromLlm] fires [onMessageFromLlm], resets the waiting flag, and drains again.
class LlmChatController {
  /// The type of LLM to connect to. Can be changed via [switchLlm].
  LlmType llmType;

  /// The initial system/base prompt sent after every reset.
  ///
  /// This is always the first message in the queue after [resetLlm].
  String basePrompt;

  /// Callback invoked when a message is received from the LLM.
  ///
  /// This fires after the clipboard interception captures the LLM's response.
  final MessageFromLlmCallback? onMessageFromLlm;

  /// Callback invoked when LLM availability changes.
  ///
  /// Fires with `false` if blocking popups or missing input are detected.
  final LlmAvailabilityCallback? onLlmAvailabilityChanged;

  /// Whether debug logging is enabled.
  ///
  /// When `true`, copious logs are printed to the console for all internal
  /// operations: queue changes, JS execution, state transitions, etc.
  final bool debug;

  /// The JavaScript provider for this LLM type.
  late LlmJsProvider jsProvider;

  /// Internal message queue (FIFO).
  final Queue<String> _sendToLlmQueue = Queue<String>();

  /// Whether we are currently waiting for the LLM to respond.
  bool _waitingForLlmResponse = false;

  /// Whether the LLM is currently available (signed in, no popups, input exists).
  bool _llmAvailable = false;

  /// Whether the controller has been disposed.
  bool _disposed = false;

  /// Tracks the last message sent to the LLM, used to filter out echo
  /// from clipboard interception (the copy observer may copy our own input).
  String? _lastSentMessage;

  /// Callback set by the widget to trigger navigation.
  /// The widget sets this so the controller can request page loads.
  void Function(String url)? onNavigate;

  /// Callback set by the widget to execute JavaScript in the WebView.
  Future<String?> Function(String js)? onRunJavaScript;

  /// Callback set by the widget to execute JavaScript that returns a result.
  Future<String> Function(String js)? onRunJavaScriptReturningResult;

  LlmChatController({
    required this.llmType,
    this.basePrompt = '',
    this.onMessageFromLlm,
    this.onLlmAvailabilityChanged,
    this.debug = false,
  }) {
    jsProvider = LlmJsProvider.forType(llmType);
    _log('Controller created for ${llmType.displayName}');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Whether the LLM web interface is currently available and ready.
  bool get isLlmAvailable => _llmAvailable;

  /// Whether the controller is waiting for an LLM response.
  bool get isWaitingForResponse => _waitingForLlmResponse;

  /// Number of messages currently queued.
  int get queueLength => _sendToLlmQueue.length;

  /// Resets the LLM session.
  ///
  /// Optionally pass [newLlmType] to switch to a different LLM and/or
  /// [newBasePrompt] to change the base prompt. The WebView is reused —
  /// no teardown/recreation needed.
  ///
  /// This will:
  /// 1. Update [llmType] / [basePrompt] / [jsProvider] if new values given
  /// 2. Clear the send queue
  /// 3. Add [basePrompt] to the front of the queue (if non-empty)
  /// 4. Reset the waiting flag
  /// 5. Navigate the WebView to the LLM URL (triggers page reload)
  ///
  /// The page load callback (handled by the widget) will then run availability
  /// checks, install JS hooks, and begin draining the queue.
  void resetLlm({LlmType? newLlmType, String? newBasePrompt}) {
    if (newLlmType != null && newLlmType != llmType) {
      _log('resetLlm() switching from ${llmType.displayName} to ${newLlmType.displayName}');
      llmType = newLlmType;
      jsProvider = LlmJsProvider.forType(newLlmType);
    }
    if (newBasePrompt != null) {
      basePrompt = newBasePrompt;
    }

    _log('resetLlm() called for ${llmType.displayName}');
    _sendToLlmQueue.clear();
    _waitingForLlmResponse = false;
    _llmAvailable = false;
    _lastSentMessage = null;

    if (basePrompt.isNotEmpty) {
      _sendToLlmQueue.addFirst(basePrompt);
      _log('Added basePrompt to queue: "${_truncate(basePrompt)}"');
    }

    final url = llmType.url;
    _log('Navigating to $url');
    onNavigate?.call(url);
  }

  /// Enqueues a message to be sent to the LLM.
  ///
  /// If the LLM is not available, the message is silently dropped and a
  /// debug log is emitted. Otherwise, the message is added to the queue
  /// and [drainSendToLlmQueue] is called.
  ///
  /// Messages are sent one at a time; the next message is sent only after
  /// the LLM responds to the current one.
  void sendToLlm(String message) {
    if (!_llmAvailable) {
      _log('sendToLlm() called but LLM is not available, dropping message');
      return;
    }
    _log('sendToLlm() enqueuing: "${_truncate(message)}"');
    _sendToLlmQueue.add(message);
    drainSendToLlmQueue();
  }

  /// Called when the page finishes loading in the WebView.
  ///
  /// This is invoked by the widget's page-load callback. It:
  /// 1. Runs availability detection JavaScript
  /// 2. If unavailable, sets [_llmAvailable] to false and calls callback
  /// 3. If available, installs clipboard hooks and mutation observer
  /// 4. Calls [drainSendToLlmQueue] to start sending queued messages
  Future<void> onPageFinishedLoading() async {
    _log('onPageFinishedLoading() called');

    if (onRunJavaScriptReturningResult == null) {
      _log('ERROR: onRunJavaScriptReturningResult not set');
      return;
    }

    // Step 1: Check availability
    try {
      final availabilityJs = jsProvider.jsDetectAvailability();
      _log('Running availability check JS...');
      final result = await onRunJavaScriptReturningResult!(availabilityJs);
      _log('Availability result: $result');

      final available = result.replaceAll('"', '').trim() == 'available';
      _llmAvailable = available;
      onLlmAvailabilityChanged?.call(available);

      if (!available) {
        _log('LLM is UNAVAILABLE (popups or no input detected)');
        return;
      }
    } catch (e) {
      _log('Availability check FAILED: $e');
      _llmAvailable = false;
      onLlmAvailabilityChanged?.call(false);
      return;
    }

    _log('LLM is AVAILABLE');

    // Step 2: Install cross-platform bridge shim
    try {
      final bridgeJs = DefaultJsSnippets.jsInstallBridgeShim();
      _log('Installing bridge shim...');
      await onRunJavaScript!(bridgeJs);
      _log('Bridge shim installed');
    } catch (e) {
      _log('Bridge shim FAILED: $e');
    }

    // Step 3: Hook clipboard
    try {
      final clipboardJs = jsProvider.jsHookClipboard();
      _log('Installing clipboard hook...');
      await onRunJavaScript!(clipboardJs);
      _log('Clipboard hook installed');
    } catch (e) {
      _log('Clipboard hook FAILED: $e');
    }

    // Step 4: Install mutation observer for copy buttons
    try {
      final observerJs = jsProvider.jsInstallCopyMutationObserver();
      _log('Installing copy mutation observer...');
      await onRunJavaScript!(observerJs);
      _log('Copy mutation observer installed');
    } catch (e) {
      _log('Mutation observer FAILED: $e');
    }

    // Step 4: Drain the queue
    drainSendToLlmQueue();
  }

  /// Called when text is received from the LLM (via clipboard interception).
  ///
  /// This is invoked by the JavaScript bridge when intercepted clipboard text
  /// arrives. It:
  /// 1. Resets [_waitingForLlmResponse] to false
  /// 2. Fires [onMessageFromLlm] callback with the received text
  /// 3. Calls [drainSendToLlmQueue] to send the next queued message
  void receiveFromLlm(String message) {
    _log('receiveFromLlm(): "${_truncate(message)}"');

    // Debug messages from JS providers (not real LLM responses)
    if (message.startsWith('__LLMDBG__:')) {
      _log('  -> JS_DEBUG: ${message.substring(11)}');
      return;
    }

    // Filter out echo of our own sent message (clipboard may copy our input)
    if (_lastSentMessage != null && message.trim() == _lastSentMessage!.trim()) {
      _log('  -> ignoring: echo of sent message');
      return;
    }

    _lastSentMessage = null;
    _waitingForLlmResponse = false;

    // Disable copy-button clicking now that we have the response
    onRunJavaScript?.call('window.__llmReadyForResponse = false;');

    onMessageFromLlm?.call(message);
    drainSendToLlmQueue();
  }

  /// Drains the send queue, sending the next message if possible.
  ///
  /// This will NOT send if:
  /// - [_waitingForLlmResponse] is true (already waiting)
  /// - [_llmAvailable] is false
  /// - The queue is empty
  ///
  /// When a message is sent, [_waitingForLlmResponse] is set to true.
  void drainSendToLlmQueue() {
    _log('drainSendToLlmQueue(): waiting=$_waitingForLlmResponse, '
        'available=$_llmAvailable, queueLen=${_sendToLlmQueue.length}');

    if (_waitingForLlmResponse) {
      _log('  -> skipping, waiting for LLM response');
      return;
    }

    if (!_llmAvailable) {
      _log('  -> skipping, LLM not available');
      return;
    }

    if (_sendToLlmQueue.isEmpty) {
      _log('  -> queue empty, nothing to send');
      return;
    }

    final message = _sendToLlmQueue.removeFirst();
    _log('  -> sending: "${_truncate(message)}"');
    _waitingForLlmResponse = true;
    _lastSentMessage = message;

    final js = jsProvider.jsSendMessage(message);

    final runner = onRunJavaScriptReturningResult ?? onRunJavaScript;
    runner?.call(js).then((result) {
      _log('  -> message sent via JS${result != null && result.toString().isNotEmpty ? " result=$result" : ""}');
    }).catchError((e) {
      _log('  -> JS send FAILED: $e');
      _waitingForLlmResponse = false;
    });
  }

  /// Dumps relevant DOM HTML for debugging selector issues.
  ///
  /// Returns a short summary of the page: title, URL-like info, and
  /// the outer HTML of key elements (inputs, buttons, dialogs).
  Future<String> dumpDomDebug() async {
    if (onRunJavaScriptReturningResult == null) return 'No JS runner';
    try {
      final js = '''
(function() {
  var info = {};
  info.title = document.title;
  info.url = location.href;
  info.bodyClasses = document.body ? document.body.className : 'NO BODY';

  // Find all textareas
  var textareas = document.querySelectorAll('textarea');
  info.textareas = [];
  textareas.forEach(function(t) {
    info.textareas.push({
      id: t.id, name: t.name, placeholder: t.placeholder,
      ariaLabel: t.getAttribute('aria-label'),
      classes: t.className.substring(0,100)
    });
  });

  // Find all contenteditable divs
  var editables = document.querySelectorAll('[contenteditable="true"]');
  info.editables = [];
  editables.forEach(function(e) {
    info.editables.push({
      tag: e.tagName, id: e.id, role: e.getAttribute('role'),
      ariaLabel: e.getAttribute('aria-label'),
      placeholder: e.getAttribute('data-placeholder') || e.getAttribute('placeholder'),
      classes: e.className.substring(0,100)
    });
  });

  // Find all buttons with send/submit-like labels
  var buttons = document.querySelectorAll('button');
  info.sendButtons = [];
  info.nearInputBtns = [];
  buttons.forEach(function(b) {
    var lbl = (b.getAttribute('aria-label') || '') + ' ' + (b.textContent || '').substring(0,30);
    if (lbl.toLowerCase().match(/send|submit|copy|clipboard/)) {
      info.sendButtons.push({
        ariaLabel: b.getAttribute('aria-label'),
        text: (b.textContent||'').substring(0,40).trim(),
        disabled: b.disabled,
        type: b.type,
        testId: b.getAttribute('data-testid'),
        classes: b.className.substring(0,80)
      });
    }
  });
  // Find buttons near the main input
  var mainInput = document.querySelector('#userInput, #prompt-textarea, textarea[placeholder]');
  if (mainInput) {
    info.inputValue = mainInput.value ? mainInput.value.substring(0,100) : '(empty)';
    var container = mainInput.parentElement;
    for (var i = 0; i < 4 && container; i++) {
      var btns = container.querySelectorAll('button');
      btns.forEach(function(b) {
        if (b.offsetWidth > 0) {
          info.nearInputBtns.push({
            ariaLabel: b.getAttribute('aria-label'),
            type: b.type, disabled: b.disabled,
            w: b.offsetWidth, h: b.offsetHeight,
            classes: b.className.substring(0,60)
          });
        }
      });
      if (info.nearInputBtns.length > 0) break;
      container = container.parentElement;
    }
  }

  // Find dialogs/modals
  var dialogs = document.querySelectorAll('[role="dialog"], dialog[open], .modal');
  info.dialogs = [];
  dialogs.forEach(function(d) {
    var style = window.getComputedStyle(d);
    var rect = d.getBoundingClientRect();
    info.dialogs.push({
      tag: d.tagName, role: d.getAttribute('role'),
      display: style.display, visibility: style.visibility,
      w: Math.round(rect.width), h: Math.round(rect.height),
      classes: d.className.substring(0,80)
    });
  });

  // Find elements with copy-related aria-labels
  var copyEls = document.querySelectorAll('[aria-label*="opy"], [aria-label*="lipboard"], [title*="opy"]');
  info.copyElements = [];
  copyEls.forEach(function(el) {
    info.copyElements.push({
      tag: el.tagName, ariaLabel: el.getAttribute('aria-label'),
      title: el.getAttribute('title'),
      classes: el.className.substring(0,60)
    });
  });

  return JSON.stringify(info, null, 2);
})();
''';
      final result = await onRunJavaScriptReturningResult!(js);
      return result;
    } catch (e) {
      return 'DOM dump error: $e';
    }
  }

  /// Disposes of the controller, releasing resources.
  void dispose() {
    _log('dispose() called');
    _disposed = true;
    _sendToLlmQueue.clear();
  }

  // ---------------------------------------------------------------------------
  // Debug logging
  // ---------------------------------------------------------------------------

  void _log(String message) {
    if (debug && !_disposed) {
      print('[LlmChat:${llmType.displayName}] $message');
    }
  }

  String _truncate(String s, [int maxLen = 80]) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }
}
