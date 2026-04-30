import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'agency_service.dart';

class LookupOption {
  const LookupOption({required this.id, required this.name});

  final int id;
  final String name;
}

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.updatedAt,
    this.parentCommentId,
    required this.authorDisplayName,
    this.authorUsername,
    this.authorAvatarUrl,
    this.likesCount = 0,
    this.isLiked = false,
    this.replies = const [],
  });

  final int id;
  final int postId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? parentCommentId;
  final String authorDisplayName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final int likesCount;
  final bool isLiked;
  final List<PostComment> replies;

  String get authorLabel {
    final fullName = authorDisplayName.trim();
    if (fullName.isNotEmpty) return fullName;
    final username = authorUsername?.trim();
    if (username != null && username.isNotEmpty) return username;
    return 'Usuário';
  }

  PostComment copyWith({
    int? id,
    int? postId,
    String? userId,
    String? body,
    DateTime? createdAt,
    Object? updatedAt = _sentinel,
    Object? parentCommentId = _sentinel,
    String? authorDisplayName,
    Object? authorUsername = _sentinel,
    Object? authorAvatarUrl = _sentinel,
    int? likesCount,
    bool? isLiked,
    List<PostComment>? replies,
  }) {
    return PostComment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: identical(updatedAt, _sentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
      parentCommentId: identical(parentCommentId, _sentinel)
          ? this.parentCommentId
          : parentCommentId as int?,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorUsername: identical(authorUsername, _sentinel)
          ? this.authorUsername
          : authorUsername as String?,
      authorAvatarUrl: identical(authorAvatarUrl, _sentinel)
          ? this.authorAvatarUrl
          : authorAvatarUrl as String?,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      replies: replies ?? this.replies,
    );
  }
}

