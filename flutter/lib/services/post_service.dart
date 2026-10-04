import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/app_rules.dart';
import 'agency_service.dart';

class LookupOption {
  const LookupOption({required this.id, required this.name, this.stateCode});

  final int id;
  final String name;
  final String? stateCode;
}

class PotentialDuplicateOccurrence {
  const PotentialDuplicateOccurrence({
    required this.occurrenceId,
    required this.title,
    required this.summary,
    required this.status,
    required this.distanceKm,
    required this.textMatch,
    required this.reportsCount,
  });

  final int occurrenceId;
  final String title;
  final String summary;
  final String status;
  final double distanceKm;
  final bool textMatch;
  final int reportsCount;
}

class ResolutionCycleInfo {
  const ResolutionCycleInfo({
    required this.id,
    required this.occurrenceId,
    required this.initiatedBy,
    required this.status,
    required this.openedAt,
    required this.expiresAt,
    required this.confirmations,
    required this.rejections,
    required this.confirmationsRequired,
    required this.rejectionsRequired,
  });

  final int id;
  final int occurrenceId;
  final String initiatedBy;
  final String status;
  final DateTime openedAt;
  final DateTime expiresAt;
  final int confirmations;
  final int rejections;
  final int confirmationsRequired;
  final int rejectionsRequired;
}

class ResolutionVoteResult {
  const ResolutionVoteResult({
    required this.cycleStatus,
    required this.confirmations,
    required this.rejections,
    required this.confirmationsRequired,
    required this.rejectionsRequired,
  });

  final String cycleStatus;
  final int confirmations;
  final int rejections;
  final int confirmationsRequired;
  final int rejectionsRequired;
}

class OccurrenceTimelineEvent {
  const OccurrenceTimelineEvent({
    required this.id,
    required this.actorKind,
    required this.eventType,
    required this.description,
    required this.createdAt,
    this.evidenceUrl,
  });

  final int id;
  final String actorKind;
  final String eventType;
  final String description;
  final DateTime createdAt;
  final String? evidenceUrl;
}

class OccurrenceEngagementContext {
  const OccurrenceEngagementContext({
    required this.occurrenceId,
    required this.isFollowing,
    required this.reportsCount,
  });

  final int occurrenceId;
  final bool isFollowing;
  final int reportsCount;
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
    return 'Usuario';
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
  PostService({SupabaseClient? supabase, AgencyService? agencyService})
    : _supabase = supabase ?? Supabase.instance.client,
      _agencyService = agencyService ?? AgencyService();

  final SupabaseClient _supabase;
  final AgencyService _agencyService;
  static const String _postImagesBucket = 'post-images';

  Future<List<LookupOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name, state')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
              stateCode: item['state'] as String?,
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

  Future<List<AgencyOption>> fetchAgenciesByCity(int cityId) =>
      _agencyService.fetchAgenciesByCity(cityId);

  Future<int> createPost({
    required String userId,
    required int cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    String? street,
    String? neighborhood,
    int? agencyId,
    bool isAnonymous = false,
  }) async {
    try {
      await _supabase.rpc('ensure_my_profile');

      final response = await _supabase.rpc(
        'create_occurrence_report',
        params: {
          'target_city_id': cityId,
          'target_category_id': categoryId,
          'report_title': title.trim(),
          'report_description': description.trim(),
          'report_latitude': latitude,
          'report_longitude': longitude,
          'report_street': _nullIfEmpty(street),
          'report_neighborhood': _nullIfEmpty(neighborhood),
          'report_anonymous': isAnonymous,
        },
      );

      final rows = response as List<dynamic>;
      if (rows.isEmpty) {
        throw Exception('O banco nao retornou o reporte criado.');
      }
      return ((rows.first as Map<String, dynamic>)['post_id'] as num).toInt();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao criar o reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao criar o reporte: $error');
    }
  }

