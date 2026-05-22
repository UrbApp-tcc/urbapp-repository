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

  String get authorLabel {
    if (isAnonymous) return 'Usuário Anônimo';
    final name = authorDisplayName.trim();
    if (name.isNotEmpty) return name;
    final username = authorUsername?.trim();
    if (username != null && username.isNotEmpty) return username;
    return 'Usuário';
  }

  FeedPost copyWith({
    int? supportsCount,
    int? commentsCount,
  }) {
    return FeedPost(
      id: id,
      title: title,
      description: description,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      resolvedAt: resolvedAt,
      latitude: latitude,
      longitude: longitude,
      cityId: cityId,
      cityName: cityName,
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
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _postImagesBucket = 'post-images';

  Future<List<FeedPost>> fetchFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_feed_posts',
        params: {
          'page_size': limit,
          'page_offset': offset,
        },
      );

      return (response as List<dynamic>)
          .map((item) => _mapFeedPost(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar a lista de reportes: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar a lista de reportes.');
    }
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
      throw Exception('Erro ao carregar contagem de comentários: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar contagem de comentários.');
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
      throw Exception('Erro ao carregar likes do usuário: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar likes do usuário.');
    }
  }

  FeedPost _mapFeedPost(Map<String, dynamic> data) {
    final imageItems = (data['images'] as List<dynamic>? ?? const [])
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => FeedImage(
            id: item['id'] as int,
            storagePath: item['storage_path'] as String,
            publicUrl: _resolveImageUrl(item['storage_path'] as String?),
            caption: item['caption'] as String?,
            position: item['position'] as int,
          ),
        )
        .toList();

    return FeedPost(
      id: data['id'] as int,
      title: (data['title'] as String?) ?? 'Sem título',
      description: (data['description'] as String?) ?? '',
      status: data['status'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: _parseDate(data['updated_at']),
      resolvedAt: _parseDate(data['resolved_at']),
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      cityId: (data['city_id'] as num?)?.toInt() ?? 0,
      cityName: (data['city_name'] as String?) ?? 'Cidade desconhecida',
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

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }

  String? _resolveImageUrl(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) return null;
    return _supabase.storage.from(_postImagesBucket).getPublicUrl(storagePath);
  }
}
