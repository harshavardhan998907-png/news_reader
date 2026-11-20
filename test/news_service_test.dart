
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:news_reader/models/news_article.dart';
import 'package:news_reader/services/news_service.dart';

class MockHttpClient extends http.BaseClient {
  final int statusCode;
  final List<Uri> requestedUris = [];
  final Future<void> Function()? onRequest;

  MockHttpClient({
    this.statusCode = 200,
    this.onRequest,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUris.add(request.url);

    if (onRequest != null) {
      await onRequest!();
    }

    final body = jsonEncode({
      'status': 'ok',
      'news': [
        {
          'id': 'test-article-1',
          'title': 'Test Headline',
          'description': 'Test description',
          'content': 'Test content',
          'url': 'https://example.com/test-article',
          'author': 'Test Author',
          'image': 'https://example.com/image.jpg',
          'language': 'en',
          'category': ['technology'],
          'published': '2026-10-31T12:00:00Z',
        }
      ],
    });

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  setUp(() {
    NewsService.clearCache();
    NewsService.minRequestInterval = Duration.zero;
    NewsService.minRefreshCooldown = Duration.zero;
  });

  tearDown(() {
    NewsService.clearCache();
  });

  group('NewsService - India and International Headlines', () {
    test('fetchIndiaHeadlines uses Currents latest-news endpoint', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchIndiaHeadlines();

      expect(mockClient.requestedUris.length, 1);

      final uri = mockClient.requestedUris.first;

      expect(uri.path, contains('/latest-news'));
      expect(uri.queryParameters['country'], 'IN');
      expect(uri.queryParameters['language'], 'en');
      expect(uri.queryParameters['category'], 'general');
      expect(uri.queryParameters['page_size'], '20');
      expect(uri.queryParameters.containsKey('apiKey'), isTrue);
    });

    test('fetchIndiaHeadlines passes selected category and country', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchIndiaHeadlines(category: 'technology');

      final uri = mockClient.requestedUris.first;

      expect(uri.queryParameters['category'], 'technology');
      expect(uri.queryParameters['country'], 'IN');
      expect(uri.queryParameters['language'], 'en');
    });

    test('fetchInternationalHeadlines general uses world category', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchInternationalHeadlines(category: 'general');

      final uri = mockClient.requestedUris.first;

      expect(uri.path, contains('/latest-news'));
      expect(uri.queryParameters['category'], 'world');
      expect(uri.queryParameters['language'], 'en');
      expect(uri.queryParameters.containsKey('country'), isFalse);
    });

    test('fetchInternationalHeadlines passes specific category globally', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchInternationalHeadlines(category: 'science');

      final uri = mockClient.requestedUris.first;

      expect(uri.queryParameters['category'], 'science');
      expect(uri.queryParameters['language'], 'en');
      expect(uri.queryParameters.containsKey('country'), isFalse);
    });

