import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:llmchatbox/llmchatbox.dart';

void main() {
  runApp(const LlmTestHarnessApp());
}

/// Test harness application for the LLM Chat Widget.
///
/// Provides a visible UI with:
/// - LLM selector dropdown
/// - WebView showing the LLM interface
/// - Log output panel
/// - Manual message input
/// - Automated test runner with 30s spacing between tests
class LlmTestHarnessApp extends StatelessWidget {
  const LlmTestHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Chat Test Harness',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const TestHarnessPage(),
    );
  }
}

class TestHarnessPage extends StatefulWidget {
  const TestHarnessPage({super.key});

  @override
  State<TestHarnessPage> createState() => _TestHarnessPageState();
}

class _TestHarnessPageState extends State<TestHarnessPage> {
  LlmType _selectedLlm = LlmType.chatGpt;
  LlmChatController? _controller;
  FileCookiePersistence? _cookiePersistence;
  bool _llmAvailable = false;
  bool _isRunningTests = false;
  final List<String> _logs = [];
  final List<TestResult> _testResults = [];
  final ScrollController _logScroller = ScrollController();
  final TextEditingController _messageInput = TextEditingController();
  String? _lastLlmResponse;

  @override
  void initState() {
    super.initState();
    _initPersistence();
  }

  Future<void> _initPersistence() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cookieDir = Directory('${appDir.path}/llm_cookies');
    setState(() {
      _cookiePersistence = FileCookiePersistence(directory: cookieDir);
    });
    _log('Cookie persistence initialized: ${cookieDir.path}');
    _initController();
  }

  /// Total number of test passes for multi-pass testing.
  static const int _totalAutoRunPasses = 10;
  int _currentPass = 0;

  void _initController() {
    // Create once — reuse for all LLM switches
    _controller = LlmChatController(
      llmType: _selectedLlm,
      basePrompt: '',
      onMessageFromLlm: _onMessageFromLlm,
      onLlmAvailabilityChanged: (available) {
        setState(() => _llmAvailable = available);
        _log('LLM availability changed: $available');
      },
      debug: true,
    );
    _log('Controller created for ${_selectedLlm.displayName}');
    setState(() {
      _llmAvailable = false;
      _lastLlmResponse = null;
    });
  }

  void _onMessageFromLlm(String message) {
    _lastLlmResponse = message;
    _log('📩 LLM Response (${message.length} chars): '
        '${message.length > 200 ? "${message.substring(0, 200)}..." : message}');
    setState(() {});
  }

  /// Dump DOM debug info for diagnosing test failures.
  Future<void> _dumpDomDebug(String context) async {
    if (_controller == null) return;
    _log('🔍 DOM Debug Dump ($context):');
    final dump = await _controller!.dumpDomDebug();
    // Split into lines and log each to avoid truncation
    for (final line in dump.split('\n')) {
      _log('  DOM: $line');
    }
  }

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final entry = '[$timestamp] $msg';
    setState(() {
      _logs.add(entry);
      if (_logs.length > 2000) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroller.hasClients) {
        _logScroller.animateTo(
          _logScroller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
    print('[TestHarness] $entry');
  }

  void _switchLlm(LlmType llm) {
    if (llm == _selectedLlm) return;
    _log('Switching to ${llm.displayName}...');
    setState(() => _selectedLlm = llm);
    _lastLlmResponse = null;
    _llmAvailable = false;
    _controller?.resetLlm(newLlmType: llm, newBasePrompt: '');
  }

  void _showLlmPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select LLM'),
        children: LlmType.values.map((t) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _switchLlm(t);
            },
            child: Text(
              t == _selectedLlm ? '▶ ${t.displayName}' : '   ${t.displayName}',
              style: TextStyle(
                fontWeight:
                    t == _selectedLlm ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _sendManualMessage() {
    final msg = _messageInput.text.trim();
    if (msg.isEmpty) return;
    _log('📤 Sending: $msg');
    _controller?.sendToLlm(msg);
    _messageInput.clear();
  }

  void _resetLlm() {
    _log('🔄 Resetting LLM...');
    _controller?.resetLlm();
  }

  // ---------------------------------------------------------------------------
  // Automated Tests
  // ---------------------------------------------------------------------------

  /// Runs all test passes (10x) across all LLMs.
  Future<void> _runAllTestsPasses() async {
    if (_isRunningTests) return;
    setState(() {
      _isRunningTests = true;
      _testResults.clear();
    });

    for (_currentPass = 1; _currentPass <= _totalAutoRunPasses; _currentPass++) {
      _log('');
      _log('╔═══════════════════════════════════════════╗');
      _log('║  PASS $_currentPass / $_totalAutoRunPasses');
      _log('╚═══════════════════════════════════════════╝');

      // Test all LLMs - put Gemini last since it needs Quill-specific debugging
      final llmOrder = [
        LlmType.chatGpt,
        LlmType.claude,
        LlmType.gemini,
        LlmType.deepSeek,
        LlmType.copilot,
        LlmType.metaAi,
      ];
      for (final llm in llmOrder) {
        _log('═══════════════════════════════════════');
        _log('🧪 [Pass $_currentPass] Testing ${llm.displayName}...');
        _switchLlm(llm);

        // Wait for page load and availability (up to 20s)
        var waitedSecs = 0;
        while (!_llmAvailable && waitedSecs < 20) {
          await Future.delayed(const Duration(seconds: 2));
          waitedSecs += 2;
        }

        if (!_llmAvailable) {
          _log('⚠️ ${llm.displayName} is NOT available after ${waitedSecs}s. Dumping DOM...');
          await _dumpDomDebug('${llm.displayName} unavailable');
          _testResults.add(TestResult(
            llm: llm,
            testName: 'availability_p$_currentPass',
            passed: false,
            message: 'LLM not available',
          ));
          continue;
        }

        await _runTestSuiteForCurrentLlm(llm);

        if (llm != llmOrder.last) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      final passed = _testResults.where((r) => r.passed).length;
      _log('📊 Pass $_currentPass complete. Running total: $passed/${_testResults.length} passed.');

      if (_currentPass < _totalAutoRunPasses) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    final passed = _testResults.where((r) => r.passed).length;
    final total = _testResults.length;
    _log('');
    _log('╔═══════════════════════════════════════════════╗');
    _log('║  ALL $_totalAutoRunPasses PASSES COMPLETE: $passed/$total tests passed');
    _log('╚═══════════════════════════════════════════════╝');
    setState(() => _isRunningTests = false);
  }

  Future<void> _runAllTests() async {
    if (_isRunningTests) return;
    setState(() {
      _isRunningTests = true;
      _testResults.clear();
    });

    _log('🧪 Starting automated test run for ALL LLMs...');

    for (final llm in LlmType.values) {
      _log('═══════════════════════════════════════');
      _log('🧪 Testing ${llm.displayName}...');
      _switchLlm(llm);

      // Wait for page load and availability
      await Future.delayed(const Duration(seconds: 10));

      if (!_llmAvailable) {
        _log('⚠️ ${llm.displayName} is NOT available (not logged in?). Skipping.');
        _testResults.add(TestResult(
          llm: llm,
          testName: 'availability',
          passed: false,
          message: 'LLM not available',
        ));
        continue;
      }

      await _runTestSuiteForCurrentLlm(llm);

      if (llm != LlmType.values.last) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    _log('🧪 All tests complete!');
    _log('Results: ${_testResults.where((r) => r.passed).length}/${_testResults.length} passed');
    setState(() => _isRunningTests = false);
  }

  Future<void> _runTestsForCurrentLlm() async {
    if (_isRunningTests) return;
    if (!_llmAvailable) {
      _log('⚠️ LLM not available. Cannot run tests.');
      return;
    }
    setState(() {
      _isRunningTests = true;
      _testResults.clear();
    });

    await _runTestSuiteForCurrentLlm(_selectedLlm);

    _log('🧪 Tests complete for ${_selectedLlm.displayName}!');
    _log('Results: ${_testResults.where((r) => r.passed).length}/${_testResults.length} passed');
    setState(() => _isRunningTests = false);
  }

  /// Lite test: runs only the simple PONG test on the current LLM.
  Future<void> _runLiteTestCurrentLlm() async {
    if (_isRunningTests) return;
    setState(() {
      _isRunningTests = true;
      _testResults.clear();
    });
    _log('⚡ Lite test for ${_selectedLlm.displayName}...');
    // Wait for availability (up to 20s)
    var waitedSecs = 0;
    while (!_llmAvailable && waitedSecs < 20) {
      await Future.delayed(const Duration(seconds: 2));
      waitedSecs += 2;
    }
    await _runLiteTest(_selectedLlm);
    _log('⚡ Lite test done: ${_testResults.where((r) => r.passed).length}/${_testResults.length} passed');
    setState(() => _isRunningTests = false);
  }

  /// Lite test: runs only the simple PONG test across all LLMs.
  Future<void> _runLiteTestAllLlms() async {
    if (_isRunningTests) return;
    setState(() {
      _isRunningTests = true;
      _testResults.clear();
    });
    _log('⚡ Lite test ALL LLMs...');
    for (final llm in LlmType.values) {
      _log('═══════════════════════════════════════');
      _log('⚡ Lite testing ${llm.displayName}...');
      _switchLlm(llm);
      var waitedSecs = 0;
      while (!_llmAvailable && waitedSecs < 20) {
        await Future.delayed(const Duration(seconds: 2));
        waitedSecs += 2;
      }
      if (!_llmAvailable) {
        _log('⚠️ ${llm.displayName} not available. Skipping.');
        _testResults.add(TestResult(
          llm: llm, testName: 'lite', passed: false, message: 'Unavailable',
        ));
        continue;
      }
      await _runLiteTest(llm);
      if (llm != LlmType.values.last) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    final passed = _testResults.where((r) => r.passed).length;
    _log('⚡ Lite test ALL done: $passed/${_testResults.length} passed');
    setState(() => _isRunningTests = false);
  }

  /// Single lite test (PONG check) for one LLM.
  Future<void> _runLiteTest(LlmType llm) async {
    await _runTest(llm, 'lite', () async {
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'Reply with exactly the word "PONG" and nothing else. No explanation, just PONG.',
      );
      final response = await _waitForResponse(timeout: 60);
      if (response == null) return 'No response received';
      if (response.trim().toUpperCase().contains('PONG')) return null;
      return 'Expected PONG, got: ${_trunc(response)}';
    });
  }

  Future<void> _runTestSuiteForCurrentLlm(LlmType llm) async {
    // Test 1: Simple echo/response
    await _runTest(llm, 'simple_response', () async {
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'Reply with exactly the word "PONG" and nothing else. No explanation, just PONG.',
      );
      final response = await _waitForResponse(timeout: 60);
      if (response == null) return 'No response received';
      if (response.trim().toUpperCase().contains('PONG')) return null;
      return 'Expected PONG, got: ${_trunc(response)}';
    });

    await Future.delayed(const Duration(seconds: 5));

    // Test 2: Random number round-trip
    await _runTest(llm, 'random_number_roundtrip', () async {
      final randomNum = Random().nextInt(99999) + 10000;
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'I am going to give you a number. Remember it. The number is $randomNum. '
        'Reply with ONLY that number and nothing else.',
      );
      final response1 = await _waitForResponse(timeout: 60);
      if (response1 == null) return 'No response to number prompt';
      if (!response1.contains(randomNum.toString())) {
        return 'LLM did not echo number. Got: ${_trunc(response1)}';
      }

      await Future.delayed(const Duration(seconds: 5));

      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'What was the number I just gave you? Reply with ONLY the number.',
      );
      final response2 = await _waitForResponse(timeout: 60);
      if (response2 == null) return 'No response to recall prompt';
      if (response2.contains(randomNum.toString())) return null;
      return 'LLM forgot number. Expected $randomNum, got: ${_trunc(response2)}';
    });

    await Future.delayed(const Duration(seconds: 5));

    // Test 3: Boolean verification
    await _runTest(llm, 'boolean_verification', () async {
      final words = ['ALPHA', 'BRAVO', 'CHARLIE', 'DELTA', 'ECHO'];
      final randomWord = words[Random().nextInt(words.length)];
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'The secret word is "$randomWord". Reply with ONLY that word, nothing else.',
      );
      final response1 = await _waitForResponse(timeout: 60);
      if (response1 == null) return 'No response to secret word prompt';

      await Future.delayed(const Duration(seconds: 5));

      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'Was the secret word "$randomWord"? Reply with exactly "TRUE" or "FALSE" only.',
      );
      final response2 = await _waitForResponse(timeout: 60);
      if (response2 == null) return 'No response to verification prompt';
      if (response2.trim().toUpperCase().contains('TRUE')) return null;
      return 'Expected TRUE, got: ${_trunc(response2)}';
    });

    await Future.delayed(const Duration(seconds: 5));

    // Test 4: Math verification
    await _runTest(llm, 'math_verification', () async {
      final a = Random().nextInt(50) + 1;
      final b = Random().nextInt(50) + 1;
      final expected = a + b;
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'What is $a + $b? Reply with ONLY the number, nothing else.',
      );
      final response = await _waitForResponse(timeout: 60);
      if (response == null) return 'No response to math prompt';
      if (response.contains(expected.toString())) return null;
      return 'Expected $expected, got: ${_trunc(response)}';
    });

    await Future.delayed(const Duration(seconds: 5));

    // Test 5: Multi-turn conversation coherence
    await _runTest(llm, 'multi_turn_coherence', () async {
      final animals = ['cat', 'dog', 'elephant', 'penguin', 'tiger'];
      final animal = animals[Random().nextInt(animals.length)];
      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'My favorite animal is a $animal. Just say "OK" to acknowledge.',
      );
      final response1 = await _waitForResponse(timeout: 60);
      if (response1 == null) return 'No response to setup prompt';

      await Future.delayed(const Duration(seconds: 5));

      _lastLlmResponse = null;
      _controller!.sendToLlm(
        'What is my favorite animal? Reply with ONLY the animal name.',
      );
      final response2 = await _waitForResponse(timeout: 60);
      if (response2 == null) return 'No response to recall prompt';
      if (response2.toLowerCase().contains(animal)) return null;
      return 'Expected $animal, got: ${_trunc(response2)}';
    });
  }

  Future<void> _runTest(
    LlmType llm,
    String testName,
    Future<String?> Function() testFn,
  ) async {
    _log('  🔬 Running test: $testName');
    try {
      final error = await testFn();
      final passed = error == null;
      _testResults.add(TestResult(
        llm: llm,
        testName: testName,
        passed: passed,
        message: error ?? 'Passed',
      ));
      _log('  ${passed ? "✅" : "❌"} $testName: ${error ?? "PASSED"}');
      if (!passed) {
        await _dumpDomDebug('$testName failed on ${llm.displayName}');
      }
    } catch (e) {
      _testResults.add(TestResult(
        llm: llm,
        testName: testName,
        passed: false,
        message: 'Exception: $e',
      ));
      _log('  ❌ $testName: Exception: $e');
      await _dumpDomDebug('$testName exception on ${llm.displayName}');
    }
    setState(() {});
  }

  Future<String?> _waitForResponse({int timeout = 60}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeout));
    while (DateTime.now().isBefore(deadline)) {
      if (_lastLlmResponse != null) return _lastLlmResponse;
      await Future.delayed(const Duration(seconds: 2));
    }
    // Timeout — resetLlm clears _waitingForLlmResponse so subsequent sends aren't blocked
    _log('⏱️ Response timeout — resetting LLM to unblock queue');
    _controller?.resetLlm();
    // Wait for page reload + availability
    await Future.delayed(const Duration(seconds: 8));
    return null;
  }

  String _trunc(String s, [int max = 80]) =>
      s.length <= max ? s : '${s.substring(0, max)}...';

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final llmIndex = LlmType.values.indexOf(_selectedLlm);
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Chat Test Harness'),
        actions: [
          // Previous LLM button
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous LLM',
            onPressed: _isRunningTests || llmIndex == 0
                ? null
                : () => _switchLlm(LlmType.values[llmIndex - 1]),
          ),
          // Current LLM label
          GestureDetector(
            onTap: _isRunningTests ? null : () => _showLlmPicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedLlm.displayName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // Next LLM button
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next LLM',
            onPressed: _isRunningTests ||
                    llmIndex == LlmType.values.length - 1
                ? null
                : () => _switchLlm(LlmType.values[llmIndex + 1]),
          ),
          const SizedBox(width: 8),
          Icon(
            _llmAvailable ? Icons.check_circle : Icons.cancel,
            color: _llmAvailable ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset LLM',
            onPressed: _resetLlm,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // WebView area
          Expanded(
            flex: 3,
            child: _controller != null && _cookiePersistence != null
                ? LlmChatWidget(
                    controller: _controller!,
                    cookiePersistence: _cookiePersistence,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const Divider(height: 1),
          // Controls
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageInput,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendManualMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _llmAvailable ? _sendManualMessage : null,
                  child: const Text('Send'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      _isRunningTests ? null : _runTestsForCurrentLlm,
                  child:
                      Text(_isRunningTests ? 'Running...' : 'Test This LLM'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isRunningTests ? null : _runAllTests,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child:
                      Text(_isRunningTests ? 'Running...' : 'Test All LLMs'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isRunningTests ? null : _runLiteTestCurrentLlm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                  child: Text(
                      _isRunningTests ? '...' : '⚡ Lite'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isRunningTests ? null : _runLiteTestAllLlms,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                  ),
                  child: Text(
                      _isRunningTests ? '...' : '⚡ Lite All'),
                ),
              ],
            ),
          ),
          // Test results bar
          if (_testResults.isNotEmpty)
            Container(
              color: Colors.grey[850],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _testResults.map((r) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        avatar: Icon(
                          r.passed ? Icons.check : Icons.close,
                          color: r.passed ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        label: Text(
                          '${r.llm.displayName}:${r.testName}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          // Log output
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: ListView.builder(
                controller: _logScroller,
                padding: const EdgeInsets.all(4),
                itemCount: _logs.length,
                itemBuilder: (_, i) => Text(
                  _logs[i],
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _logs[i].contains('❌')
                        ? Colors.red[300]
                        : _logs[i].contains('✅')
                            ? Colors.green[300]
                            : _logs[i].contains('📩')
                                ? Colors.cyan[300]
                                : _logs[i].contains('📤')
                                    ? Colors.yellow[300]
                                    : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _logScroller.dispose();
    _messageInput.dispose();
    super.dispose();
  }
}

/// Represents a single test result.
class TestResult {
  final LlmType llm;
  final String testName;
  final bool passed;
  final String message;

  TestResult({
    required this.llm,
    required this.testName,
    required this.passed,
    required this.message,
  });
}
