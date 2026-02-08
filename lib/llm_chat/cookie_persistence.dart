import 'dart:convert';
import 'dart:io';

/// Abstract interface for persisting WebView state (cookies, local storage).
///
/// Implement this interface to provide custom persistence for the WebView's
/// cookies and session data across app restarts.
///
/// ## Usage
/// ```dart
/// class MyCookiePersistence implements CookiePersistence {
///   @override
///   Future<Map<String, String>> loadCookies(String llmId) async { ... }
///   @override
///   Future<void> saveCookies(String llmId, Map<String, String> cookies) async { ... }
///   @override
///   Future<void> clearCookies(String llmId) async { ... }
/// }
/// ```
abstract class CookiePersistence {
  /// Loads saved cookies for the given [llmId].
  ///
  /// Returns a map of cookie name -> cookie value.
  /// Returns an empty map if no cookies are saved.
  Future<Map<String, String>> loadCookies(String llmId);

  /// Saves cookies for the given [llmId].
  ///
  /// [cookies] is a map of cookie name -> cookie value.
  Future<void> saveCookies(String llmId, Map<String, String> cookies);

  /// Clears all saved cookies for the given [llmId].
  Future<void> clearCookies(String llmId);
}

/// File-based implementation of [CookiePersistence].
///
/// Stores cookies as JSON files in the given [directory], one file per LLM.
///
/// ```dart
/// final persistence = FileCookiePersistence(
///   directory: Directory('/path/to/cookies'),
/// );
/// ```
class FileCookiePersistence implements CookiePersistence {
  /// The directory where cookie files are stored.
  final Directory directory;

  FileCookiePersistence({required this.directory});

  File _fileFor(String llmId) => File('${directory.path}/$llmId.cookies.json');

  @override
  Future<Map<String, String>> loadCookies(String llmId) async {
    final file = _fileFor(llmId);
    if (!await file.exists()) return {};
    try {
      final content = await file.readAsString();
      final Map<String, dynamic> data = json.decode(content);
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveCookies(String llmId, Map<String, String> cookies) async {
    final file = _fileFor(llmId);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await file.writeAsString(json.encode(cookies));
  }

  @override
  Future<void> clearCookies(String llmId) async {
    final file = _fileFor(llmId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
