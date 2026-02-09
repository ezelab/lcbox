import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'llm_type.dart';
import 'llm_chat_controller.dart';
import 'cookie_persistence.dart';

/// A Flutter widget that embeds an LLM web interface in a WebView.
///
/// Uses `flutter_inappwebview` for cross-platform WebView support
/// (WebView2 on Windows, native WebView on Android/iOS/macOS).
///
/// ## Parameters
///
/// - **[controller]** (required): The [LlmChatController] managing state and queue.
/// - **[cookiePersistence]** (optional): A [CookiePersistence] implementation for
///   saving/restoring cookies across sessions. When provided, cookies are loaded
///   before navigation and saved periodically.
/// - **[userAgent]** (optional): Custom User-Agent string for the WebView.
/// - **[webViewEnvironment]** (optional): A [WebViewEnvironment] for sharing a
///   persistent browser profile (cookies, cache) with other WebViews. If not
///   provided, the default environment is used.
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
/// A JavaScript handler named `LlmBridge` is registered on the WebView.
/// The clipboard-hook JS sends intercepted text back to Dart via
/// `window.flutter_inappwebview.callHandler('LlmBridge', text)`.
class LlmChatWidget extends StatefulWidget {
  /// The controller managing LLM interaction state.
  final LlmChatController controller;

  /// Optional cookie persistence layer for remembering login sessions.
  final CookiePersistence? cookiePersistence;

  /// Optional custom User-Agent string.
  final String? userAgent;

  /// Optional [WebViewEnvironment] for sharing a persistent browser profile.
  /// On Windows, this shares the WebView2 user data folder (cookies, cache)
  /// with other WebViews in the calling app. If not provided, the default
  /// environment is used.
  final WebViewEnvironment? webViewEnvironment;

  const LlmChatWidget({
    super.key,
    required this.controller,
    this.cookiePersistence,
    this.userAgent,
    this.webViewEnvironment,
  });

  @override
  State<LlmChatWidget> createState() => _LlmChatWidgetState();
}

class _LlmChatWidgetState extends State<LlmChatWidget> {
  InAppWebViewController? _controller;
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
    _log('Initializing WebView...');

    // Wire up controller callbacks
    _ctrl.onNavigate = (url) {
      if (_disposed || _controller == null) return;
      _log('Controller requested navigation to: $url');
      _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    };

    _ctrl.onRunJavaScript = (js) async {
      if (_disposed || _controller == null) return null;
      _log('Running JS (${js.length} chars)');
      await _controller!.evaluateJavascript(source: js);
      return null;
    };

    _ctrl.onRunJavaScriptReturningResult = (js) async {
      if (_disposed || _controller == null) return '';
      _log('Running JS with result (${js.length} chars)');
      final result = await _controller!.evaluateJavascript(source: js);
      return result?.toString() ?? '';
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
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;

    // Register JS → Dart bridge handler
    controller.addJavaScriptHandler(
      handlerName: 'LlmBridge',
      callback: (args) {
        if (_disposed || args.isEmpty) return;
        final text = args[0]?.toString() ?? '';
        if (text.isNotEmpty) {
          _log('JS Bridge received: "${text.length > 100 ? "${text.substring(0, 100)}..." : text}"');
          _ctrl.receiveFromLlm(text);
        }
      },
    );

    // Trigger initial reset to load the LLM page
    _ctrl.resetLlm();
  }

  Future<void> _onPageLoaded(String url) async {
    if (_disposed) return;
    _log('Page finished loading: $url');

    // Save cookies after page load
    if (widget.cookiePersistence != null) {
      _saveCookies();
    }

    // Delay slightly to let page JS settle
    await Future.delayed(const Duration(seconds: 2));

    if (_disposed) {
      _log('Widget disposed during page load delay, skipping JS setup');
      return;
    }

    // Delegate to controller for availability check and JS setup
    await _ctrl.onPageFinishedLoading();
  }

  Future<void> _saveCookies() async {
    if (_disposed || widget.cookiePersistence == null || _controller == null) {
      return;
    }
    try {
      final result = await _controller!
          .evaluateJavascript(source: 'document.cookie');
      if (_disposed) return;
      final cookieStr = result?.toString() ?? '';
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
    if (_disposed) {
      super.dispose();
      return;
    }
    _log('Widget disposing');
    _disposed = true;
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      userAgent: widget.userAgent ?? '',
      allowUniversalAccessFromFileURLs: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    );

    return InAppWebView(
      webViewEnvironment: widget.webViewEnvironment,
      initialSettings: settings,
      onWebViewCreated: _onWebViewCreated,
      onLoadStop: (controller, url) {
        if (_disposed) return;
        _onPageLoaded(url?.toString() ?? '');
      },
    );
  }
}