  Future<List<PotentialDuplicateOccurrence>> findPotentialDuplicates({
    required int cityId,
    required int categoryId,
    required double latitude,
    required double longitude,
    required String text,
  }) async {
    try {
      final response = await _supabase.rpc(
        'find_potential_duplicate_occurrences',
        params: {
          'target_city_id': cityId,
          'target_category_id': categoryId,
          'target_latitude': latitude,
          'target_longitude': longitude,
          'target_text': text.trim(),
          'maximum_distance_km': 1,
        },
      );

      return (response as List<dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .map(
            (item) => PotentialDuplicateOccurrence(
              occurrenceId: (item['occurrence_id'] as num).toInt(),
              title: (item['title'] as String?) ?? 'Ocorrencia urbana',
              summary: (item['summary'] as String?) ?? '',
              status: item['status'] as String,
              distanceKm: (item['distance_km'] as num).toDouble(),
              textMatch: item['text_match'] as bool? ?? false,
              reportsCount: (item['reports_count'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao procurar ocorrencias semelhantes: ${error.message}',
      );
    }
  }

  Future<int> addReportToOccurrence({
    required int occurrenceId,
    required String title,
    required String description,
    required bool isAnonymous,
  }) async {
    try {
      final response = await _supabase.rpc(
        'add_report_to_occurrence',
        params: {
          'target_occurrence_id': occurrenceId,
          'report_title': title.trim(),
          'report_description': description.trim(),
          'report_anonymous': isAnonymous,
        },
      );
      return (response as num).toInt();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao adicionar relato: ${error.message}');
    }
  }

  String? _nullIfEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> deletePost(int postId) async {
    try {
      await _supabase.from('posts').delete().eq('id', postId);
    } on PostgrestException catch (error) {
      throw Exception('Erro ao excluir o reporte: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao excluir o reporte: $error');
    }
  }

  Future<void> uploadPostImages({
    required int postId,
    required List<XFile> files,
  }) async {
    try {
      final imageFiles = files.where(_isImageFile).toList();
      if (imageFiles.isEmpty) return;

      for (var index = 0; index < imageFiles.length; index++) {
        final image = imageFiles[index];
        final bytes = await image.readAsBytes();
        final extension = _fileExtension(image.name);
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        final storagePath = 'reports/$postId/$fileName';

        await _supabase.storage
            .from(_postImagesBucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                upsert: false,
                contentType: _mimeFromExtension(extension),
              ),
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

  Future<LookupOption?> findCityByName({
    required String cityName,
    String? stateCode,
  }) async {
    final normalizedName = _normalizeText(cityName);
    if (normalizedName.isEmpty) return null;

    try {
      var query = _supabase.from('cities').select('id, name, state');
      if (stateCode != null && stateCode.isNotEmpty) {
        query = query.eq('state', stateCode);
      }

      final response = await query.limit(200);
      final cities = (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
              stateCode: item['state'] as String?,
            ),
          )
          .toList();

      LookupOption? partialMatch;
      for (final city in cities) {
        final normalizedCityName = _normalizeText(city.name);
        if (normalizedCityName == normalizedName) {
          return city;
        }

        if (normalizedCityName.contains(normalizedName) ||
            normalizedName.contains(normalizedCityName)) {
          partialMatch ??= city;
        }
      }

      return partialMatch;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao localizar cidade: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao localizar cidade: $error');
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
      throw Exception('Erro ao carregar comentarios: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar comentarios.');
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
      throw Exception('Erro ao enviar comentario: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao enviar comentario: $error');
    }
  }

  Future<void> toggleCommentLike({
    required int commentId,
    required bool isLiked,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Faca login para curtir comentarios.');
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
        'Erro ao registrar curtida no comentario: ${error.message}',
      );
    } catch (error) {
      throw Exception(
        'Erro inesperado ao registrar curtida no comentario: $error',
      );
    }
  }

  /// Toggles the support (like) on a post and returns the new liked state.
  /// Throws if [currentUserId] matches [postAuthorId] (self-support).
  /// Throws if [postStatus] is a final status.
  Future<bool> toggleSupport({
    required int postId,
    required String currentUserId,
    required String? postAuthorId,
    required bool isCurrentlyLiked,
    required String postStatus,
  }) async {
    if (postAuthorId != null && isSelfSupport(currentUserId, postAuthorId)) {
      throw Exception('Você não pode apoiar o próprio reporte.');
    }
    if (isFinalStatus(postStatus)) {
      throw Exception(
        'Este reporte está encerrado e não aceita novas interações.',
      );
    }

    try {
      if (isCurrentlyLiked) {
        await _supabase
            .from('post_supports')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', currentUserId);
        return false;
      } else {
        await _supabase.from('post_supports').insert({
          'post_id': postId,
          'user_id': currentUserId,
        });
        return true;
      }
    } on PostgrestException catch (error) {
      throw Exception('Erro ao registrar apoio: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao registrar apoio: $error');
    }
  }

  Future<int> openResolutionCycle({
    required int postId,
    required String note,
    String initiatorKind = 'citizen',
    XFile? evidence,
  }) async {
    String? uploadedEvidencePath;
    try {
      final post = await _supabase
          .from('posts')
          .select('occurrence_id')
          .eq('id', postId)
          .single();
      final occurrenceId = (post['occurrence_id'] as num?)?.toInt();
      if (occurrenceId == null) {
        throw Exception(
          'Este reporte ainda nao esta vinculado a uma ocorrencia.',
        );
      }

      if (evidence != null) {
        if (!_isImageFile(evidence)) {
          throw Exception('Selecione uma imagem válida como evidência.');
        }
        final extension = _fileExtension(evidence.name);
        uploadedEvidencePath =
            'occurrences/$occurrenceId/resolution/'
            '${DateTime.now().microsecondsSinceEpoch}.$extension';
        await _supabase.storage
            .from(_postImagesBucket)
            .uploadBinary(
              uploadedEvidencePath,
              await evidence.readAsBytes(),
              fileOptions: FileOptions(
                upsert: false,
                contentType: _mimeFromExtension(extension),
              ),
            );
      }

      final response = await _supabase.rpc(
        'open_resolution_cycle_with_evidence',
        params: {
          'target_occurrence_id': occurrenceId,
          'resolution_description': note.trim(),
          'initiator_kind': initiatorKind,
          'evidence_storage_path': uploadedEvidencePath,
        },
      );
      return (response as num).toInt();
    } on PostgrestException catch (error) {
      if (uploadedEvidencePath != null) {
        try {
          await _supabase.storage.from(_postImagesBucket).remove([
            uploadedEvidencePath,
          ]);
        } catch (_) {
          // A falha principal da regra de negócio deve permanecer visível.
        }
      }
      throw Exception('Erro ao abrir validacao: ${error.message}');
    } on StorageException catch (error) {
      throw Exception('Erro ao enviar evidência: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao abrir validacao: $error');
    }
  }

  Future<ResolutionCycleInfo?> fetchActiveResolutionCycle(int postId) async {
    try {
      final post = await _supabase
          .from('posts')
          .select('occurrence_id')
          .eq('id', postId)
          .single();
      final occurrenceId = (post['occurrence_id'] as num?)?.toInt();
      if (occurrenceId == null) return null;

      await _supabase.rpc(
        'expire_resolution_cycles',
        params: {'target_occurrence_id': occurrenceId},
      );

      final response = await _supabase.rpc(
        'get_active_resolution_cycle',
        params: {'target_occurrence_id': occurrenceId},
      );
      final rows = response as List<dynamic>;
      if (rows.isEmpty) return null;
      final cycle = rows.first as Map<String, dynamic>;

      return ResolutionCycleInfo(
        id: (cycle['cycle_id'] as num).toInt(),
        occurrenceId: (cycle['occurrence_id'] as num).toInt(),
        initiatedBy: cycle['initiated_by'] as String,
        status: cycle['cycle_status'] as String,
        openedAt: DateTime.parse(cycle['opened_at'] as String),
        expiresAt: DateTime.parse(cycle['expires_at'] as String),
        confirmations: (cycle['confirmations'] as num).toInt(),
        rejections: (cycle['rejections'] as num).toInt(),
        confirmationsRequired: (cycle['confirmations_required'] as num).toInt(),
        rejectionsRequired: (cycle['rejections_required'] as num).toInt(),
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar validacao: ${error.message}');
    }
  }

  Future<ResolutionVoteResult> voteResolution({
    required int cycleId,
    required bool confirm,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _supabase.rpc(
        'vote_resolution_cycle',
        params: {
          'target_cycle_id': cycleId,
          'vote_decision': confirm ? 'confirm' : 'reject',
          'voter_latitude': latitude,
          'voter_longitude': longitude,
        },
      );
      final data = response as Map<String, dynamic>;
      return ResolutionVoteResult(
        cycleStatus: data['cycle_status'] as String,
        confirmations: (data['confirmations'] as num?)?.toInt() ?? 0,
        rejections: (data['rejections'] as num?)?.toInt() ?? 0,
        confirmationsRequired:
            (data['confirmations_required'] as num?)?.toInt() ?? 3,
        rejectionsRequired: (data['rejections_required'] as num?)?.toInt() ?? 2,
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao registrar validacao: ${error.message}');
    }
  }

  Future<List<OccurrenceTimelineEvent>> fetchOccurrenceTimeline(
    int postId,
  ) async {
    final post = await _supabase
        .from('posts')
        .select('occurrence_id')
        .eq('id', postId)
        .single();
    final occurrenceId = (post['occurrence_id'] as num?)?.toInt();
    if (occurrenceId == null) return const [];

    final response = await _supabase
        .from('occurrence_events')
        .select('id, actor_kind, event_type, description, metadata, created_at')
        .eq('occurrence_id', occurrenceId)
        .order('created_at');
    return (response as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .map((item) {
          final metadata = item['metadata'] as Map<String, dynamic>?;
          final evidencePath = metadata?['evidence_storage_path'] as String?;
          return OccurrenceTimelineEvent(
            id: (item['id'] as num).toInt(),
            actorKind: item['actor_kind'] as String,
            eventType: item['event_type'] as String,
            description: item['description'] as String,
            createdAt: DateTime.parse(item['created_at'] as String),
            evidenceUrl: evidencePath == null || evidencePath.trim().isEmpty
                ? null
                : _supabase.storage
                      .from(_postImagesBucket)
                      .getPublicUrl(evidencePath),
          );
        })
        .toList();
  }

  Future<OccurrenceEngagementContext?> fetchOccurrenceEngagement(
    int postId,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    final post = await _supabase
        .from('posts')
        .select('occurrence_id')
        .eq('id', postId)
        .single();
    final occurrenceId = (post['occurrence_id'] as num?)?.toInt();
    if (occurrenceId == null) return null;

    final reportsResponse = await _supabase
        .from('posts')
        .select('id')
        .eq('occurrence_id', occurrenceId)
        .count(CountOption.exact);

    var isFollowing = false;
    if (userId != null) {
      final following = await _supabase
          .from('occurrence_followers')
          .select('occurrence_id')
          .eq('occurrence_id', occurrenceId)
          .eq('user_id', userId)
          .maybeSingle();
      isFollowing = following != null;
    }

    return OccurrenceEngagementContext(
      occurrenceId: occurrenceId,
      isFollowing: isFollowing,
      reportsCount: reportsResponse.count,
    );
  }

  Future<bool> toggleOccurrenceFollowing({
    required int occurrenceId,
    required bool isFollowing,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Entre na sua conta para acompanhar a ocorrência.');
    }

    try {
      if (isFollowing) {
        await _supabase
            .from('occurrence_followers')
            .delete()
            .eq('occurrence_id', occurrenceId)
            .eq('user_id', userId);
        return false;
      }

      await _supabase.from('occurrence_followers').insert({
        'occurrence_id': occurrenceId,
        'user_id': userId,
      });
      return true;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao acompanhar ocorrência: ${error.message}');
    }
  }

  Future<String> uploadReopeningEvidence({
    required int occurrenceId,
    required XFile file,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Entre na sua conta para reabrir a ocorrência.');
    }
    if (!_isImageFile(file)) {
      throw Exception('Selecione uma imagem válida como nova evidência.');
    }

    final extension = _fileExtension(file.name);
    final storagePath =
        'occurrences/$occurrenceId/reopening/'
        '${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _supabase.storage
        .from(_postImagesBucket)
        .uploadBinary(
          storagePath,
          await file.readAsBytes(),
          fileOptions: FileOptions(
            upsert: false,
            contentType: _mimeFromExtension(extension),
          ),
        );
    return storagePath;
  }

  Future<void> reopenOccurrence({
    required int occurrenceId,
    required String description,
    required String evidenceStoragePath,
  }) async {
    try {
      await _supabase.rpc(
        'reopen_occurrence',
        params: {
          'target_occurrence_id': occurrenceId,
          'reopening_description': description.trim(),
          'evidence_storage_path': evidenceStoragePath,
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao reabrir ocorrência: ${error.message}');
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

  bool _isImageFile(XFile file) {
    final extension = _fileExtension(file.name);
    return {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'bin';
    return parts.last.toLowerCase();
  }

  String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  String _normalizeText(String value) {
    var normalized = value.trim().toLowerCase();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã£': 'a',
      'Ã¢': 'a',
      'Ã©': 'e',
      'Ãª': 'e',
      'Ã­': 'i',
      'Ã³': 'o',
      'Ã´': 'o',
      'Ãµ': 'o',
      'Ãº': 'u',
      'Ã§': 'c',
      'ÃƒÂ¡': 'a',
      'ÃƒÂ ': 'a',
      'ÃƒÂ£': 'a',
      'ÃƒÂ¢': 'a',
      'ÃƒÂ©': 'e',
      'ÃƒÂª': 'e',
      'ÃƒÂ­': 'i',
      'ÃƒÂ³': 'o',
      'ÃƒÂ´': 'o',
      'ÃƒÂµ': 'o',
      'ÃƒÂº': 'u',
      'ÃƒÂ§': 'c',
    };

    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });

    return normalized
        .replaceAll(RegExp(r'^municipio de\s+'), '')
        .replaceAll(RegExp(r'^cidade de\s+'), '')
        .replaceAll(RegExp(r'^estancia turistica de\s+'), '')
        .replaceAll(RegExp(r'\s*[-/]\s*[a-z]{2}$'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
