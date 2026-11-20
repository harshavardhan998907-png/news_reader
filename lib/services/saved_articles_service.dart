import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_article.dart';

/// Service managing persistent storage of Favourites and Bookmarks.
/// Uses SharedPreferences and serializes articles as JSON.
/// Namespaces storage keys by Firebase user UID.
class SavedArticlesService extends ChangeNotifier {
  static final SavedArticlesService _instance =
      SavedArticlesService._internal();

  factory SavedArticlesService() => _instance;

  SavedArticlesService._internal();

  SharedPreferences? _prefs;
  String _userId = 'guest';

  List<NewsArticle> _favourites = [];
  List<NewsArticle> _bookmarks = [];
  bool _isInitialized = false;

  /// Visible for testing to inject custom/mock SharedPreferences
  @visibleForTesting
  SavedArticlesService.withPrefs(SharedPreferences prefs, {String userId = 'guest'}) {
    _prefs = prefs;
    _userId = userId;
    _isInitialized = true;
  }

  /// Current user ID for namespacing
  String get userId => _userId;

  /// Unmodifiable list of currently loaded favourites
  List<NewsArticle> get favourites => List.unmodifiable(_favourites);

  /// Unmodifiable list of currently loaded bookmarks
  List<NewsArticle> get bookmarks => List.unmodifiable(_bookmarks);

  String get _favouritesKey => 'news_reader_favourites_$_userId';
  String get _bookmarksKey => 'news_reader_bookmarks_$_userId';

  /// Initializes the service with SharedPreferences and loads saved articles
  /// for the specified [userId].
  Future<void> init({String? userId}) async {
    final newUserId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : 'guest';

    // If already initialized for the same user, no need to reload
    if (_isInitialized && _userId == newUserId && _prefs != null) {
      return;
    }

    _userId = newUserId;
    _prefs ??= await SharedPreferences.getInstance();

    await Future.wait([
      loadFavourites(),
      loadBookmarks(),
    ]);

    _isInitialized = true;
    notifyListeners();
  }

  /// Ensures SharedPreferences is ready
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Loads favourite articles from SharedPreferences.
  /// Handles missing, empty, or corrupted JSON safely.
  Future<List<NewsArticle>> loadFavourites() async {
    final prefs = await _getPrefs();
    final jsonStrings = prefs.getStringList(_favouritesKey) ?? [];

    final List<NewsArticle> loaded = [];
    for (final raw in jsonStrings) {
      try {
        final map = jsonDecode(raw);
        if (map is Map<String, dynamic>) {
          final article = NewsArticle.fromJson(map);
          if (article.url.isNotEmpty) {
            loaded.add(article);
          }
        }
      } catch (e) {
        debugPrint('Error decoding favourite article: $e');
      }
    }

    _favourites = loaded;
    notifyListeners();
    return _favourites;
  }

  /// Loads bookmarked articles from SharedPreferences.
  /// Handles missing, empty, or corrupted JSON safely.
  Future<List<NewsArticle>> loadBookmarks() async {
    final prefs = await _getPrefs();
    final jsonStrings = prefs.getStringList(_bookmarksKey) ?? [];

    final List<NewsArticle> loaded = [];
    for (final raw in jsonStrings) {
      try {
        final map = jsonDecode(raw);
        if (map is Map<String, dynamic>) {
          final article = NewsArticle.fromJson(map);
          if (article.url.isNotEmpty) {
            loaded.add(article);
          }
        }
      } catch (e) {
        debugPrint('Error decoding bookmark article: $e');
      }
    }

    _bookmarks = loaded;
    notifyListeners();
    return _bookmarks;
  }

  /// Checks whether an article URL is in favourites.
  bool isFavourite(String articleUrl) {
    final normalized = NewsArticle.normalizeUrl(articleUrl);
    return _favourites.any((item) => item.normalizedUrl == normalized);
  }

  /// Checks whether an article URL is in bookmarks.
  bool isBookmarked(String articleUrl) {
    final normalized = NewsArticle.normalizeUrl(articleUrl);
    return _bookmarks.any((item) => item.normalizedUrl == normalized);
  }

  /// Toggles the favourite state of [article].
  /// Returns `true` if added, `false` if removed.
  Future<bool> toggleFavourite(NewsArticle article) async {
    if (isFavourite(article.url)) {
      await removeFavourite(article.url);
      return false;
    } else {
      await addFavourite(article);
      return true;
    }
  }

  /// Toggles the bookmark state of [article].
  /// Returns `true` if added, `false` if removed.
  Future<bool> toggleBookmark(NewsArticle article) async {
    if (isBookmarked(article.url)) {
      await removeBookmark(article.url);
      return false;
    } else {
      await addBookmark(article);
      return true;
    }
  }

  /// Adds [article] to favourites, preventing duplicates.
  Future<void> addFavourite(NewsArticle article) async {
    final normalized = article.normalizedUrl;
    if (normalized.isEmpty) return;

    // Prevent duplicate entries
    _favourites.removeWhere((item) => item.normalizedUrl == normalized);
    _favourites.insert(0, article); // Most recently favourited on top

    await _persistFavourites();
    notifyListeners();
  }

  /// Removes an article from favourites by its URL.
  Future<void> removeFavourite(String articleUrl) async {
    final normalized = NewsArticle.normalizeUrl(articleUrl);
    _favourites.removeWhere((item) => item.normalizedUrl == normalized);

    await _persistFavourites();
    notifyListeners();
  }

  /// Adds [article] to bookmarks, preventing duplicates.
  Future<void> addBookmark(NewsArticle article) async {
    final normalized = article.normalizedUrl;
    if (normalized.isEmpty) return;

    // Prevent duplicate entries
    _bookmarks.removeWhere((item) => item.normalizedUrl == normalized);
    _bookmarks.insert(0, article); // Most recently bookmarked on top

    await _persistBookmarks();
    notifyListeners();
  }

  /// Removes an article from bookmarks by its URL.
  Future<void> removeBookmark(String articleUrl) async {
    final normalized = NewsArticle.normalizeUrl(articleUrl);
    _bookmarks.removeWhere((item) => item.normalizedUrl == normalized);

    await _persistBookmarks();
    notifyListeners();
  }

  /// Serializes and writes favourites to SharedPreferences.
  Future<void> _persistFavourites() async {
    final prefs = await _getPrefs();
    final jsonList =
        _favourites.map((article) => jsonEncode(article.toJson())).toList();
    await prefs.setStringList(_favouritesKey, jsonList);
  }

  /// Serializes and writes bookmarks to SharedPreferences.
  Future<void> _persistBookmarks() async {
    final prefs = await _getPrefs();
    final jsonList =
        _bookmarks.map((article) => jsonEncode(article.toJson())).toList();
    await prefs.setStringList(_bookmarksKey, jsonList);
  }

  /// Resets in-memory lists (useful upon user logout).
  void clearInMemory() {
    _favourites = [];
    _bookmarks = [];
    _isInitialized = false;
    _userId = 'guest';
    notifyListeners();
  }
}
