import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/models/news_article.dart';

void main() {
  group('NewsArticle', () {
    test('correctly deserializes from complete GNews JSON', () {
      final json = {
        'title': 'Flutter 3.24 Released',
        'description': 'Exciting new features in Flutter.',
        'content': 'Flutter has released version 3.24 with amazing capabilities...',
        'url': 'https://example.com/flutter-update',
        'image': 'https://example.com/flutter.png',
        'publishedAt': '2026-10-26T12:00:00Z',
        'source': {
          'name': 'Tech Hub',
          'url': 'https://techhub.example.com',
        },
      };

      final article = NewsArticle.fromJson(json);

      expect(article.title, 'Flutter 3.24 Released');
      expect(article.description, 'Exciting new features in Flutter.');
      expect(article.content, contains('Flutter has released'));
      expect(article.url, 'https://example.com/flutter-update');
      expect(article.imageUrl, 'https://example.com/flutter.png');
      expect(article.hasValidImage, isTrue);
      expect(article.publishedAt, isNotNull);
      expect(article.sourceName, 'Tech Hub');
      expect(article.sourceUrl, 'https://techhub.example.com');
    });

    test('handles missing or null fields gracefully', () {
      final json = <String, dynamic>{
        'title': 'Minimal Article',
        'url': 'https://example.com/minimal',
      };

      final article = NewsArticle.fromJson(json);

      expect(article.title, 'Minimal Article');
      expect(article.description, isNull);
      expect(article.content, isNull);
      expect(article.imageUrl, isNull);
      expect(article.hasValidImage, isFalse);
      expect(article.publishedAt, isNull);
      expect(article.sourceName, 'Unknown Source');
      expect(article.timeAgo, '');
    });

    test('sanitizeUrl rejects invalid, malformed, or non-http URLs', () {
      expect(NewsArticle.sanitizeUrl('https://example.com/image.jpg'),
          'https://example.com/image.jpg');
      expect(NewsArticle.sanitizeUrl('http://example.com/image.png'),
          'http://example.com/image.png');
      expect(NewsArticle.sanitizeUrl(null), isNull);
      expect(NewsArticle.sanitizeUrl(''), isNull);
      expect(NewsArticle.sanitizeUrl('   '), isNull);
      expect(NewsArticle.sanitizeUrl('null'), isNull);
      expect(NewsArticle.sanitizeUrl('undefined'), isNull);
      expect(NewsArticle.sanitizeUrl('javascript:alert(1)'), isNull);
      expect(NewsArticle.sanitizeUrl('ftp://example.com/file'), isNull);
    });

    test('hasValidImage returns false for empty or invalid image strings', () {
      const articleWithInvalidImage = NewsArticle(
        title: 'Test',
        url: 'https://example.com',
        imageUrl: 'not-a-valid-url',
        sourceName: 'Source',
      );
      expect(articleWithInvalidImage.hasValidImage, isFalse);

      const articleWithValidImage = NewsArticle(
        title: 'Test',
        url: 'https://example.com',
        imageUrl: 'https://cdn.example.com/pic.jpg',
        sourceName: 'Source',
      );
      expect(articleWithValidImage.hasValidImage, isTrue);
    });

    test('formats relative timeAgo properly for recent articles', () {
      final now = DateTime.now().toUtc();
      final oneHourAgo = now.subtract(const Duration(hours: 1));

      final article = NewsArticle(
        title: 'Breaking News',
        url: 'https://example.com',
        sourceName: 'Daily Post',
        publishedAt: oneHourAgo,
      );

      expect(article.timeAgo, contains('hour'));
    });

    test('formats timeAgo for future timestamps gracefully as Just now', () {
      final futureDate = DateTime.now().toUtc().add(const Duration(minutes: 5));
      final article = NewsArticle(
        title: 'Future Story',
        url: 'https://example.com',
        sourceName: 'Daily Post',
        publishedAt: futureDate,
      );

      expect(article.timeAgo, 'Just now');
    });
  });
}
