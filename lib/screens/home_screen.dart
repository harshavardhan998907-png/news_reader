import 'dart:async';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/news_article.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';
import '../services/saved_articles_service.dart';
import '../widgets/news_card.dart';
import 'article_details_screen.dart';
import 'bookmarks_screen.dart';
import 'favourites_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final NewsService _newsService = NewsService();
  final SavedArticlesService _savedService = SavedArticlesService();

  final TextEditingController _searchController = TextEditingController();

  // Supported news categories.
  // Note: GNews supports general, business, technology, entertainment, sports, science, health, world, nation.
  // For 'politics', NewsService queries political headlines via the search endpoint.
  static const List<Map<String, String>> _categories = [
    {'label': 'General', 'id': 'general'},
    {'label': 'Technology', 'id': 'technology'},
    {'label': 'Sports', 'id': 'sports'},
    {'label': 'Politics', 'id': 'politics'},
    {'label': 'Business', 'id': 'business'},
    {'label': 'Entertainment', 'id': 'entertainment'},
    {'label': 'Health', 'id': 'health'},
    {'label': 'Science', 'id': 'science'},
  ];

  int _currentTabIndex = 0;
  String _selectedCategory = 'general';
  bool _isLoggingOut = false;
  bool _isSearchActive = false;

  // Rate-limiting & refresh throttling
  Timer? _rateLimitTimer;
  DateTime? _lastPullToRefreshTime;
  static const Duration _minPullToRefreshInterval = Duration(seconds: 15);

  // India news state
  List<NewsArticle> _indiaArticles = [];
  bool _isIndiaLoading = false;
  String? _indiaError;

  // International news state
  List<NewsArticle> _rawInternationalArticles = [];
  List<NewsArticle> _internationalArticles = [];
  bool _isInternationalLoading = false;
  String? _internationalError;

  // Search state
  List<NewsArticle> _searchResults = [];
  bool _isSearchLoading = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    // Initialize saved articles namespaced by the authenticated user's UID
    _savedService.init(userId: _authService.currentUser?.uid);
    _loadNews();
  }

  @override
  void dispose() {
    _rateLimitTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Loads both India and International news sequentially, or executes a search if query is present.
  Future<void> _loadNews({bool forceRefresh = false}) async {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      await _performSearch(query, forceRefresh: forceRefresh);
    } else {
      // Load sequentially to prevent concurrent burst requests hitting the GNews 1 req/sec limit
      await _loadIndiaNews(forceRefresh: forceRefresh);
      await _loadInternationalNews(forceRefresh: forceRefresh);
    }
  }

  /// Fetches top headlines for India.
  Future<void> _loadIndiaNews({bool forceRefresh = false}) async {
    if (_indiaArticles.isEmpty) {
      setState(() {
        _isIndiaLoading = true;
        _indiaError = null;
      });
    }

    try {
      final fetched = await _newsService.fetchIndiaHeadlines(
        category: _selectedCategory,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _indiaArticles = _deduplicate(fetched);
          _isIndiaLoading = false;
          _indiaError = null;
          _filterInternationalDuplicates();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndiaLoading = false;
          if (_indiaArticles.isEmpty) {
            _indiaError = e.toString();
          } else {
            // Keep existing articles displayed on error and show friendly floating snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString()),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
        _checkRateLimitCooldown();
      }
    }
  }

  /// Fetches international/world headlines.
  Future<void> _loadInternationalNews({bool forceRefresh = false}) async {
    if (_internationalArticles.isEmpty) {
      setState(() {
        _isInternationalLoading = true;
        _internationalError = null;
      });
    }

    try {
      final fetched = await _newsService.fetchInternationalHeadlines(
        category: _selectedCategory,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _rawInternationalArticles = fetched;
          _filterInternationalDuplicates();
          _isInternationalLoading = false;
          _internationalError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInternationalLoading = false;
          if (_internationalArticles.isEmpty) {
            _internationalError = e.toString();
          } else {
            // Keep existing articles displayed on error and show friendly floating snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString()),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
        _checkRateLimitCooldown();
      }
    }
  }

  /// Triggers a live countdown ticker when rate-limited to update retry buttons every second.
  void _checkRateLimitCooldown() {
    if (NewsService.isRateLimited) {
      _rateLimitTimer?.cancel();
      _rateLimitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {}); // Updates the remaining seconds in the UI
        if (!NewsService.isRateLimited) {
          timer.cancel();
        }
      });
    }
  }

  /// Handles user-initiated pull-to-refresh with rate-limiting and minimum interval checks.
  Future<void> _onPullToRefresh() async {
    if (NewsService.isRateLimited) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'API rate-limited. Please wait ${NewsService.remainingCooldownSeconds}s before refreshing.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now();
    if (_lastPullToRefreshTime != null &&
        now.difference(_lastPullToRefreshTime!) < _minPullToRefreshInterval) {
      final remaining = _minPullToRefreshInterval.inSeconds -
          now.difference(_lastPullToRefreshTime!).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('News is up to date. You can refresh again in ${remaining}s.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _lastPullToRefreshTime = now;
    await _loadNews(forceRefresh: true);
  }

  /// Filters out any international article that already appears in the India news list
  /// using normalized article URLs.
  void _filterInternationalDuplicates() {
    final indiaUrls = _indiaArticles
        .map((a) => a.normalizedUrl)
        .where((u) => u.isNotEmpty)
        .toSet();

    _internationalArticles = _deduplicate(
      _rawInternationalArticles,
      existingUrls: indiaUrls,
    );
  }

  /// Helper to remove duplicate articles based on normalized URLs.
  List<NewsArticle> _deduplicate(
    List<NewsArticle> articles, {
    Set<String>? existingUrls,
  }) {
    final seen = existingUrls != null ? Set<String>.from(existingUrls) : <String>{};
    final unique = <NewsArticle>[];
    for (final article in articles) {
      final url = article.normalizedUrl;
      if (url.isNotEmpty) {
        if (seen.add(url)) {
          unique.add(article);
        }
      } else {
        unique.add(article);
      }
    }
    return unique;
  }

  /// Executes keyword search.
  Future<void> _performSearch(String query, {bool forceRefresh = false}) async {
    setState(() {
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final fetched = await _newsService.searchNews(query, forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _searchResults = _deduplicate(fetched);
          _isSearchLoading = false;
          _searchError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearchLoading = false;
        });
        _checkRateLimitCooldown();
      }
    }
  }

  /// Changes the category and re-loads both India and International sections.
  void _onCategorySelected(String categoryId) {
    if (_selectedCategory == categoryId && _searchController.text.isEmpty) {
      return;
    }

    setState(() {
      _selectedCategory = categoryId;
      _searchController.clear();
      _isSearchActive = false;
      _searchResults = [];
      _searchError = null;
    });

    _loadNews();
  }

  /// Submits the keyword search.
  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    _performSearch(query.trim());
  }

  /// Clears search text and restores the India First & International feed.
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearchActive = false;
      _searchResults = [];
      _searchError = null;
    });
    _loadNews();
  }

  /// Logout confirmation and execution.
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sign Out'),
        content: const Text('Are you sure you want to log out of News Reader?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      _savedService.clearInMemory();
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String get _appBarTitle {
    switch (_currentTabIndex) {
      case 1:
        return 'Favourites';
      case 2:
        return 'Bookmarks';
      case 0:
      default:
        return 'News Reader';
    }
  }

  IconData get _appBarIcon {
    switch (_currentTabIndex) {
      case 1:
        return Icons.favorite;
      case 2:
        return Icons.bookmark;
      case 0:
      default:
        return Icons.newspaper;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              _appBarIcon,
              size: 26,
              color: _currentTabIndex == 1
                  ? Colors.red
                  : (_currentTabIndex == 2
                      ? theme.colorScheme.primary
                      : null),
            ),
            const SizedBox(width: 8),
            Text(
              _appBarTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Toggle Search Bar (Only visible on Feed tab)
          if (_currentTabIndex == 0)
            IconButton(
              tooltip: _isSearchActive ? 'Close Search' : 'Search Articles',
              icon: Icon(_isSearchActive ? Icons.search_off : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearchActive = !_isSearchActive;
                  if (!_isSearchActive && _searchController.text.isNotEmpty) {
                    _clearSearch();
                  }
                });
              },
            ),
          // Logout Action
          IconButton(
            tooltip: 'Sign Out (${user?.email ?? "User"})',
            icon: _isLoggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            onPressed: _isLoggingOut ? null : _handleLogout,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildFeedTab(theme),
              const FavouritesScreen(),
              const BookmarksScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: Icon(Icons.newspaper),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite, color: Colors.red),
            label: 'Favourites',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
        ],
      ),
    );
  }

  Widget _buildFeedTab(ThemeData theme) {
    return Column(
      children: [
        // Search Input Bar (Visible when toggled or search has active text)
        if (_isSearchActive) _buildSearchBar(theme),

        // Categories Horizontal Scroll
        _buildCategoryBar(theme),

        // Active Filter Indicator
        _buildFilterIndicator(theme),

        // Feed Content
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onPullToRefresh,
            child: _buildFeedBody(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: theme.colorScheme.surface,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: _onSearchSubmitted,
        decoration: InputDecoration(
          hintText: 'Search news by keyword (e.g. AI, Climate, Football)...',
          prefixIcon: IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => _onSearchSubmitted(_searchController.text),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: _clearSearch,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) {
          setState(() {}); // Updates suffix clear icon visibility
        },
      ),
    );
  }

  Widget _buildCategoryBar(ThemeData theme) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected =
              _selectedCategory == cat['id'] && _searchController.text.isEmpty;

          return Center(
            child: FilterChip(
              label: Text(cat['label']!),
              selected: isSelected,
              showCheckmark: false,
              selectedColor: theme.colorScheme.primaryContainer,
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              onSelected: (_) => _onCategorySelected(cat['id']!),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterIndicator(ThemeData theme) {
    final query = _searchController.text.trim();
    final categoryLabel = _categories.firstWhere(
      (c) => c['id'] == _selectedCategory,
      orElse: () => {'label': _selectedCategory},
    )['label'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            query.isNotEmpty ? Icons.search : Icons.newspaper,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              query.isNotEmpty
                  ? 'Search results for "$query"'
                  : (_selectedCategory == 'general'
                      ? 'India & International Headlines'
                      : 'India & International • $categoryLabel'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (query.isNotEmpty)
            TextButton(
              onPressed: _clearSearch,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// Builds the body of the feed tab:
  /// - Search results list if a search query is active
  /// - Single scrollable dual-section feed (India first, International on scroll)
  Widget _buildFeedBody(ThemeData theme) {
    final query = _searchController.text.trim();

    // 1. Search Mode
    if (query.isNotEmpty) {
      if (_isSearchLoading) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Searching news...'),
            ],
          ),
        );
      }

      if (_searchError != null) {
        return _buildErrorState(
          theme,
          errorMessage: _searchError,
          onRetry: () => _performSearch(query, forceRefresh: true),
        );
      }

      if (_searchResults.isEmpty) {
        return _buildSearchEmptyState(theme, query);
      }

      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final article = _searchResults[index];
          return NewsCard(
            article: article,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ArticleDetailsScreen(article: article),
                ),
              );
            },
          );
        },
      );
    }

    // 2. Dual Feed Mode: India First, International on scroll
    final hasNoApiKey = !ApiConfig.hasApiKey;
    final bothFailed = _indiaError != null &&
        _internationalError != null &&
        _indiaArticles.isEmpty &&
        _internationalArticles.isEmpty;

    if (hasNoApiKey || bothFailed) {
      return _buildErrorState(
        theme,
        errorMessage: _indiaError ?? _internationalError,
        onRetry: () => _loadNews(forceRefresh: true),
      );
    }

    // Initial full-page loading spinner if neither section has articles yet
    if (_isIndiaLoading &&
        _isInternationalLoading &&
        _indiaArticles.isEmpty &&
        _internationalArticles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Fetching latest headlines...'),
          ],
        ),
      );
    }

    final categoryLabel = _categories.firstWhere(
      (c) => c['id'] == _selectedCategory,
      orElse: () => {'label': _selectedCategory},
    )['label'];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // --- SECTION 1: LATEST INDIA NEWS ---
        SliverToBoxAdapter(
          child: _buildSectionHeading(
            context: context,
            title: 'Latest India News',
            icon: Icons.location_on,
            subtitle: _selectedCategory == 'general'
                ? 'Top stories and breaking updates from India'
                : 'Top India headlines in $categoryLabel',
            badgeText: 'India',
            badgeColor: Colors.deepOrange,
            badgeTextColor: Colors.deepOrange.shade800,
          ),
        ),

        if (_isIndiaLoading && _indiaArticles.isEmpty)
          const SliverToBoxAdapter(
            child: _SectionLoadingIndicator(message: 'Loading India news...'),
          )
        else if (_indiaError != null && _indiaArticles.isEmpty)
          SliverToBoxAdapter(
            child: _buildSectionErrorCard(
              context: context,
              title: 'Unable to load India news',
              errorMessage: _indiaError!,
              onRetry: () => _loadIndiaNews(forceRefresh: true),
            ),
          )
        else if (_indiaArticles.isEmpty)
          SliverToBoxAdapter(
            child: _buildSectionEmptyCard(
              context,
              'No India stories found for this category at the moment.',
            ),
          )
        else
          SliverList.builder(
            itemCount: _indiaArticles.length,
            itemBuilder: (context, index) {
              final article = _indiaArticles[index];
              return NewsCard(
                article: article,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          ArticleDetailsScreen(article: article),
                    ),
                  );
                },
              );
            },
          ),

        // --- SECTION DIVIDER ---
        SliverToBoxAdapter(
          child: _buildSectionDivider(theme),
        ),

        // --- SECTION 2: INTERNATIONAL NEWS ---
        SliverToBoxAdapter(
          child: _buildSectionHeading(
            context: context,
            title: 'International News',
            icon: Icons.public,
            subtitle: _selectedCategory == 'general'
                ? 'World events and global headlines'
                : 'Global headlines in $categoryLabel',
            badgeText: 'World',
            badgeColor: theme.colorScheme.primary,
            badgeTextColor: theme.colorScheme.primary,
          ),
        ),

        if (_isInternationalLoading && _internationalArticles.isEmpty)
          const SliverToBoxAdapter(
            child:
                _SectionLoadingIndicator(message: 'Loading International news...'),
          )
        else if (_internationalError != null && _internationalArticles.isEmpty)
          SliverToBoxAdapter(
            child: _buildSectionErrorCard(
              context: context,
              title: 'Unable to load International news',
              errorMessage: _internationalError!,
              onRetry: () => _loadInternationalNews(forceRefresh: true),
            ),
          )
        else if (_internationalArticles.isEmpty)
          SliverToBoxAdapter(
            child: _buildSectionEmptyCard(
              context,
              'No international stories found for this category at the moment.',
            ),
          )
        else
          SliverList.builder(
            itemCount: _internationalArticles.length,
            itemBuilder: (context, index) {
              final article = _internationalArticles[index];
              return NewsCard(
                article: article,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          ArticleDetailsScreen(article: article),
                    ),
                  );
                },
              );
            },
          ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 24),
        ),
      ],
    );
  }

  /// Modern section header with icon, title, subtitle, and badge.
  Widget _buildSectionHeading({
    required BuildContext context,
    required String title,
    required IconData icon,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withAlpha(70)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Transition banner and divider between sections.
  Widget _buildSectionDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'GLOBAL COVERAGE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }  /// Inline error card with a retry button for a specific section.
  Widget _buildSectionErrorCard({
    required BuildContext context,
    required String title,
    required String errorMessage,
    required VoidCallback onRetry,
  }) {
    final theme = Theme.of(context);
    final isRateLimited = NewsService.isRateLimited;
    final cooldown = NewsService.remainingCooldownSeconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        color: theme.colorScheme.errorContainer.withAlpha(90),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.error.withAlpha(60)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isRateLimited ? Icons.hourglass_top : Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isRateLimited ? 'Rate Limit Active (HTTP 429)' : title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                errorMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: isRateLimited ? null : onRetry,
                  icon: isRateLimited
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(
                    isRateLimited ? 'Retry in ${cooldown}s' : 'Retry',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty card for a specific section when no articles are found.
  Widget _buildSectionEmptyCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 20, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-page error state for global errors (missing key, no network, etc.).
  Widget _buildErrorState(
    ThemeData theme, {
    String? errorMessage,
    required VoidCallback onRetry,
  }) {
    final isApiKeyMissing = !ApiConfig.hasApiKey;
    final isRateLimited = NewsService.isRateLimited;
    final cooldown = NewsService.remainingCooldownSeconds;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isApiKeyMissing
                      ? Icons.key_off_outlined
                      : (isRateLimited
                          ? Icons.hourglass_top
                          : Icons.wifi_off_outlined),
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  isApiKeyMissing
                      ? 'API Key Configuration Needed'
                      : (isRateLimited
                          ? 'Rate Limit Active (HTTP 429)'
                          : 'Unable to Load News'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage ?? 'An error occurred while loading news.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isRateLimited ? null : onRetry,
                  icon: isRateLimited
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    isRateLimited ? 'Please wait ${cooldown}s' : 'Try Again',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Empty state when a search yields 0 results.
  Widget _buildSearchEmptyState(ThemeData theme, String query) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No search results found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No articles match "$query". Check your spelling or try different keywords.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Clear Search & View Feed'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper widget to show a section-level progress indicator.
class _SectionLoadingIndicator extends StatelessWidget {
  final String message;

  const _SectionLoadingIndicator({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
