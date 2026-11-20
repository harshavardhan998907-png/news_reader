
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/news_article.dart';

class NewsApiException implements Exception {
  final String message;
  final int? statusCode;

  NewsApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class CachedNewsArticles {
  final List<NewsArticle> articles;
  final DateTime timestamp;

  CachedNewsArticles(this.articles, this.timestamp);

  bool isFresh(Duration ttl) =>
      DateTime.now().difference(timestamp) < ttl;
}

class NewsService {
  final http.Client _client;

  NewsService({http.Client? client})
      : _client = client ?? http.Client();

  static final Map<String, CachedNewsArticles> _cache = {};
  static final Map<String, Future<List<NewsArticle>>> _inFlightRequests = {};

  static DateTime? _lastRequestTime;
  static DateTime? _rateLimitResetTime;

  static Duration minRequestInterval =
      const Duration(milliseconds: 1200);

  static Duration cacheTtl = const Duration(minutes: 5);
  static Duration minRefreshCooldown = const Duration(seconds: 15);
  static Duration rateLimitCooldown = const Duration(seconds: 60);

  static bool get isRateLimited {
    if (_rateLimitResetTime == null) return false;

    if (DateTime.now().isAfter(_rateLimitResetTime!)) {
      _rateLimitResetTime = null;
      return false;
    }

    return true;
  }

  static int get remainingCooldownSeconds {
    if (_rateLimitResetTime == null) return 0;

    final remaining =
        _rateLimitResetTime!.difference(DateTime.now()).inSeconds;

    return remaining > 0 ? remaining : 0;
  }

  static void setRateLimited({Duration? cooldown}) {
    _rateLimitResetTime =
        DateTime.now().add(cooldown ?? rateLimitCooldown);
  }

  static void resetRateLimit() {
    _rateLimitResetTime = null;
  }

  static void clearCache() {
    _cache.clear();
    _inFlightRequests.clear();
    _lastRequestTime = null;
    _rateLimitResetTime = null;
  }

  static List<NewsArticle>? getCachedArticles(String cacheKey) {
    return _cache[cacheKey]?.articles;
  }

  static bool hasFreshCache(String cacheKey) {
    final entry = _cache[cacheKey];
    return entry != null && entry.isFresh(cacheTtl);
  }

  void _validateApiKey() {
    if (!ApiConfig.hasApiKey) {
      throw NewsApiException(
        'Currents API key is not configured. '
        'Add your key in lib/config/api_config.dart.',
      );
    }
  }

  // Fetch category headlines, optionally filtered by country.
  Future<List<NewsArticle>> fetchTopHeadlines({
    String category = 'general',
    String? country,
    bool forceRefresh = false,
  }) async {
    _validateApiKey();

    final cat = category.toLowerCase().trim();

    // Currents does not use a dedicated politics category.
    if (cat == 'politics') {
      return searchNews(
        'politics',
        country: country,
        forceRefresh: forceRefresh,
      );
    }

    final countryCode = country?.trim().toUpperCase();
    final countryKey = countryCode ?? 'global';
    final cacheKey = 'top_${cat}_$countryKey';

    return _fetchWithCacheAndDeduplication(
      cacheKey: cacheKey,
      forceRefresh: forceRefresh,
      networkFetch: () {
        final params = <String, String>{
          'language': 'en',
          'category': cat,
          'page_size': '20',
          'apiKey': ApiConfig.apiKey,
        };

        if (countryCode != null && countryCode.isNotEmpty) {
          params['country'] = countryCode;
        }

        final uri = Uri.parse(
          '${ApiConfig.baseUrl}/latest-news',
        ).replace(queryParameters: params);

        return _getArticles(uri);
      },
    );
  }

  // Fetch India headlines.
  Future<List<NewsArticle>> fetchIndiaHeadlines({
    String category = 'general',
    bool forceRefresh = false,
  }) {
    return fetchTopHeadlines(
      category: category,
      country: 'IN',
      forceRefresh: forceRefresh,
    );
  }

  // Fetch international headlines.
  Future<List<NewsArticle>> fetchInternationalHeadlines({
    String category = 'general',
    bool forceRefresh = false,
  }) async {
    _validateApiKey();

    final cat = category.toLowerCase().trim();

    if (cat == 'politics') {
      return searchNews(
        'world politics',
        forceRefresh: forceRefresh,
      );
    }

    final effectiveCategory =
        cat == 'general' ? 'world' : cat;

    final cacheKey = 'intl_$effectiveCategory';

    return _fetchWithCacheAndDeduplication(
      cacheKey: cacheKey,
      forceRefresh: forceRefresh,
      networkFetch: () {
        final uri = Uri.parse(
          '${ApiConfig.baseUrl}/latest-news',
        ).replace(queryParameters: {
          'language': 'en',
          'category': effectiveCategory,
          'page_size': '20',
          'apiKey': ApiConfig.apiKey,
        });

        return _getArticles(uri);
      },
    );
  }

  // Search news by keyword.
  Future<List<NewsArticle>> searchNews(
    String query, {
    String? country,
    bool forceRefresh = false,
  }) async {
    _validateApiKey();

    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return fetchIndiaHeadlines(forceRefresh: forceRefresh);
    }

    final countryCode = country?.trim().toUpperCase();
    final countryKey = countryCode ?? 'global';

    final cacheKey =
        'search_${trimmed.toLowerCase()}_$countryKey';

    return _fetchWithCacheAndDeduplication(
      cacheKey: cacheKey,
      forceRefresh: forceRefresh,
      networkFetch: () {
        final params = <String, String>{
          'keywords': trimmed,
          'language': 'en',
          'page_size': '20',
          'apiKey': ApiConfig.apiKey,
        };

        if (countryCode != null && countryCode.isNotEmpty) {
          params['country'] = countryCode;
        }

        final uri = Uri.parse(
          '${ApiConfig.baseUrl}/search',
        ).replace(queryParameters: params);

        return _getArticles(uri);
      },
    );
  }

