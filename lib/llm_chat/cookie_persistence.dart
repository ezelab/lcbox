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