    test('politics category uses Currents keyword search', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchIndiaHeadlines(category: 'politics');
      await newsService.fetchInternationalHeadlines(category: 'politics');

      expect(mockClient.requestedUris.length, 2);

      final indiaUri = mockClient.requestedUris[0];

      expect(indiaUri.path, contains('/search'));
      expect(indiaUri.queryParameters['keywords'], 'politics');
      expect(indiaUri.queryParameters['country'], 'IN');

      final internationalUri = mockClient.requestedUris[1];

      expect(internationalUri.path, contains('/search'));
      expect(internationalUri.queryParameters['keywords'], 'world politics');
      expect(internationalUri.queryParameters.containsKey('country'), isFalse);
    });

    test('duplicate prevention filters repeated international articles', () {
      final indiaArticles = [
        const NewsArticle(
          title: 'ISRO Launch Success',
          url: 'https://news.example.com/isro-launch/',
          sourceName: 'India News',
        ),
        const NewsArticle(
          title: 'India Economy Growth',
          url: 'https://news.example.com/india-economy',
          sourceName: 'Daily Express',
        ),
      ];

      final internationalArticles = [
        const NewsArticle(
          title: 'ISRO Launch Success (Global)',
          url: 'https://news.example.com/isro-launch',
          sourceName: 'Global Wire',
        ),
        const NewsArticle(
          title: 'Global Summit in Tokyo',
          url: 'https://news.example.com/tokyo-summit',
          sourceName: 'World Times',
        ),
      ];

      final indiaUrls =
          indiaArticles.map((a) => a.normalizedUrl).toSet();

      final filteredInternational = internationalArticles
          .where((a) => !indiaUrls.contains(a.normalizedUrl))
          .toList();

      expect(filteredInternational.length, 1);
      expect(filteredInternational.first.title, 'Global Summit in Tokyo');
    });
  });

  group('NewsService - Currents JSON Parsing', () {
    test('parses Currents news response correctly', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      final articles = await newsService.fetchIndiaHeadlines();

      expect(articles.length, 1);
      expect(articles.first.title, 'Test Headline');
      expect(articles.first.description, 'Test description');
      expect(articles.first.url, 'https://example.com/test-article');
      expect(articles.first.sourceName, 'example.com');
      expect(articles.first.publishedAt, isNotNull);
    });
  });

  group('NewsService - In-Memory Caching', () {
    test('subsequent calls return cached articles without new HTTP calls', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      final firstResult = await newsService.fetchIndiaHeadlines();

      expect(mockClient.requestedUris.length, 1);
      expect(firstResult.isNotEmpty, isTrue);

      final secondResult = await newsService.fetchIndiaHeadlines();

      expect(mockClient.requestedUris.length, 1);
      expect(secondResult.length, firstResult.length);
      expect(secondResult.first.title, firstResult.first.title);
    });

    test('forceRefresh bypasses cache when cooldown has elapsed', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchIndiaHeadlines();

      expect(mockClient.requestedUris.length, 1);

      await newsService.fetchIndiaHeadlines(forceRefresh: true);

      expect(mockClient.requestedUris.length, 2);
    });

    test('category switching reuses cached results', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      await newsService.fetchIndiaHeadlines(category: 'general');

      await newsService.fetchIndiaHeadlines(category: 'business');

      expect(mockClient.requestedUris.length, 2);

      await newsService.fetchIndiaHeadlines(category: 'general');

      expect(mockClient.requestedUris.length, 2);
    });
  });

  group('NewsService - In-Flight Request Deduplication', () {
    test('concurrent requests coalesce into one HTTP request', () async {
      final mockClient = MockHttpClient(
        onRequest: () async {
          await Future.delayed(const Duration(milliseconds: 50));
        },
      );

      final newsService = NewsService(client: mockClient);

      final results = await Future.wait([
        newsService.fetchIndiaHeadlines(),
        newsService.fetchIndiaHeadlines(),
        newsService.fetchIndiaHeadlines(),
      ]);

      expect(mockClient.requestedUris.length, 1);
      expect(results[0].length, results[1].length);
      expect(results[1].length, results[2].length);
    });
  });

  group('NewsService - HTTP 429 Rate Limiting', () {
    test('HTTP 429 activates rate limit cooldown', () async {
      final mockClient = MockHttpClient(statusCode: 429);
      final newsService = NewsService(client: mockClient);

      expect(NewsService.isRateLimited, isFalse);

      await expectLater(
        newsService.fetchIndiaHeadlines(),
        throwsA(
          isA<NewsApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );

      expect(NewsService.isRateLimited, isTrue);
      expect(NewsService.remainingCooldownSeconds, greaterThan(0));
    });

    test('cached articles are returned during rate limit cooldown', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      final cachedArticles =
          await newsService.fetchIndiaHeadlines();

      expect(cachedArticles.isNotEmpty, isTrue);

      NewsService.setRateLimited(
        cooldown: const Duration(seconds: 30),
      );

      final fallbackArticles =
          await newsService.fetchIndiaHeadlines(forceRefresh: true);

      expect(fallbackArticles.length, cachedArticles.length);
      expect(fallbackArticles.first.title, cachedArticles.first.title);
      expect(mockClient.requestedUris.length, 1);
    });

    test('blocks requests while rate limited without cached data', () async {
      final mockClient = MockHttpClient();
      final newsService = NewsService(client: mockClient);

      NewsService.setRateLimited(
        cooldown: const Duration(seconds: 30),
      );

      await expectLater(
        newsService.fetchIndiaHeadlines(),
        throwsA(
          isA<NewsApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );

      expect(mockClient.requestedUris.isEmpty, isTrue);
    });
  });
}