const Object _sentinel = Object();

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _postImagesBucket = 'post-images';

  Future<List<LookupOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao buscar cidades: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar cidades.');
    }
  }

  Future<List<LookupOption>> fetchCategories() async {
    try {
      final response = await _supabase
          .from('problem_categories')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao buscar categorias: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar categorias.');
    }
  }

  Future<List<AgencyOption>> fetchAgenciesByCity(int cityId) async {
    final agencyService = AgencyService();
    return agencyService.fetchAgenciesByCity(cityId);
  }

  Future<int> createPost({
    required String userId,
    required int cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    int? agencyId,
    bool isAnonymous = false,
  }) async {
    try {
      await _supabase.rpc('ensure_my_profile');

      final response = await _supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'city_id': cityId,
            'category_id': categoryId,
            'agency_id': agencyId,
            'title': title.trim(),
            'description': description.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'anonymity': isAnonymous,
            'status': 'open',
          })
          .select('id')
          .single();

      return response['id'] as int;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao criar o reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao criar o reporte: $error');
    }
  }

  Future<void> createInitialStatusHistory({
    required int postId,
    required String userId,
  }) async {
    try {
      await _supabase.from('post_status_history').insert({
        'post_id': postId,
        'changed_by': userId,
        'from_status': null,
        'to_status': 'open',
        'note': 'Reporte criado pelo usuário.',
      });
    } on PostgrestException catch (error) {
      throw Exception('Erro ao criar histórico do reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao criar histórico do reporte: $error');
    }
  }

  Future<void> uploadPostImages({
    required String userId,
    required int postId,
    required List<PlatformFile> files,
  }) async {
    try {
      final imageFiles = files.where(_isImageFile).toList();
      if (imageFiles.isEmpty) return;

      for (var index = 0; index < imageFiles.length; index++) {
        final file = imageFiles[index];
        final bytes = _extractBytes(file);
        final extension = _fileExtension(file.name);
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        final storagePath = '$userId/posts/$postId/$fileName';

        await _supabase.storage
            .from(_postImagesBucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: const FileOptions(upsert: false),
            );

        await _supabase.from('post_images').insert({
          'post_id': postId,
          'storage_path': storagePath,
          'position': index + 1,
        });
      }
    } on StorageException catch (error) {
      throw Exception(
        'Erro ao enviar imagem para o armazenamento: ${error.message}',
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao salvar imagem do reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao salvar imagens do reporte: $error');
    }
  }

  Future<List<PostComment>> fetchComments(int postId) async {
    try {
      final response = await _supabase
          .from('comments')
          .select(
            'id, post_id, user_id, body, likes, created_at, updated_at, parent_comment_id, '
            'profiles!comments_user_id_fkey(full_name, username, avatar_url)',
          )
          .eq('post_id', postId)
          .order('created_at');

      final responseList = response as List<dynamic>;
      final likedIds = await _fetchLikedCommentIds(
        responseList
            .map(
              (item) => ((item as Map<String, dynamic>)['id'] as num).toInt(),
            )
            .toList(),
      );

      final flatComments = responseList
          .map((item) => _mapComment(item as Map<String, dynamic>, likedIds))
          .toList();

      return _buildCommentThread(flatComments);
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar comentários: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar comentários.');
    }
  }

  Future<PostComment> createComment({
    required int postId,
    required String userId,
    required String body,
    int? parentCommentId,
  }) async {
    try {
      await _supabase.rpc('ensure_my_profile');

      final response = await _supabase
          .from('comments')
          .insert({
            'post_id': postId,
            'user_id': userId,
            'body': body.trim(),
            'parent_comment_id': parentCommentId,
          })
          .select(
            'id, post_id, user_id, body, likes, created_at, updated_at, parent_comment_id, '
            'profiles!comments_user_id_fkey(full_name, username, avatar_url)',
          )
          .single();

      return _mapComment(response, const <int>{});
    } on PostgrestException catch (error) {
      throw Exception('Erro ao enviar comentário: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao enviar comentário: $error');
    }
  }

  Future<void> toggleCommentLike({
    required int commentId,
    required bool isLiked,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Faça login para curtir comentários.');
    }

    try {
      if (isLiked) {
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', userId);
      } else {
        await _supabase.from('comment_likes').insert({
          'comment_id': commentId,
          'user_id': userId,
        });
      }
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao registrar curtida no comentário: ${error.message}',
      );
    } catch (error) {
      throw Exception(
        'Erro inesperado ao registrar curtida no comentário: $error',
      );
    }
  }

  Future<void> resolvePost({
    required int postId,
    required String userId,
    required String fromStatus,
    required String note,
  }) async {
    final resolvedNote = note.trim();

    try {
      final resolvedAt = DateTime.now().toUtc().toIso8601String();

      final updatedPost = await _supabase
          .from('posts')
          .update({'status': 'completed', 'resolved_at': resolvedAt})
          .eq('id', postId)
          .eq('user_id', userId)
          .select('id')
          .maybeSingle();

      if (updatedPost == null) {
        throw Exception('Você não tem permissão para resolver este reporte.');
      }

      await _supabase.from('post_status_history').insert({
        'post_id': postId,
        'changed_by': userId,
        'from_status': fromStatus,
        'to_status': 'completed',
        'note': resolvedNote.isEmpty
            ? 'Reporte marcado como resolvido pelo autor.'
            : resolvedNote,
      });
    } on PostgrestException catch (error) {
      throw Exception('Erro ao resolver o reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao resolver o reporte: $error');
    }
  }

  Future<Set<int>> _fetchLikedCommentIds(List<int> commentIds) async {
    if (commentIds.isEmpty) return <int>{};

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return <int>{};

    final response = await _supabase
        .from('comment_likes')
        .select('comment_id')
        .eq('user_id', userId)
        .inFilter('comment_id', commentIds);

    return (response as List<dynamic>)
        .map((item) => (item['comment_id'] as num).toInt())
        .toSet();
  }

  List<PostComment> _buildCommentThread(List<PostComment> flatComments) {
    final commentsById = {
      for (final comment in flatComments) comment.id: comment,
    };
    final repliesByParent = <int, List<PostComment>>{};
    final topLevel = <PostComment>[];

    for (final comment in flatComments) {
      if (comment.parentCommentId == null) {
        topLevel.add(comment);
        continue;
      }

      final rootParentId = _resolveTopLevelParentId(comment, commentsById);
      repliesByParent
          .putIfAbsent(rootParentId, () => <PostComment>[])
          .add(comment);
    }

    return topLevel
        .map(
          (comment) => comment.copyWith(
            replies: repliesByParent[comment.id] ?? const <PostComment>[],
          ),
        )
        .toList();
  }

  int _resolveTopLevelParentId(
    PostComment comment,
    Map<int, PostComment> commentsById,
  ) {
    var currentParentId = comment.parentCommentId;

    while (currentParentId != null) {
      final parent = commentsById[currentParentId];
      if (parent == null) return currentParentId;
      if (parent.parentCommentId == null) return parent.id;
      currentParentId = parent.parentCommentId;
    }

    return comment.id;
  }

  bool _isImageFile(PlatformFile file) {
    final extension = _fileExtension(file.name);
    return {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'bin';
    return parts.last.toLowerCase();
  }

  Uint8List _extractBytes(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Não foi possível ler os bytes do arquivo ${file.name}.');
    }
    return bytes;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }

  PostComment _mapComment(Map<String, dynamic> data, Set<int> likedIds) {
    final profile = data['profiles'] as Map<String, dynamic>?;

    return PostComment(
      id: (data['id'] as num).toInt(),
      postId: (data['post_id'] as num).toInt(),
      userId: data['user_id'] as String,
      body: (data['body'] as String?) ?? '',
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: _parseDate(data['updated_at']),
      parentCommentId: (data['parent_comment_id'] as num?)?.toInt(),
      authorDisplayName: (profile?['full_name'] as String?) ?? '',
      authorUsername: profile?['username'] as String?,
      authorAvatarUrl: profile?['avatar_url'] as String?,
      likesCount: (data['likes'] as num?)?.toInt() ?? 0,
      isLiked: likedIds.contains((data['id'] as num).toInt()),
    );
  }
}
