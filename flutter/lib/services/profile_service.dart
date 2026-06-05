import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'feed_service.dart';

class ProfileCityOption {
  const ProfileCityOption({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class ProfileBadge {
  const ProfileBadge({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    this.icon,
    this.awardedAt,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String? icon;
  final DateTime? awardedAt;
}

class UserProfileData {
  const UserProfileData({
    required this.id,
    required this.fullName,
    required this.username,
    this.avatarUrl,
    this.cityId,
    this.cityName,
    required this.currentXp,
    required this.currentLevel,
    required this.currentPoints,
    required this.followersCount,
    required this.likesReceived,
    required this.isFollowing,
    this.featuredBadge,
    required this.badges,
    required this.posts,
  });

  final String id;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final int? cityId;
  final String? cityName;
  final int currentXp;
  final int currentLevel;
  final int currentPoints;
  final int followersCount;
  final int likesReceived;
  final bool isFollowing;
  final ProfileBadge? featuredBadge;
  final List<ProfileBadge> badges;
  final List<FeedPost> posts;

  int get xpIntoCurrentLevel => currentXp % 1000;
  int get xpToNextLevel => 1000 - xpIntoCurrentLevel;
}

class ProfileService {
  ProfileService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _postImagesBucket = 'post-images';
  static const String _profileImagesBucket = 'profile-images';

  Future<UserProfileData> fetchProfile({
    required String profileUserId,
    String? viewerUserId,
  }) async {
    try {
      if (viewerUserId == profileUserId) {
        await _supabase.rpc('ensure_my_profile');
      }

      final profileResponse = await _fetchProfileRow(profileUserId);
      final fullName = _resolveDisplayName(profileResponse);
      final username = (profileResponse['username'] as String?)?.trim() ?? 'usuario';
      final avatarUrl = profileResponse['avatar_url'] as String?;

      final posts = await _fetchProfilePosts(
        profileUserId: profileUserId,
        includeAnonymous: viewerUserId == profileUserId,
        authorDisplayName: fullName,
        authorUsername: username,
        authorAvatarUrl: avatarUrl,
      );

      final followersCount = await _fetchFollowersCountSafely(profileUserId);
      final isFollowing = await _fetchIsFollowingSafely(
        profileUserId: profileUserId,
        viewerUserId: viewerUserId,
      );
      final badges = await _fetchBadgesSafely(profileUserId);
      final likesReceived = posts.fold<int>(0, (sum, post) => sum + post.supportsCount);
      final city = _asMap(profileResponse['cities']);

      return UserProfileData(
        id: profileResponse['id'] as String,
        fullName: fullName,
        username: username,
        avatarUrl: avatarUrl,
        cityId: (profileResponse['city_id'] as num?)?.toInt(),
        cityName: city?['name'] as String?,
        currentXp: (profileResponse['current_xp'] as num?)?.toInt() ?? 0,
        currentLevel: (profileResponse['current_level'] as num?)?.toInt() ?? 1,
        currentPoints: (profileResponse['current_points'] as num?)?.toInt() ?? 0,
        followersCount: followersCount,
        likesReceived: likesReceived,
        isFollowing: isFollowing,
        featuredBadge: _mapBadge(profileResponse['badges']),
        badges: badges,
        posts: posts,
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar perfil: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao carregar perfil: $error');
    }
  }

  Future<List<ProfileCityOption>> fetchCities() async {
    final response = await _supabase.from('cities').select('id, name').order('name');

    return (response as List<dynamic>)
        .map(
          (item) => ProfileCityOption(
            id: (item['id'] as num).toInt(),
            name: item['name'] as String,
          ),
        )
        .toList();
  }

  Future<List<ProfileBadge>> fetchBadgeCatalog() async {
    try {
      final response = await _supabase
          .from('badges')
          .select('id, name, slug, description, icon')
          .order('id');

      return (response as List<dynamic>)
          .map((item) => _mapBadge(item))
          .whereType<ProfileBadge>()
          .toList();
    } on PostgrestException catch (error) {
      if (_isMissingOptionalProfileFeature(error)) return const <ProfileBadge>[];
      throw Exception('Erro ao carregar insignias: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao carregar insignias: $error');
    }
  }

  Future<void> updateProfile({
    required String userId,
    required String fullName,
    required String username,
    int? cityId,
    int? featuredBadgeId,
    String? avatarUrl,
  }) async {
    try {
      await _supabase.rpc('ensure_my_profile');

      final payload = {
        'full_name': fullName.trim(),
        'username': username.trim(),
        'city_id': cityId,
        'featured_badge_id': featuredBadgeId,
        ...?switch (avatarUrl) {
          final value? => {'avatar_url': value},
          null => null,
        },
      };

      await _supabase.from('profiles').update(payload).eq('id', userId);
    } on PostgrestException catch (error) {
      throw Exception('Erro ao atualizar perfil: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao atualizar perfil: $error');
    }
  }

  Future<String> uploadAvatar({
    required String userId,
    required PlatformFile file,
  }) async {
    try {
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Nao foi possivel ler a imagem selecionada.');
      }

      final extension = _fileExtension(file.name);
      final storagePath = '$userId/avatar/avatar.$extension';

      await _supabase.storage.from(_profileImagesBucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = _supabase.storage.from(_profileImagesBucket).getPublicUrl(storagePath);
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      return '$publicUrl?v=$cacheBuster';
    } on StorageException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('bucket') && message.contains('not found')) {
        throw Exception(
          'O bucket de fotos de perfil ainda nao existe no Supabase. '
          'Aplique a migration 20260419113000_add_profile_features.sql ou crie o bucket "profile-images".',
        );
      }

      throw Exception('Erro ao enviar avatar: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao enviar avatar: $error');
    }
  }

  Future<void> followProfile({
    required String viewerUserId,
    required String profileUserId,
  }) async {
    try {
      await _supabase.from('profile_followers').insert({
        'follower_id': viewerUserId,
        'followed_id': profileUserId,
      });
    } on PostgrestException catch (error) {
      if (_isMissingProfileFollowersFeature(error)) {
        throw Exception(
          'O recurso de seguir perfis ainda nao foi criado no Supabase. '
          'Aplique a migration 20260419113000_add_profile_features.sql.',
        );
      }

      throw Exception('Erro ao seguir usuario: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao seguir usuario: $error');
    }
  }

  Future<void> unfollowProfile({
    required String viewerUserId,
    required String profileUserId,
  }) async {
    try {
      await _supabase
          .from('profile_followers')
          .delete()
          .eq('follower_id', viewerUserId)
          .eq('followed_id', profileUserId);
    } on PostgrestException catch (error) {
      if (_isMissingProfileFollowersFeature(error)) {
        throw Exception(
          'O recurso de seguir perfis ainda nao foi criado no Supabase. '
          'Aplique a migration 20260419113000_add_profile_features.sql.',
        );
      }

      throw Exception('Erro ao deixar de seguir usuario: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao deixar de seguir usuario: $error');
    }
  }

  Future<List<ProfileBadge>> _fetchBadges(String userId) async {
    final response = await _supabase
        .from('user_badges')
        .select('awarded_at, badges(id, name, slug, description, icon)')
        .eq('user_id', userId)
        .order('awarded_at', ascending: false);

    return (response as List<dynamic>)
        .map((item) {
          final badge = _asMap(item['badges']);
          if (badge == null) return null;

          return ProfileBadge(
            id: (badge['id'] as num).toInt(),
            name: badge['name'] as String,
            slug: badge['slug'] as String,
            description: badge['description'] as String,
            icon: badge['icon'] as String?,
            awardedAt: DateTime.parse(item['awarded_at'] as String),
          );
        })
        .whereType<ProfileBadge>()
        .toList();
  }

  Future<List<ProfileBadge>> _fetchBadgesSafely(String userId) async {
    try {
      return await _fetchBadges(userId);
    } on PostgrestException catch (error) {
      if (_isMissingOptionalProfileFeature(error)) return const <ProfileBadge>[];
      rethrow;
    }
  }

  Future<int> _fetchFollowersCount(String userId) async {
    final response = await _supabase
        .from('profile_followers')
        .select('followed_id')
        .eq('followed_id', userId)
        .count(CountOption.exact);

    return response.count;
  }

  Future<int> _fetchFollowersCountSafely(String userId) async {
    try {
      return await _fetchFollowersCount(userId);
    } on PostgrestException catch (error) {
      if (_isMissingProfileFollowersFeature(error)) return 0;
      rethrow;
    }
  }

  Future<bool> _fetchIsFollowing({
    required String profileUserId,
    String? viewerUserId,
  }) async {
    if (viewerUserId == null || viewerUserId == profileUserId) return false;

    final response = await _supabase
        .from('profile_followers')
        .select('followed_id')
        .eq('followed_id', profileUserId)
        .eq('follower_id', viewerUserId)
        .maybeSingle();

    return response != null;
  }

  Future<bool> _fetchIsFollowingSafely({
    required String profileUserId,
    String? viewerUserId,
  }) async {
    try {
      return await _fetchIsFollowing(
        profileUserId: profileUserId,
        viewerUserId: viewerUserId,
      );
    } on PostgrestException catch (error) {
      if (_isMissingProfileFollowersFeature(error)) return false;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchProfileRow(String profileUserId) async {
    return await _supabase
        .from('profiles')
        .select('''
          id,
          full_name,
          username,
          avatar_url,
          city_id,
          current_xp,
          current_level,
          current_points,
          featured_badge_id,
          cities(name),
          badges!profiles_featured_badge_id_fkey(id, name, slug, description, icon)
        ''')
        .eq('id', profileUserId)
        .single();
  }

  Future<List<FeedPost>> _fetchProfilePosts({
    required String profileUserId,
    required bool includeAnonymous,
    required String authorDisplayName,
    required String authorUsername,
    String? authorAvatarUrl,
  }) async {
    var query = _supabase.from('posts').select('''
          id,
          title,
          description,
          status,
          created_at,
          updated_at,
          resolved_at,
          latitude,
          longitude,
          city_id,
          category_id,
          agency_id,
          supports_count,
          comments_count,
          anonymity,
          user_id,
          cities(name),
          problem_categories(name),
          public_agencies(name),
          post_images(id, storage_path, caption, position)
        ''').eq('user_id', profileUserId);

    if (!includeAnonymous) {
      query = query.eq('anonymity', false);
    }

    final response = await query.order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map(
          (item) => _mapProfilePost(
            item as Map<String, dynamic>,
            authorDisplayName: authorDisplayName,
            authorUsername: authorUsername,
            authorAvatarUrl: authorAvatarUrl,
          ),
        )
        .toList();
  }

  FeedPost _mapProfilePost(
    Map<String, dynamic> data, {
    required String authorDisplayName,
    required String authorUsername,
    String? authorAvatarUrl,
  }) {
    final imageItems = (data['post_images'] as List<dynamic>? ?? const [])
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
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final city = _asMap(data['cities']);
    final category = _asMap(data['problem_categories']);
    final agency = _asMap(data['public_agencies']);
    final isAnonymous = data['anonymity'] as bool? ?? false;

    return FeedPost(
      id: (data['id'] as num).toInt(),
      title: (data['title'] as String?) ?? 'Sem titulo',
      description: (data['description'] as String?) ?? '',
      status: data['status'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: _parseDate(data['updated_at']),
      resolvedAt: _parseDate(data['resolved_at']),
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      cityId: (data['city_id'] as num?)?.toInt() ?? 0,
      cityName: (city?['name'] as String?) ?? 'Cidade desconhecida',
      categoryId: (data['category_id'] as num?)?.toInt() ?? 0,
      categoryName: (category?['name'] as String?) ?? 'Categoria',
      agencyId: (data['agency_id'] as num?)?.toInt(),
      agencyName: agency?['name'] as String?,
      supportsCount: (data['supports_count'] as num?)?.toInt() ?? 0,
      commentsCount: (data['comments_count'] as num?)?.toInt() ?? 0,
      isAnonymous: isAnonymous,
      authorId: isAnonymous ? null : data['user_id'] as String?,
      authorDisplayName: isAnonymous ? 'Anonimo' : authorDisplayName,
      authorUsername: isAnonymous ? null : authorUsername,
      authorAvatarUrl: isAnonymous ? null : authorAvatarUrl,
      imageCount: imageItems.length,
      primaryImageUrl: imageItems.isNotEmpty ? imageItems.first.publicUrl : null,
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

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'jpg';
    return parts.last.toLowerCase();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is List && value.isNotEmpty) return _asMap(value.first);
    return null;
  }

  ProfileBadge? _mapBadge(dynamic rawValue) {
    final badge = _asMap(rawValue);
    if (badge == null) return null;

    return ProfileBadge(
      id: (badge['id'] as num).toInt(),
      name: badge['name'] as String,
      slug: badge['slug'] as String,
      description: badge['description'] as String,
      icon: badge['icon'] as String?,
    );
  }

  String _resolveDisplayName(Map<String, dynamic> profileResponse) {
    final fullName = (profileResponse['full_name'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;

    final username = (profileResponse['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) return username;

    return 'Usuario';
  }

  bool _isMissingOptionalProfileFeature(PostgrestException error) {
    // 42703 = undefined column, 42P01 = undefined table/relation
    return error.code == '42703' || error.code == '42P01';
  }

  bool _isMissingProfileFollowersFeature(PostgrestException error) {
    return error.code == '42P01';
  }
}
