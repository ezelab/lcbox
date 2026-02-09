# llmchatbox

A reusable Flutter widget that wraps 6 LLM web interfaces in a WebView with programmatic message send/receive via clipboard interception and copy-button auto-clicking.

## Supported LLMs

| LLM               | Provider Class       | Web URL                 |
| ----------------- | -------------------- | ----------------------- |
| Google Gemini     | `GeminiJsProvider`   | `gemini.google.com/app` |
| OpenAI ChatGPT    | `ChatGptJsProvider`  | `chat.openai.com`       |
| Anthropic Claude  | `ClaudeJsProvider`   | `claude.ai/new`         |
| Microsoft Copilot | `CopilotJsProvider`  | `copilot.microsoft.com` |
| Meta AI           | `MetaAiJsProvider`   | `meta.ai`               |
| DeepSeek          | `DeepSeekJsProvider` | `chat.deepseek.com`     |

## Installation

### Git dependency

```yaml
dependencies:
  llmchatbox:
    git:
      url: https://github.com/ezelab/lcbox.git
```

### Local path dependency

```yaml
dependencies:
  llmchatbox:
    path: ../llmchatbox
```

## Quick Start

```dart
import 'package:llmchatbox/llmchatbox.dart';

// 1. Create a controller
final controller = LlmChatController(
  llmType: LlmType.chatGpt,
  basePrompt: 'You are a helpful assistant. Respond concisely.',
  onMessageFromLlm: (message) {
    print('LLM responded: $message');
  },
  onLlmAvailabilityChanged: (available) {
    print('LLM available: $available');
  },
  debug: true,  // enables copious logging
);

// 2. Implement CookiePersistence (or skip for no persistence)
class MyCookiePersistence implements CookiePersistence {
  @override
  Future<Map<String, String>> loadCookies(String llmId) async { ... }
  @override
  Future<void> saveCookies(String llmId, Map<String, String> cookies) async { ... }
  @override
  Future<void> clearCookies(String llmId) async { ... }
}

// 3. Add the widget to your tree
@override
Widget build(BuildContext context) {
  return LlmChatWidget(
    controller: controller,
    cookiePersistence: MyCookiePersistence(),
  );
}

// 4. Send messages programmatically
controller.sendToLlm('What is the capital of France?');

// 5. Switch LLM or reset conversation
controller.resetLlm();

// 6. Clean up
controller.dispose();
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Your App                                           │
│                                                     │
│  ┌──────────────┐    ┌──────────────────────────┐   │
│  │ LlmChatWidget│───▶│   LlmChatController      │   │
│  │ (InAppWebView)│   │   - message queue         │   │
│  └──────────────┘    │   - send/receive flow     │   │
│                      │   - availability state     │   │
│                      └──────────┬───────────────┘   │
│                                 │                    │
│                                 ▼                    │
│                      ┌──────────────────────────┐   │
│                      │   LlmJsProvider          │   │
│                      │   (per-LLM JS snippets)   │   │
│                      └──────────────────────────┘   │
│  ┌──────────────────┐                               │
│  │CookiePersistence │  (optional, caller-provided)  │
│  └──────────────────┘                               │
└─────────────────────────────────────────────────────┘
```

## Core API

### `LlmType`

Enum of supported LLM providers. Each has a `.url` and `.displayName`:

```dart
LlmType.chatGpt.url         // 'https://chat.openai.com/'
LlmType.chatGpt.displayName // 'ChatGPT'
```

### `LlmChatController`

The primary programmatic interface.

| Method / Property                                               | Description                               |
| --------------------------------------------------------------- | ----------------------------------------- |
| `LlmChatController(llmType, basePrompt, onMessageFromLlm, ...)` | Constructor                               |
| `sendToLlm(String message)`                                     | Enqueue a message; sent when LLM is ready |
| `resetLlm()`                                                    | Clear queue, push basePrompt, reload page |
| `isAvailable`                                                   | Whether the LLM is currently usable       |
| `isWaitingForResponse`                                          | Whether we're waiting for a reply         |
| `onMessageFromLlm`                                              | Callback fired with each LLM response     |
| `onLlmAvailabilityChanged`                                      | Callback when availability changes        |
| `dispose()`                                                     | Clean up resources                        |

### `LlmChatWidget`

The Flutter widget that renders the WebView. Uses `flutter_inappwebview` for
cross-platform support (WebView2 on Windows, native WebView on Android/iOS/macOS).

| Parameter             | Type                  | Required | Description                                          |
| --------------------- | --------------------- | -------- | ---------------------------------------------------- |
| `controller`          | `LlmChatController`   | ✅        | The controller instance                              |
| `cookiePersistence`   | `CookiePersistence?`  | ❌        | Optional cookie/session storage (caller-provided)    |
| `userAgent`           | `String?`             | ❌        | Custom User-Agent string                             |
| `webViewEnvironment`  | `WebViewEnvironment?` | ❌        | Shared browser profile (Windows WebView2 data folder)|

