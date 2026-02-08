import 'package:flutter_test/flutter_test.dart';

import 'package:llmchatbox/llm_chat/llm_chat.dart';

void main() {
  test('LlmType has correct URLs', () {
    expect(LlmType.chatGpt.url, 'https://chat.openai.com/');
    expect(LlmType.claude.url, 'https://claude.ai/new');
    expect(LlmType.gemini.url, 'https://gemini.google.com/app');
    expect(LlmType.copilot.url, 'https://copilot.microsoft.com/');
    expect(LlmType.metaAi.url, 'https://www.meta.ai/');
    expect(LlmType.deepSeek.url, 'https://chat.deepseek.com/');
  });

  test('LlmType has display names', () {
    for (final t in LlmType.values) {
      expect(t.displayName.isNotEmpty, true);
    }
  });

  test('LlmJsProvider factory returns correct types', () {
    expect(LlmJsProvider.forType(LlmType.chatGpt), isNotNull);
    expect(LlmJsProvider.forType(LlmType.claude), isNotNull);
    expect(LlmJsProvider.forType(LlmType.gemini), isNotNull);
    expect(LlmJsProvider.forType(LlmType.copilot), isNotNull);
    expect(LlmJsProvider.forType(LlmType.metaAi), isNotNull);
    expect(LlmJsProvider.forType(LlmType.deepSeek), isNotNull);
  });

  test('LlmJsProvider.escapeForJs escapes special chars', () {
    expect(LlmJsProvider.escapeForJs("it's"), "it\\'s");
    expect(LlmJsProvider.escapeForJs('line1\nline2'), 'line1\\nline2');
    expect(LlmJsProvider.escapeForJs('a\\b'), 'a\\\\b');
  });

  test('LlmChatController initializes correctly', () {
    final ctrl = LlmChatController(
      llmType: LlmType.chatGpt,
      basePrompt: 'Hello',
      debug: true,
    );
    expect(ctrl.llmType, LlmType.chatGpt);
    expect(ctrl.isLlmAvailable, false);
    expect(ctrl.isWaitingForResponse, false);
    expect(ctrl.queueLength, 0);
    ctrl.dispose();
  });

  test('LlmChatController.resetLlm populates queue with basePrompt', () {
    String? navigatedUrl;
    final ctrl = LlmChatController(
      llmType: LlmType.chatGpt,
      basePrompt: 'System prompt',
      debug: false,
    );
    ctrl.onNavigate = (url) => navigatedUrl = url;
    ctrl.resetLlm();
    expect(ctrl.queueLength, 1);
    expect(navigatedUrl, LlmType.chatGpt.url);
    ctrl.dispose();
  });

  test('LlmChatController.sendToLlm drops messages when unavailable', () {
    final ctrl = LlmChatController(
      llmType: LlmType.chatGpt,
      debug: false,
    );
    ctrl.sendToLlm('test');
    expect(ctrl.queueLength, 0); // dropped because not available
    ctrl.dispose();
  });

  test('JS providers generate non-empty snippets', () {
    for (final t in LlmType.values) {
      final p = LlmJsProvider.forType(t);
      expect(p.jsDetectAvailability().isNotEmpty, true, reason: '${t.name} availability');
      expect(p.jsSendMessage('test').isNotEmpty, true, reason: '${t.name} sendMessage');
      expect(p.jsInstallCopyMutationObserver().isNotEmpty, true, reason: '${t.name} observer');
      expect(p.jsHookClipboard().isNotEmpty, true, reason: '${t.name} clipboard');
    }
  });
}
