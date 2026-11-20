import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:news_reader/models/news_article.dart';
import 'package:news_reader/services/saved_articles_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NewsArticle sampleArticle1;
  late NewsArticle sampleArticle2;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    sampleArticle1 = const NewsArticle(
      title: 'AI Revolution in 2026',
      description: 'Breakthroughs in artificial intelligence.',
      content: 'Detailed content about AI models.',
      url: 'https://techtimes.com/ai-revolution/',
      imageUrl: 'https://techtimes.com/ai.png',
      sourceName: 'Tech Times',
      sourceUrl: 'https://techtimes.com',
    );

    sampleArticle2 = const NewsArticle(
      title: 'Global Climate Summit',
      description: 'World leaders discuss clean energy.',
      content: 'Summit highlights on renewable investments.',
      url: 'https://globalnews.org/climate-summit',
      imageUrl: 'https://globalnews.org/summit.jpg',
      sourceName: 'Global News',
      sourceUrl: 'https://globalnews.org',
    );
  });

  group('NewsArticle Serialization', () {
    test('toJson produces valid map and round-trips with fromJson', () {
      final jsonMap = sampleArticle1.toJson();
      expect(jsonMap['title'], sampleArticle1.title);
      expect(jsonMap['url'], sampleArticle1.url);
      expect(jsonMap['image'], sampleArticle1.imageUrl);
      expect(jsonMap['source']['name'], sampleArticle1.sourceName);

      final deserialized = NewsArticle.fromJson(jsonMap);
      expect(deserialized.title, sampleArticle1.title);
      expect(deserialized.url, sampleArticle1.url);
      expect(deserialized.imageUrl, sampleArticle1.imageUrl);
      expect(deserialized.sourceName, sampleArticle1.sourceName);
    });

    test('normalizeUrl removes trailing slashes and trims whitespace', () {
      expect(
        NewsArticle.normalizeUrl('  https://example.com/article/  '),
        'https://example.com/article',
      );
      expect(
        NewsArticle.normalizeUrl('https://example.com/article'),
        'https://example.com/article',
      );
    });
  });

  group('SavedArticlesService', () {
    test('adds and removes favourites correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'test_user_1');

      expect(service.isFavourite(sampleArticle1.url), isFalse);
      expect(service.favourites, isEmpty);

      // Add to favourites
      await service.addFavourite(sampleArticle1);
      expect(service.isFavourite(sampleArticle1.url), isTrue);
      expect(service.favourites.length, 1);
      expect(service.favourites.first.title, sampleArticle1.title);

      // Remove from favourites
      await service.removeFavourite(sampleArticle1.url);
      expect(service.isFavourite(sampleArticle1.url), isFalse);
      expect(service.favourites, isEmpty);
    });

    test('adds and removes bookmarks correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'test_user_1');

      expect(service.isBookmarked(sampleArticle1.url), isFalse);
      expect(service.bookmarks, isEmpty);

      // Add bookmark
      await service.addBookmark(sampleArticle1);
      expect(service.isBookmarked(sampleArticle1.url), isTrue);
      expect(service.bookmarks.length, 1);

      // Remove bookmark
      await service.removeBookmark(sampleArticle1.url);
      expect(service.isBookmarked(sampleArticle1.url), isFalse);
      expect(service.bookmarks, isEmpty);
    });

    test('prevents duplicate entries when added multiple times', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'test_user_1');

      await service.addFavourite(sampleArticle1);
      // Add again (different instance or trailing slash)
      final duplicate = NewsArticle(
        title: sampleArticle1.title,
        url: 'https://techtimes.com/ai-revolution', // normalized matches
        sourceName: sampleArticle1.sourceName,
      );
      await service.addFavourite(duplicate);

      expect(service.favourites.length, 1);
    });

    test('favourites and bookmarks remain strictly independent', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'test_user_1');

      // Add sampleArticle1 to favourites only
      await service.addFavourite(sampleArticle1);
      expect(service.isFavourite(sampleArticle1.url), isTrue);
      expect(service.isBookmarked(sampleArticle1.url), isFalse);

      // Add sampleArticle2 to bookmarks only
      await service.addBookmark(sampleArticle2);
      expect(service.isBookmarked(sampleArticle2.url), isTrue);
      expect(service.isFavourite(sampleArticle2.url), isFalse);

      // Removing favourite does not affect bookmarks
      await service.removeFavourite(sampleArticle1.url);
      expect(service.favourites, isEmpty);
      expect(service.bookmarks.length, 1);
      expect(service.isBookmarked(sampleArticle2.url), isTrue);
    });

    test('persists articles and reloads from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'persistent_user');

      await service.addFavourite(sampleArticle1);
      await service.addBookmark(sampleArticle2);

      // Create a new service instance reading the same SharedPreferences
      final reloadedService =
          SavedArticlesService.withPrefs(prefs, userId: 'persistent_user');
      await reloadedService.loadFavourites();
      await reloadedService.loadBookmarks();

      expect(reloadedService.isFavourite(sampleArticle1.url), isTrue);
      expect(reloadedService.isBookmarked(sampleArticle2.url), isTrue);
    });

    test('namespaces storage by user UID so different users do not share saved lists', () async {
      final prefs = await SharedPreferences.getInstance();

      final userAService =
          SavedArticlesService.withPrefs(prefs, userId: 'uid_alice');
      final userBService =
          SavedArticlesService.withPrefs(prefs, userId: 'uid_bob');

      await userAService.addFavourite(sampleArticle1);
      await userBService.addFavourite(sampleArticle2);

      expect(userAService.favourites.length, 1);
      expect(userAService.isFavourite(sampleArticle1.url), isTrue);
      expect(userAService.isFavourite(sampleArticle2.url), isFalse);

      expect(userBService.favourites.length, 1);
      expect(userBService.isFavourite(sampleArticle2.url), isTrue);
      expect(userBService.isFavourite(sampleArticle1.url), isFalse);
    });

    test('handles corrupted or invalid JSON in storage safely without crashing', () async {
      final prefs = await SharedPreferences.getInstance();
      // Inject corrupt JSON strings into storage
      await prefs.setStringList(
        'news_reader_favourites_corrupted_user',
        ['not-a-json', '{"empty": true}', '{"title": "Valid", "url": "https://valid.com"}'],
      );

      final service = SavedArticlesService.withPrefs(prefs, userId: 'corrupted_user');
      final loaded = await service.loadFavourites();

      expect(loaded.length, 1);
      expect(loaded.first.url, 'https://valid.com');
    });

    test('toggle methods switch state and return boolean indicator', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'toggle_user');

      // First toggle: adds
      final addedFav = await service.toggleFavourite(sampleArticle1);
      expect(addedFav, isTrue);
      expect(service.isFavourite(sampleArticle1.url), isTrue);

      // Second toggle: removes
      final removedFav = await service.toggleFavourite(sampleArticle1);
      expect(removedFav, isFalse);
      expect(service.isFavourite(sampleArticle1.url), isFalse);
    });

    test('clearInMemory resets state and switching user reloads separate data', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SavedArticlesService.withPrefs(prefs, userId: 'user_1');

      await service.addFavourite(sampleArticle1);
      expect(service.favourites.length, 1);

      // Logout triggers clearInMemory
      service.clearInMemory();
      expect(service.favourites, isEmpty);
      expect(service.bookmarks, isEmpty);
      expect(service.userId, 'guest');

      // User 2 logs in
      await service.init(userId: 'user_2');
      expect(service.favourites, isEmpty); // User 2 has no favourites yet

      await service.addFavourite(sampleArticle2);
      expect(service.favourites.length, 1);
      expect(service.isFavourite(sampleArticle2.url), isTrue);
      expect(service.isFavourite(sampleArticle1.url), isFalse);

      // User 1 logs back in
      service.clearInMemory();
      await service.init(userId: 'user_1');
      expect(service.favourites.length, 1);
      expect(service.isFavourite(sampleArticle1.url), isTrue);
      expect(service.isFavourite(sampleArticle2.url), isFalse);
    });
  });
}