### `WebViewEnvironment` (optional)

On Windows, pass a `WebViewEnvironment` to share a persistent browser profile
(cookies, cache, user data folder) with other WebViews in your app. If not
provided, the default environment is used.

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

final env = await WebViewEnvironment.create(
  settings: WebViewEnvironmentSettings(userDataFolder: 'path/to/data'),
);

LlmChatWidget(
  controller: controller,
  webViewEnvironment: env,
);
```

### `CookiePersistence`

Abstract interface for session persistence. The library does **not** include a
concrete implementation — callers provide their own:

```dart
class FileCookiePersistence implements CookiePersistence {
  final Directory directory;
  FileCookiePersistence({required this.directory});

  @override
  Future<Map<String, String>> loadCookies(String llmId) async { ... }
  @override
  Future<void> saveCookies(String llmId, Map<String, String> cookies) async { ... }
  @override
  Future<void> clearCookies(String llmId) async { ... }
}
```

See `example/lib/file_cookie_persistence.dart` for a complete file-based
implementation you can copy into your project.

### `LlmJsProvider`

Base class for LLM-specific JavaScript. Use the factory to get the right provider:

```dart
final provider = LlmJsProvider.forType(LlmType.chatGpt);
```

Each provider implements 4 JS snippet methods:

| Method                            | Purpose                                             |
| --------------------------------- | --------------------------------------------------- |
| `jsDetectAvailability()`          | Check if LLM is signed in and ready                 |
| `jsSendMessage(message)`          | Type message into input and click send              |
| `jsInstallCopyMutationObserver()` | Auto-click copy buttons on LLM responses            |
| `jsHookClipboard()`               | Intercept clipboard writes to capture response text |

## How It Works

1. **Page loads** → availability JS checks for blocking popups and message input
2. **If available** → bridge shim, clipboard hook, and mutation observer are installed
3. **`sendToLlm()`** → message is queued; JS types it into the input and clicks send
4. **LLM responds** → mutation observer clicks the copy button on the response
5. **Copy triggers clipboard** → hooked `navigator.clipboard.writeText` sends text to Dart via `window.flutter_inappwebview.callHandler('LlmBridge', text)`
6. **`onMessageFromLlm` fires** → your callback receives the response text
7. **Queue drains** → next queued message is sent automatically

## Message Queue

Messages are queued and sent one at a time. The controller waits for a response before sending the next message. On `resetLlm()`, the queue is cleared and `basePrompt` is pushed as the first message.

## Debug Mode

Pass `debug: true` to `LlmChatController` for verbose logging:

```dart
LlmChatController(
  llmType: LlmType.chatGpt,
  basePrompt: 'Hello',
  onMessageFromLlm: (msg) {},
  debug: true,  // logs all JS injection, queue state, availability, etc.
);
```

## Platform Support

| Platform | WebView Backend                            | Status       |
| -------- | ------------------------------------------ | ------------ |
| Windows  | `flutter_inappwebview` (WebView2/Edge)     | ✅ Tested     |
| Android  | `flutter_inappwebview` (Android WebView)   | 🔧 Supported |
| iOS      | `flutter_inappwebview` (WKWebView)         | 🔧 Supported |
| macOS    | `flutter_inappwebview` (WKWebView)         | 🔧 Supported |
| Web      | Not supported (no WebView embedding)       | ❌            |

## Adding a New LLM Provider

1. Add a variant to `LlmType` enum with URL and display name
2. Create a new class implementing `LlmJsProvider` (use `DefaultJsSnippets` mixin for shared clipboard/observer logic)
3. Add the case to `LlmJsProvider.forType()` factory
4. Implement the 4 JS snippet methods for the LLM's specific DOM structure

```dart
class MyLlmJsProvider with DefaultJsSnippets implements LlmJsProvider {
  @override
  String jsDetectAvailability() => '(function() { ... })();';

  @override
  String jsSendMessage(String message) {
    final escaped = DefaultJsSnippets.escapeJs(message);
    return '(function() { ... })();';
  }

  // jsInstallCopyMutationObserver and jsHookClipboard provided by DefaultJsSnippets mixin
}
```

## Test Harness

The included `example/` app is a full test harness with:

* LLM picker dropdown to switch between providers
* Manual test buttons (full 5-test suite and lite PONG test)
* Cookie persistence (file-based, in `example/lib/file_cookie_persistence.dart`)

Run it with:

```bash
cd example
flutter run -d windows   # or android, ios, etc.
```

## License

See [LICENSE](LICENSE) for details.