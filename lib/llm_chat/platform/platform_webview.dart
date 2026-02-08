import 'package:flutter/widgets.dart';

/// Callback for when the WebView receives a message from JavaScript.
typedef WebViewMessageCallback = void Function(String message);

/// Callback for when a page finishes loading.
typedef WebViewPageFinishedCallback = void Function(String url);

/// Abstract cross-platform WebView interface.
///
/// This abstraction decouples the LLM chat widget from any specific WebView
/// implementation, allowing different backends per platform:
///
/// - **Windows**: Uses `webview_windows` (WebView2/Edge)
/// - **Android/iOS/macOS/web**: Uses `webview_flutter`
///
/// ## Lifecycle
/// 1. Create via [PlatformWebView.create] factory (auto-detects platform).
/// 2. Call [initialize] before any other method.
/// 3. Use [loadUrl], [runJavaScript], [runJavaScriptReturningResult] as needed.
/// 4. Call [dispose] when done.
///
/// ## JavaScript Bridge
/// Register a [onMessageReceived] callback before loading any URL. The WebView
/// implementation ensures that JavaScript can call this bridge via:
/// - `webview_flutter`: `LlmBridge.postMessage(text)`
/// - `webview_windows`: `window.chrome.webview.postMessage(text)`
abstract class PlatformWebView {
  /// Factory that returns the correct implementation for the current platform.
  ///
  /// On Windows, returns [WindowsWebView]. On all other platforms, returns
  /// [MobileWebView] (backed by `webview_flutter`).
  factory PlatformWebView.create() {
    // Conditional import pattern won't work here; use runtime check.
    // The actual factory is in platform_webview_factory.dart
    throw UnimplementedError('Use PlatformWebViewFactory.create() instead');
  }

  /// Initializes the WebView. Must be called before any other method.
  Future<void> initialize();

  /// Navigates the WebView to the given [url].
  Future<void> loadUrl(String url);

  /// Executes JavaScript in the WebView (fire-and-forget).
  Future<void> runJavaScript(String javaScript);

  /// Executes JavaScript and returns the string result.
  Future<String> runJavaScriptReturningResult(String javaScript);

  /// Sets a custom User-Agent string.
  Future<void> setUserAgent(String userAgent);

  /// Callback invoked when the JavaScript bridge sends a message to Dart.
  ///
  /// Set this before calling [initialize] so the bridge is registered.
  WebViewMessageCallback? onMessageReceived;

  /// Callback invoked when a page finishes loading.
  ///
  /// Set this before calling [loadUrl] to receive the first notification.
  WebViewPageFinishedCallback? onPageFinished;

  /// Returns the Flutter widget that renders this WebView.
  ///
  /// Call only after [initialize] has completed.
  Widget buildWidget();

  /// Releases all resources held by this WebView.
  void dispose();
}
