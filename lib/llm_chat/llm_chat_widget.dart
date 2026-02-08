import 'dart:async';
import 'package:flutter/material.dart';

import 'llm_type.dart';
import 'llm_chat_controller.dart';
import 'cookie_persistence.dart';
import 'platform/platform_webview.dart';
import 'platform/platform_webview_factory.dart';

/// A Flutter widget that embeds an LLM web interface in a WebView.
///
/// This widget is **cross-platform**: it auto-selects the correct WebView
/// backend for the running platform:
/// - **Windows**: WebView2/Edge via `webview_windows`
/// - **Android/iOS/macOS/web**: `webview_flutter`
///
/// ## Parameters
///
/// - **[controller]** (required): The [LlmChatController] managing state and queue.
/// - **[cookiePersistence]** (optional): A [CookiePersistence] implementation for
///   saving/restoring cookies across sessions. When provided, cookies are loaded
///   before navigation and saved periodically.
/// - **[userAgent]** (optional): Custom User-Agent string for the WebView.
///
/// ## Example
/// ```dart
/// final controller = LlmChatController(
///   llmType: LlmType.chatGpt,
///   basePrompt: 'Hello!',
///   onMessageFromLlm: (msg) => print(msg),
///   debug: true,
/// );
///
/// @override
/// Widget build(BuildContext context) {
///   return LlmChatWidget(
///     controller: controller,
///     cookiePersistence: FileCookiePersistence(directory: myDir),
///   );
/// }
/// ```
///
/// ## Cookie Persistence
/// If [cookiePersistence] is provided, the widget will:
/// - Load cookies from persistence when the WebView is created
/// - Save cookies after each page load completes
/// - Use the LLM type name as the persistence key
///
/// ## JavaScript Bridge
/// The clipboard-hook JS sends intercepted text back to Dart. The bridge
/// call varies by platform and is handled transparently:
/// - `webview_flutter`: `LlmBridge.postMessage(text)`
/// - `webview_windows`: `window.chrome.webview.postMessage(text)`
class LlmChatWidget extends StatefulWidget {
  /// The controller managing LLM interaction state.
  final LlmChatController controller;

  /// Optional cookie persistence layer for remembering login sessions.
  final CookiePersistence? cookiePersistence;

  /// Optional custom User-Agent string.
  final String? userAgent;

  const LlmChatWidget({
    super.key,
    required this.controller,
    this.cookiePersistence,
    this.userAgent,
  });

  @override
  State<LlmChatWidget> createState() => _LlmChatWidgetState();
}

class _LlmChatWidgetState extends State<LlmChatWidget> {
  PlatformWebView? _webView;
  bool _initialized = false;
  bool _disposed = false;

  LlmChatController get _ctrl => widget.controller;

  void _log(String msg) {
    if (_ctrl.debug) {
      print('[LlmChatWidget:${_ctrl.llmType.displayName}] $msg');
    }
  }

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    _log('Initializing WebView (cross-platform)...');

    final webView = PlatformWebViewFactory.create();

    // Set up callbacks before initialize
    webView.onMessageReceived = (String message) {
      if (_disposed) return;
      _log('JS Bridge received: "${message.length > 100 ? "${message.substring(0, 100)}..." : message}"');
      _ctrl.receiveFromLlm(message);
    };

    webView.onPageFinished = (String url) {
      if (_disposed) return;
      _log('Page finished loading: $url');
      _onPageLoaded(url);
    };

    try {
      await webView.initialize();
    } catch (e) {
      _log('WebView initialization FAILED: $e');
      return;
    }

    if (_disposed) {
      _log('Widget disposed during WebView init, cleaning up');
      webView.dispose();
      return;
    }

    if (widget.userAgent != null) {
      await webView.setUserAgent(widget.userAgent!);
    }

    _webView = webView;

    // Wire up controller callbacks
    _ctrl.onNavigate = (url) {
      if (_disposed || _webView == null) return;
      _log('Controller requested navigation to: $url');
      _webView!.loadUrl(url);
    };

    _ctrl.onRunJavaScript = (js) async {
      if (_disposed || _webView == null) return null;
      _log('Running JS (${js.length} chars)');
      await _webView!.runJavaScript(js);
      return null;
    };

    _ctrl.onRunJavaScriptReturningResult = (js) async {
      if (_disposed || _webView == null) return '';
      _log('Running JS with result (${js.length} chars)');
      return await _webView!.runJavaScriptReturningResult(js);
    };

    // Load cookies if persistence is available
    if (widget.cookiePersistence != null) {
      _log('Loading cookies from persistence...');
      try {
        final cookies = await widget.cookiePersistence!
            .loadCookies(_ctrl.llmType.name);
        _log('Loaded ${cookies.length} cookies');
      } catch (e) {
        _log('Failed to load cookies: $e');
      }
    }

    if (_disposed) return;
    setState(() => _initialized = true);

    // Trigger initial reset to load the LLM page
    _ctrl.resetLlm();
  }

  Future<void> _onPageLoaded(String url) async {
    if (_disposed) return;
    _log('_onPageLoaded: $url');

    // Save cookies after page load
    if (widget.cookiePersistence != null) {
      _saveCookies();
    }

    // Delay slightly to let page JS settle
    await Future.delayed(const Duration(seconds: 2));

    // Guard: widget may have been disposed during the delay
    if (_disposed) {
      _log('Widget disposed during page load delay, skipping JS setup');
      return;
    }

    // Delegate to controller for availability check and JS setup
    await _ctrl.onPageFinishedLoading();
  }

  Future<void> _saveCookies() async {
    if (_disposed || widget.cookiePersistence == null || _webView == null) return;
    try {
      final cookieStr = await _webView!
          .runJavaScriptReturningResult('document.cookie');
      if (_disposed) return;
      final cookieMap = <String, String>{};
      final raw = cookieStr.replaceAll('"', '');
      if (raw.isNotEmpty) {
        for (final part in raw.split(';')) {
          final trimmed = part.trim();
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx > 0) {
            cookieMap[trimmed.substring(0, eqIdx)] =
                trimmed.substring(eqIdx + 1);
          }
        }
      }
      await widget.cookiePersistence!
          .saveCookies(_ctrl.llmType.name, cookieMap);
      _log('Saved ${cookieMap.length} cookies');
    } catch (e) {
      _log('Failed to save cookies: $e');
    }
  }

  @override
  void dispose() {
    _log('Widget disposing');
    _disposed = true;
    _webView?.dispose();
    _webView = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _webView == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _webView!.buildWidget();
  }
}
