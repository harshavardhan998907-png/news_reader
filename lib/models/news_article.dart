/// Represents a news article returned by the GNews API or loaded from local storage.
class NewsArticle {
  final String title;
  final String? description;
  final String? content;
  final String url;
  final String? imageUrl;
  final DateTime? publishedAt;
  final String sourceName;
  final String? sourceUrl;

  const NewsArticle({
    required this.title,
    this.description,
    this.content,
    required this.url,
    this.imageUrl,
    this.publishedAt,
    required this.sourceName,
    this.sourceUrl,
  });

  /// Normalizes an article URL to serve as a stable identifier.
  /// Trims whitespace and removes trailing slashes.
  static String normalizeUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    while (trimmed.endsWith('/') && trimmed.length > 1) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Returns the normalized URL for this article.
  String get normalizedUrl => normalizeUrl(url);

  /// Validates and sanitizes a URL string.
  /// Rejects null, empty, "null", "undefined", or non-HTTP/HTTPS URLs.
  static String? sanitizeUrl(dynamic rawUrl) {
    if (rawUrl is! String) return null;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'null' ||
        trimmed.toLowerCase() == 'undefined') {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }
    return trimmed;
  }

  /// Whether the article has a valid, loadable web image URL.
  bool get hasValidImage =>
      imageUrl != null && imageUrl!.trim().isNotEmpty && sanitizeUrl(imageUrl) != null;

  /// Factory constructor to parse GNews API JSON response or locally saved JSON.
  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    if (json['publishedAt'] != null) {
      try {
        parsedDate = DateTime.tryParse(json['publishedAt'] as String);
      } catch (_) {
        parsedDate = null;
      }
    }

    String sourceName = 'Unknown Source';
    String? sourceUrl;
    if (json['source'] is Map<String, dynamic>) {
      final sourceMap = json['source'] as Map<String, dynamic>;
      sourceName = (sourceMap['name'] as String?)?.trim().isNotEmpty == true
          ? (sourceMap['name'] as String).trim()
          : 'Unknown Source';
      sourceUrl = sanitizeUrl(sourceMap['url']);
    } else if (json['sourceName'] is String &&
        (json['sourceName'] as String).trim().isNotEmpty) {
      sourceName = (json['sourceName'] as String).trim();
      sourceUrl = sanitizeUrl(json['sourceUrl']);
    }

    final rawImage = json['image'] ?? json['imageUrl'];
    final sanitizedImage = sanitizeUrl(rawImage);

    final rawTitle = json['title'] as String?;
    final cleanTitle = (rawTitle != null && rawTitle.trim().isNotEmpty)
        ? rawTitle.trim()
        : 'No title available';

    final rawUrl = json['url'] as String? ?? '';

    return NewsArticle(
      title: cleanTitle,
      description: (json['description'] as String?)?.trim(),
      content: (json['content'] as String?)?.trim(),
      url: rawUrl.trim(),
      imageUrl: sanitizedImage,
      publishedAt: parsedDate,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
    );
  }

  /// Serializes the article into a JSON-compatible Map for local storage.
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'content': content,
      'url': url,
      'image': imageUrl,
      'publishedAt': publishedAt?.toIso8601String(),
      'source': {
        'name': sourceName,
        'url': sourceUrl,
      },
    };
  }

  /// User-friendly relative time or formatted date string.
  String get timeAgo {
    if (publishedAt == null) return '';
    final difference = DateTime.now().toUtc().difference(publishedAt!.toUtc());

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final m = difference.inMinutes;
      return '$m ${m == 1 ? 'min' : 'mins'} ago';
    } else if (difference.inHours < 24) {
      final h = difference.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final d = difference.inDays;
      return '$d ${d == 1 ? 'day' : 'days'} ago';
    } else {
      final date = publishedAt!.toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewsArticle &&
          runtimeType == other.runtimeType &&
          normalizedUrl == other.normalizedUrl;

  @override
  int get hashCode => normalizedUrl.hashCode;
}
