import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

import 'platform_webview.dart';

/// Windows implementation of [PlatformWebView] using `webview_windows` (WebView2).
///
/// This implementation leverages Microsoft Edge WebView2 which is available on
/// Windows 10 1809+ and Windows 11.
///
/// ### JavaScript Bridge
/// Messages from JS are sent via `window.chrome.webview.postMessage(text)` and
/// arrive on the [ww.WebviewController.webMessage] stream.
class WindowsWebView implements PlatformWebView {
  late ww.WebviewController _controller;
  StreamSubscription? _messageSub;
  StreamSubscription? _loadingSub;
  bool _disposed = false;

  @override
  WebViewMessageCallback? onMessageReceived;

  @override
  WebViewPageFinishedCallback? onPageFinished;

  String? _currentUrl;

  @override
  Future<void> initialize() async {
    _controller = ww.WebviewController();
    await _controller.initialize();

    // Listen for web messages (JS -> Dart bridge)
    _messageSub = _controller.webMessage.listen((message) {
      if (_disposed) return;
      final text = message is String ? message : message.toString();
      onMessageReceived?.call(text);
    });

    // Listen for loading state changes to detect page-finished
    _loadingSub = _controller.loadingState.listen((state) {
      if (_disposed) return;
      if (state == ww.LoadingState.navigationCompleted) {
        onPageFinished?.call(_currentUrl ?? '');
      }
    });
  }

  @override
  Future<void> loadUrl(String url) async {
    if (_disposed) return;
    _currentUrl = url;
    await _controller.loadUrl(url);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    if (_disposed) return;
    await _controller.executeScript(javaScript);
  }

  @override
  Future<String> runJavaScriptReturningResult(String javaScript) async {
    if (_disposed) return '';
    final result = await _controller.executeScript(javaScript);
    return result?.toString() ?? '';
  }

  @override
  Future<void> setUserAgent(String userAgent) async {
    if (_disposed) return;
    await _controller.executeScript(
      "Object.defineProperty(navigator, 'userAgent', {get: function(){return '$userAgent';}});",
    );
  }

  @override
  Widget buildWidget() {
    return ww.Webview(_controller);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _messageSub?.cancel();
    _loadingSub?.cancel();
    _controller.dispose();
  }
}
