import 'package:supabase_flutter/supabase_flutter.dart';

class FeedImage {
  const FeedImage({
    required this.id,
    required this.storagePath,
    required this.position,
    this.publicUrl,
    this.caption,
  });

  final int id;
  final String storagePath;
  final int position;
  final String? publicUrl;
  final String? caption;
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    required this.latitude,
    required this.longitude,
    required this.cityId,
    required this.cityName,
    this.street,
    this.neighborhood,
    required this.categoryId,
    required this.categoryName,
    this.agencyId,
    this.agencyName,
    required this.supportsCount,
    required this.commentsCount,
    required this.isAnonymous,
    this.authorId,
    required this.authorDisplayName,
    this.authorUsername,
    this.authorAvatarUrl,
    required this.imageCount,
    this.primaryImageUrl,
    required this.images,
  });

  final int id;
  final String title;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final double latitude;
  final double longitude;
  final int cityId;
  final String cityName;
  final String? street;
  final String? neighborhood;
  final int categoryId;
  final String categoryName;
  final int? agencyId;
  final String? agencyName;
  final int supportsCount;
  final int commentsCount;
  final bool isAnonymous;
  final String? authorId;
  final String authorDisplayName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final int imageCount;
  final String? primaryImageUrl;
  final List<FeedImage> images;

  String get addressLabel {
    return [
      street?.trim() ?? '',
      neighborhood?.trim() ?? '',
      cityName.trim(),
    ].where((part) => part.isNotEmpty).toSet().join(' - ');
  }

  String get authorLabel {
    if (isAnonymous) return 'Usuario Anonimo';
    final name = authorDisplayName.trim();
    if (name.isNotEmpty) return name;
    final username = authorUsername?.trim();
    if (username != null && username.isNotEmpty) return username;
    return 'Usuario';
  }

  FeedPost copyWith({
    String? status,
    DateTime? updatedAt,
    DateTime? resolvedAt,
    int? supportsCount,
    int? commentsCount,
  }) {
    return FeedPost(
      id: id,
      title: title,
      description: description,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      latitude: latitude,
      longitude: longitude,
      cityId: cityId,
      cityName: cityName,
      street: street,
      neighborhood: neighborhood,
      categoryId: categoryId,
      categoryName: categoryName,
      agencyId: agencyId,
      agencyName: agencyName,
      supportsCount: supportsCount ?? this.supportsCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isAnonymous: isAnonymous,
      authorId: authorId,
      authorDisplayName: authorDisplayName,
      authorUsername: authorUsername,
      authorAvatarUrl: authorAvatarUrl,
      imageCount: imageCount,
      primaryImageUrl: primaryImageUrl,
      images: images,
    );
  }
}

class FeedService {
  FeedService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  static const String _postImagesBucket = 'post-images';

  Future<List<FeedPost>> fetchFeed({
    int limit = 20,
    int offset = 0,
    int? cityId,
    int? categoryId,
    String? status,
  }) async {
    try {
      return await _fetchDirectFeed(
        limit: limit,
        offset: offset,
        cityId: cityId,
        categoryId: categoryId,
        status: status,
        includeAddress: true,
      );
    } on PostgrestException catch (error) {
      if (error.code == '42703') {
        return _fetchDirectFeed(
          limit: limit,
          offset: offset,
          cityId: cityId,
          categoryId: categoryId,
          status: status,
          includeAddress: false,
        );
      }
      throw Exception('Erro ao carregar a lista de reportes: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar a lista de reportes.');
    }
  }

