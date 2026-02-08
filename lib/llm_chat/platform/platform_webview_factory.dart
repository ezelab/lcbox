import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'platform_webview.dart';
import 'windows_webview.dart';
import 'mobile_webview.dart';

/// Factory for creating the correct [PlatformWebView] for the current platform.
///
/// ```dart
/// final webView = PlatformWebViewFactory.create();
/// await webView.initialize();
/// ```
///
/// ## Platform Selection
/// - **Windows** → [WindowsWebView] (WebView2/Edge via `webview_windows`)
/// - **Android/iOS/macOS/Web** → [MobileWebView] (`webview_flutter`)
class PlatformWebViewFactory {
  /// Creates the appropriate [PlatformWebView] for the running platform.
  static PlatformWebView create() {
    if (!kIsWeb && Platform.isWindows) {
      return WindowsWebView();
    }
    return MobileWebView();
  }
}