  // Cache, deduplicate and handle rate limits.
  Future<List<NewsArticle>> _fetchWithCacheAndDeduplication({
    required String cacheKey,
    required bool forceRefresh,
    required Future<List<NewsArticle>> Function() networkFetch,
  }) async {
    if (!forceRefresh) {
      final cached = _cache[cacheKey];

      if (cached != null && cached.isFresh(cacheTtl)) {
        return List<NewsArticle>.from(cached.articles);
      }
    }

    if (isRateLimited) {
      final cached = _cache[cacheKey];

      if (cached != null) {
        return List<NewsArticle>.from(cached.articles);
      }

      throw NewsApiException(
        'Currents API rate limit reached. '
        'Please wait $remainingCooldownSeconds seconds.',
        statusCode: 429,
      );
    }

    if (forceRefresh) {
      final cached = _cache[cacheKey];

      if (cached != null &&
          DateTime.now().difference(cached.timestamp) <
              minRefreshCooldown) {
        return List<NewsArticle>.from(cached.articles);
      }
    }

    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey]!;
    }

    final future = networkFetch();
    _inFlightRequests[cacheKey] = future;

    try {
      final articles = await future;

      _cache[cacheKey] =
          CachedNewsArticles(articles, DateTime.now());

      return List<NewsArticle>.from(articles);
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  // Make request and convert Currents JSON into NewsArticle objects.
  Future<List<NewsArticle>> _getArticles(Uri uri) async {
    if (minRequestInterval > Duration.zero &&
        _lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);

      if (elapsed < minRequestInterval) {
        await Future.delayed(minRequestInterval - elapsed);
      }
    }

    _lastRequestTime = DateTime.now();

    final requestUri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        '_cb': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    try {
      final response = await _client.get(requestUri).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          throw NewsApiException(
            'Unexpected response from Currents API.',
          );
        }

        if (decoded['status'] == 'error') {
          throw NewsApiException(
            decoded['message']?.toString() ??
                decoded['msg']?.toString() ??
                'Currents API returned an error.',
          );
        }

        final List<dynamic>? newsJson =
            decoded['news'] as List<dynamic>?;

        if (newsJson == null || newsJson.isEmpty) {
          return [];
        }

        return newsJson
            .whereType<Map<String, dynamic>>()
            .map((item) {
              // Convert Currents fields to the existing model format.
              final articleUrl =
                  item['url']?.toString() ?? '';

              String sourceName = 'Unknown Source';
              String? sourceUrl;

              final parsedUri = Uri.tryParse(articleUrl);

              if (parsedUri != null &&
                  parsedUri.host.isNotEmpty) {
                sourceName = parsedUri.host
                    .replaceFirst('www.', '');
                sourceUrl = parsedUri.origin;
              }

              return NewsArticle.fromJson({
                'title': item['title'],
                'description': item['description'],
                'content': item['content'],
                'url': articleUrl,
                'image': item['image'],
                'publishedAt': item['published'],
                'source': {
                  'name': sourceName,
                  'url': sourceUrl,
                },
              });
            })
            .where((article) =>
                article.title.isNotEmpty &&
                article.url.isNotEmpty)
            .toList();
      }

      String serverError = '';

      try {
        final errorData = jsonDecode(response.body);

        if (errorData is Map) {
          serverError =
              errorData['message']?.toString() ??
              errorData['msg']?.toString() ??
              errorData['error']?.toString() ??
              '';
        }
      } catch (_) {
        // Use the default error message below.
      }

      switch (response.statusCode) {
        case 400:
          throw NewsApiException(
            serverError.isNotEmpty
                ? serverError
                : 'Invalid Currents API request.',
            statusCode: 400,
          );

        case 401:
          throw NewsApiException(
            'Invalid Currents API key. Check api_config.dart.',
            statusCode: 401,
          );

        case 403:
          throw NewsApiException(
            serverError.isNotEmpty
                ? serverError
                : 'Currents API access is forbidden.',
            statusCode: 403,
          );

        case 429:
          _rateLimitResetTime =
              DateTime.now().add(rateLimitCooldown);

          throw NewsApiException(
            serverError.isNotEmpty
                ? serverError
                : 'Currents API request limit reached. '
                    'Please wait before trying again.',
            statusCode: 429,
          );

        case 500:
        case 502:
        case 503:
          throw NewsApiException(
            'Currents server temporarily unavailable. '
            'Please try again later.',
            statusCode: response.statusCode,
          );

        default:
          throw NewsApiException(
            serverError.isNotEmpty
                ? serverError
                : 'Failed to fetch news. '
                    'Status: ${response.statusCode}',
            statusCode: response.statusCode,
          );
      }
    } on SocketException {
      throw NewsApiException(
        'No internet connection. Please check your network.',
      );
    } on http.ClientException catch (e) {
      if (e.message.contains('XMLHttpRequest error') ||
          e.message.contains('Failed to fetch')) {
        throw NewsApiException(
          'Network or CORS error while connecting to Currents API.',
        );
      }

      throw NewsApiException(
        'Network error occurred while fetching news.',
      );
    } on FormatException {
      throw NewsApiException(
        'Received invalid JSON from Currents API.',
      );
    } on NewsApiException {
      rethrow;
    } catch (e) {
      final error = e.toString();

      if (error.contains('TimeoutException')) {
        throw NewsApiException(
          'Request timed out. Please try again.',
        );
      }

      throw NewsApiException(
        'Unexpected error occurred: $e',
      );
    }
  }
}
