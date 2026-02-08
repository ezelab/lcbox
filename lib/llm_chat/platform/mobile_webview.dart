import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'platform_webview.dart';

/// Mobile/default implementation of [PlatformWebView] using `webview_flutter`.
///
/// Works on Android, iOS, macOS, and web. Uses `webview_flutter`'s federated
/// plugin system which auto-selects the correct platform backend.
///
/// ### JavaScript Bridge
/// A JavaScript channel named `LlmBridge` is registered. JS sends messages via
/// `LlmBridge.postMessage(text)`.
class MobileWebView implements PlatformWebView {
  late WebViewController _controller;

  @override
  WebViewMessageCallback? onMessageReceived;

  @override
  WebViewPageFinishedCallback? onPageFinished;

  @override
  Future<void> initialize() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LlmBridge',
        onMessageReceived: (JavaScriptMessage message) {
          onMessageReceived?.call(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            onPageFinished?.call(url);
          },
        ),
      );
  }

  @override
  Future<void> loadUrl(String url) async {
    await _controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    await _controller.runJavaScript(javaScript);
  }

  @override
  Future<String> runJavaScriptReturningResult(String javaScript) async {
    final result = await _controller.runJavaScriptReturningResult(javaScript);
    return result.toString();
  }

  @override
  Future<void> setUserAgent(String userAgent) async {
    await _controller.setUserAgent(userAgent);
  }

  @override
  Widget buildWidget() {
    return WebViewWidget(controller: _controller);
  }

  @override
  void dispose() {
    // webview_flutter's WebViewController doesn't have a dispose method;
    // it's managed by the WebViewWidget lifecycle.
  }
}
