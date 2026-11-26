import 'package:shared_preferences/shared_preferences.dart';

/// Stores the local PDF paths the user has marked as favorites.
class LocalPdfFavoritesService {
  static const String _favoritesKey = 'favorite_local_pdf_paths';

  static Future<Set<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return paths.toSet();
  }

  static Future<void> saveFavorites(Set<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedPaths = paths.toList()..sort();
    await prefs.setStringList(_favoritesKey, sortedPaths);
  }
}