  Future<List<FeedPost>> fetchTrendingFeed({
    int limit = 20,
    int offset = 0,
    int? cityId,
  }) async {
    if (cityId != null) {
      return _fetchTrendingFeedFallback(
        limit: limit,
        offset: offset,
        cityId: cityId,
      );
    }

    try {
      final response = await _supabase.rpc(
        'get_trending_feed_posts',
        params: {'page_size': limit, 'page_offset': offset},
      );

      return (response as List<dynamic>)
          .map((item) => _mapFeedPost(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      if (_shouldUseTrendingFallback(error)) {
        return _fetchTrendingFeedFallback(
          limit: limit,
          offset: offset,
          cityId: cityId,
        );
      }
      throw Exception(
        'Erro ao carregar a lista de reportes em alta: ${error.message}',
      );
    } catch (_) {
      throw Exception(
        'Erro inesperado ao carregar a lista de reportes em alta.',
      );
    }
  }

  Future<List<FeedPost>> _fetchTrendingFeedFallback({
    required int limit,
    required int offset,
    int? cityId,
  }) async {
    final candidatePosts = await fetchFeed(
      limit: 100,
      offset: 0,
      cityId: cityId,
    );
    if (candidatePosts.isEmpty) return const <FeedPost>[];

    final postIds = candidatePosts.map((post) => post.id).toList();
    final authorIds = candidatePosts
        .map((post) => post.authorId)
        .whereType<String>()
        .toSet()
        .toList();

    final statusChangedAtByPostId = await _fetchLatestStatusChangedAt(postIds);
    final followersByAuthorId = await _fetchFollowersCountByAuthorId(authorIds);

    final scoredPosts =
        candidatePosts
            .map(
              (post) => (
                post: post,
                score: _calculateTrendingScore(
                  post,
                  followersCount: followersByAuthorId[post.authorId] ?? 0,
                  statusChangedAt: statusChangedAtByPostId[post.id],
                ),
                statusChangedAt:
                    statusChangedAtByPostId[post.id] ?? post.createdAt,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            if (byScore != 0) return byScore;

            final byComments = b.post.commentsCount.compareTo(
              a.post.commentsCount,
            );
            if (byComments != 0) return byComments;

            final bySupports = b.post.supportsCount.compareTo(
              a.post.supportsCount,
            );
            if (bySupports != 0) return bySupports;

            final byStatusAge = a.statusChangedAt.compareTo(b.statusChangedAt);
            if (byStatusAge != 0) return byStatusAge;

            final byCreatedAt = b.post.createdAt.compareTo(a.post.createdAt);
            if (byCreatedAt != 0) return byCreatedAt;

            return b.post.id.compareTo(a.post.id);
          });

    return scoredPosts
        .skip(offset)
        .take(limit)
        .map((entry) => entry.post)
        .toList();
  }

  Future<List<FeedPost>> fetchAllCityPosts({
    required int cityId,
    int? categoryId,
    String? status,
    int pageSize = 100,
  }) async {
    final posts = <FeedPost>[];
    var offset = 0;

    while (true) {
      final page = await fetchFeed(
        limit: pageSize,
        offset: offset,
        cityId: cityId,
        categoryId: categoryId,
        status: status,
      );
      posts.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }

    return posts;
  }

  Future<List<FeedPost>> _fetchDirectFeed({
    required int limit,
    required int offset,
    required int? cityId,
    required int? categoryId,
    required String? status,
    required bool includeAddress,
  }) async {
    var query = _supabase.from('post_feed_rows').select();

    if (cityId != null) {
      query = query.eq('city_id', cityId);
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List<dynamic>)
        .map((item) => _mapFeedPost(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<int, int>> fetchCommentCounts(List<int> postIds) async {
    if (postIds.isEmpty) return const <int, int>{};

    try {
      final entries = await Future.wait(
        postIds.map((postId) async {
          final response = await _supabase
              .from('comments')
              .select()
              .eq('post_id', postId)
              .count(CountOption.exact);
          return MapEntry(postId, response.count);
        }),
      );
      return Map.fromEntries(entries);
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao carregar contagem de comentarios: ${error.message}',
      );
    } catch (_) {
      throw Exception('Erro inesperado ao carregar contagem de comentarios.');
    }
  }

  Future<Set<int>> fetchLikedPostIds(List<int> postIds) async {
    if (postIds.isEmpty) return <int>{};

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return <int>{};

    try {
      final response = await _supabase
          .from('post_supports')
          .select('post_id')
          .eq('user_id', userId)
          .inFilter('post_id', postIds);

      return (response as List<dynamic>)
          .map((item) => (item['post_id'] as num).toInt())
          .toSet();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar likes do usuario: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar likes do usuario.');
    }
  }

  Future<Map<int, DateTime>> _fetchLatestStatusChangedAt(
    List<int> postIds,
  ) async {
    if (postIds.isEmpty) return const <int, DateTime>{};

    try {
      final response = await _supabase
          .from('post_status_history')
          .select('post_id, created_at')
          .inFilter('post_id', postIds)
          .order('created_at', ascending: false);

      final latestByPostId = <int, DateTime>{};
      for (final item in response as List<dynamic>) {
        final data = item as Map<String, dynamic>;
        final postId = (data['post_id'] as num).toInt();
        latestByPostId.putIfAbsent(
          postId,
          () => DateTime.parse(data['created_at'] as String),
        );
      }
      return latestByPostId;
    } on PostgrestException catch (error) {
      if (_isMissingStatusHistoryFeature(error)) {
        return const <int, DateTime>{};
      }
      rethrow;
    }
  }

  Future<Map<String, int>> _fetchFollowersCountByAuthorId(
    List<String> authorIds,
  ) async {
    if (authorIds.isEmpty) return const <String, int>{};

    try {
      final response = await _supabase
          .from('profile_followers')
          .select('followed_id')
          .inFilter('followed_id', authorIds);

      final counts = <String, int>{};
      for (final item in response as List<dynamic>) {
        final authorId =
            (item as Map<String, dynamic>)['followed_id'] as String;
        counts.update(authorId, (count) => count + 1, ifAbsent: () => 1);
      }
      return counts;
    } on PostgrestException catch (error) {
      if (_isMissingFollowersFeature(error)) {
        return const <String, int>{};
      }
      rethrow;
    }
  }

  int _calculateTrendingScore(
    FeedPost post, {
    required int followersCount,
    required DateTime? statusChangedAt,
  }) {
    final changedAt = (statusChangedAt ?? post.createdAt).toUtc();
    final hoursInCurrentStatus =
        DateTime.now().toUtc().difference(changedAt).inMilliseconds /
        Duration.millisecondsPerHour;

    final cappedHours = hoursInCurrentStatus.clamp(
      0,
      _statusAgeCapHours(post.status),
    );
    final agingScore = (cappedHours * _statusAgeWeight(post.status)).floor();

    return post.supportsCount * 18 +
        post.commentsCount * 24 +
        (post.supportsCount + post.commentsCount) * 6 +
        followersCount * 5 +
        _statusBaseScore(post.status) +
        agingScore;
  }

  int _statusBaseScore(String status) {
    switch (status) {
      case 'open':
        return 80;
      case 'in_analysis':
        return 90;
      case 'in_progress':
        return 70;
      case 'awaiting_validation':
        return 100;
      case 'reopened':
        return 95;
      case 'completed':
        return 30;
      case 'closed':
        return 20;
      case 'expired':
        return 10;
      default:
        return 0;
    }
  }

  double _statusAgeCapHours(String status) {
    switch (status) {
      case 'open':
      case 'in_analysis':
        return 24 * 30;
      case 'in_progress':
        return 24 * 21;
      case 'awaiting_validation':
        return 72;
      case 'reopened':
        return 24 * 30;
      case 'completed':
      case 'closed':
        return 24 * 7;
      default:
        return 24 * 3;
    }
  }

  double _statusAgeWeight(String status) {
    switch (status) {
      case 'open':
      case 'in_analysis':
        return 0.90;
      case 'in_progress':
        return 0.60;
      case 'awaiting_validation':
        return 0.20;
      case 'reopened':
        return 0.90;
      case 'completed':
      case 'closed':
        return 0.15;
      default:
        return 0.08;
    }
  }

  bool _shouldUseTrendingFallback(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        (message.contains('get_trending_feed_posts') &&
            message.contains('schema cache'));
  }

  bool _isMissingFollowersFeature(PostgrestException error) {
    return error.code == '42P01';
  }

  bool _isMissingStatusHistoryFeature(PostgrestException error) {
    return error.code == '42P01';
  }

  FeedPost _mapFeedPost(Map<String, dynamic> data) {
    final rawImages = data['images'];
    final imageList = rawImages is List
        ? rawImages
        : (rawImages is String ? [] : const []);
    final imageItems = imageList
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => FeedImage(
            id: (item['id'] as num).toInt(),
            storagePath: item['storage_path'] as String,
            publicUrl: _resolveImageUrl(item['storage_path'] as String?),
            caption: item['caption'] as String?,
            position: (item['position'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    return FeedPost(
      id: data['id'] as int,
      title: (data['title'] as String?) ?? 'Sem titulo',
      description: (data['description'] as String?) ?? '',
      status: data['status'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: _parseDate(data['updated_at']),
      resolvedAt: _parseDate(data['resolved_at']),
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      cityId: (data['city_id'] as num?)?.toInt() ?? 0,
      cityName: (data['city_name'] as String?) ?? 'Cidade desconhecida',
      street: data['street'] as String?,
      neighborhood: data['neighborhood'] as String?,
      categoryId: (data['category_id'] as num?)?.toInt() ?? 0,
      categoryName: (data['category_name'] as String?) ?? 'Categoria',
      agencyId: (data['agency_id'] as num?)?.toInt(),
      agencyName: data['agency_name'] as String?,
      supportsCount: (data['supports_count'] as num?)?.toInt() ?? 0,
      commentsCount: (data['comments_count'] as num?)?.toInt() ?? 0,
      isAnonymous: data['is_anonymous'] as bool? ?? false,
      authorId: data['author_id'] as String?,
      authorDisplayName: (data['author_display_name'] as String?) ?? '',
      authorUsername: data['author_username'] as String?,
      authorAvatarUrl: data['author_avatar_url'] as String?,
      imageCount: (data['image_count'] as num?)?.toInt() ?? 0,
      primaryImageUrl: _resolveImageUrl(data['primary_image_path'] as String?),
      images: imageItems,
    );
  }

  Future<FeedPost?> fetchPostById(int id) async {
    try {
      final response = await _supabase.rpc(
        'get_feed_posts',
        params: {'page_size': 100, 'page_offset': 0},
      );

      final list = response as List<dynamic>;
      final match = list
          .map((item) => item as Map<String, dynamic>)
          .where((item) => (item['id'] as num?)?.toInt() == id)
          .map(_mapFeedPost)
          .firstOrNull;

      if (match != null) return match;

      final row = await _supabase
          .from('post_feed_rows')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (row == null) return null;
      return _mapFeedPost(row);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }

  String? _resolveImageUrl(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) return null;
    return _supabase.storage.from(_postImagesBucket).getPublicUrl(storagePath);
  }
}
