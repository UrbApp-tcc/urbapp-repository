import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/labels.dart';
import '../domain/models.dart';
import '../utils/error_formatter.dart';

/// Acesso à ocorrência como entidade central (spec §29.2). Toda regra crítica
/// (status, validação, permissões, contadores) é aplicada no backend; este
/// serviço apenas lê views/RPCs e envia comandos.
class OccurrenceService {
  OccurrenceService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const imagesBucket = 'post-images';
  static const _feedView = 'occurrence_feed_rows';

  String? get currentUserId => _supabase.auth.currentUser?.id;

  String? imageUrl(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) return null;
    if (storagePath.startsWith('http')) return storagePath;
    return _supabase.storage.from(imagesBucket).getPublicUrl(storagePath);
  }

  Occurrence _occurrence(dynamic row) => Occurrence.fromJson(
    Map<String, dynamic>.from(row as Map),
    resolveImage: imageUrl,
  );

  List<Occurrence> _occurrences(dynamic rows) =>
      (rows as List<dynamic>).map(_occurrence).toList();

  Future<T> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw Exception(friendlyBackendMessage(error.message, fallback));
    } on StorageException catch (error) {
      throw Exception('$fallback (${error.message})');
    }
  }

  // ---------------------------------------------------------------------------
  // Leituras de ocorrências
  // ---------------------------------------------------------------------------

  Future<List<Occurrence>> fetchRecent({
    int? cityId,
    int limit = 20,
    int offset = 0,
  }) {
    return _guard(() async {
      var query = _supabase.from(_feedView).select();
      if (cityId != null) query = query.eq('city_id', cityId);
      final rows = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);
      return _occurrences(rows);
    }, 'Não foi possível carregar as ocorrências.');
  }

  Future<List<Occurrence>> fetchTrending({
    int? cityId,
    int limit = 20,
    int offset = 0,
  }) {
    return _guard(() async {
      final rows = await _supabase.rpc(
        'get_trending_occurrences',
        params: {
          'target_city_id': cityId,
          'page_size': limit,
          'page_offset': offset,
        },
      );
      return _occurrences(rows);
    }, 'Não foi possível carregar as ocorrências em alta.');
  }

  Future<List<Occurrence>> search({
    String? text,
    int? cityId,
    int? categoryId,
    String? statusCode,
    String? neighborhood,
    double? latitude,
    double? longitude,
    double? maxDistanceKm,
    int limit = 40,
    int offset = 0,
  }) {
    return _guard(() async {
      final rows = await _supabase.rpc(
        'search_occurrences',
        params: {
          'search_text': (text?.trim().isEmpty ?? true) ? null : text!.trim(),
          'target_city_id': cityId,
          'target_category_id': categoryId,
          'target_status': statusCode,
          'neighborhood_text': (neighborhood?.trim().isEmpty ?? true)
              ? null
              : neighborhood!.trim(),
          'origin_latitude': latitude,
          'origin_longitude': longitude,
          'maximum_distance_km': maxDistanceKm,
          'page_size': limit,
          'page_offset': offset,
        },
      );
      return _occurrences(rows);
    }, 'Não foi possível buscar ocorrências.');
  }

  Future<Occurrence?> fetchById(int id) {
    return _guard(() async {
      final row = await _supabase
          .from(_feedView)
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : _occurrence(row);
    }, 'Não foi possível carregar a ocorrência.');
  }

  Future<List<Occurrence>> fetchByIds(Iterable<int> ids) {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return Future.value(const []);
    return _guard(() async {
      final rows = await _supabase
          .from(_feedView)
          .select()
          .inFilter('id', unique);
      final byId = {for (final item in _occurrences(rows)) item.id: item};
      return [for (final id in unique) ?byId[id]];
    }, 'Não foi possível carregar as ocorrências.');
  }

  Future<List<Occurrence>> fetchByAgency(
    int agencyId, {
    bool activeOnly = false,
    int limit = 50,
  }) {
    return _guard(() async {
      var query = _supabase.from(_feedView).select().eq('agency_id', agencyId);
      if (activeOnly) {
        query = query.inFilter('status', [
          'open',
          'in_analysis',
          'in_progress',
          'awaiting_validation',
          'reopened',
        ]);
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return _occurrences(rows);
    }, 'Não foi possível carregar as ocorrências do órgão.');
  }

  Future<List<Occurrence>> fetchByAdministration(
    int administrationId, {
    bool activeOnly = true,
    int limit = 60,
  }) {
    return _guard(() async {
      var query = _supabase
          .from(_feedView)
          .select()
          .eq('administration_id', administrationId);
      if (activeOnly) {
        query = query.inFilter('status', [
          'open',
          'in_analysis',
          'in_progress',
          'awaiting_validation',
          'reopened',
        ]);
      }
      final rows = await query
          .order('administrative_priority', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return _occurrences(rows);
    }, 'Não foi possível carregar a demanda municipal.');
  }

  /// Ocorrências próximas aguardando validação em que o usuário ainda pode votar.
  Future<List<Occurrence>> fetchPendingValidationsNear(
    double latitude,
    double longitude,
  ) {
    return _guard(() async {
      final rows = await _supabase.rpc(
        'get_pending_validations_near',
        params: {
          'origin_latitude': latitude,
          'origin_longitude': longitude,
          'page_size': 5,
        },
      );
      return _occurrences(rows);
    }, 'Não foi possível carregar validações próximas.');
  }

  Future<List<Occurrence>> fetchFollowed() async {
    final userId = currentUserId;
    if (userId == null) return const [];
    return _guard(() async {
      final rows = await _supabase
          .from('occurrence_followers')
          .select('occurrence_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return fetchByIds(
        (rows as List).map((row) => (row['occurrence_id'] as num).toInt()),
      );
    }, 'Não foi possível carregar as ocorrências acompanhadas.');
  }

  Future<List<Occurrence>> fetchSupported() async {
    final userId = currentUserId;
    if (userId == null) return const [];
    return _guard(() async {
      final rows = await _supabase
          .from('occurrence_supports')
          .select('occurrence_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return fetchByIds(
        (rows as List).map((row) => (row['occurrence_id'] as num).toInt()),
      );
    }, 'Não foi possível carregar seus apoios.');
  }

  // ---------------------------------------------------------------------------
  // Relatos, comentários e linha do tempo
  // ---------------------------------------------------------------------------

  Future<List<OccurrenceReport>> fetchReports(int occurrenceId) {
    return _guard(() async {
      final rows = await _supabase
          .from('post_feed_rows')
          .select(
            'id, title, description, created_at, is_anonymous, author_id, '
            'author_display_name, author_username, author_avatar_url, images',
          )
          .eq('occurrence_id', occurrenceId)
          .order('created_at', ascending: false);
      return (rows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final images = (row['images'] as List? ?? const [])
            .map(asJsonMap)
            .whereType<Map<String, dynamic>>()
            .map(
              (image) => ReportImage(
                storagePath: image['storage_path'] as String,
                url: imageUrl(image['storage_path'] as String)!,
                caption: image['caption'] as String?,
              ),
            )
            .toList();
        return OccurrenceReport(
          id: (row['id'] as num).toInt(),
          title: row['title'] as String? ?? '',
          description: row['description'] as String? ?? '',
          createdAt: DateTime.parse(row['created_at'] as String),
          isAnonymous: row['is_anonymous'] == true,
          authorId: row['author_id'] as String?,
          authorName: row['author_display_name'] as String? ?? 'Cidadão',
          authorUsername: row['author_username'] as String?,
          authorAvatarUrl: row['author_avatar_url'] as String?,
          images: images,
        );
      }).toList();
    }, 'Não foi possível carregar os relatos.');
  }

  Future<List<OccurrenceComment>> fetchComments(int occurrenceId) {
    return _guard(() async {
      final rows = await _supabase
          .from('occurrence_comment_rows')
          .select()
          .eq('occurrence_id', occurrenceId)
          .order('created_at', ascending: true);
      final all = (rows as List)
          .map(
            (row) => OccurrenceComment.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      final roots = <OccurrenceComment>[];
      final byId = {for (final comment in all) comment.id: comment};
      for (final comment in all) {
        final parent = comment.parentId == null ? null : byId[comment.parentId];
        if (parent == null) {
          roots.add(comment);
        } else {
          parent.replies.add(comment);
        }
      }
      return roots.reversed.toList();
    }, 'Não foi possível carregar os comentários.');
  }

  Future<void> addComment(int occurrenceId, String body, {int? parentId}) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para comentar.');
    return _guard(() async {
      await _supabase.from('comments').insert({
        'occurrence_id': occurrenceId,
        'body': body.trim(),
        'parent_comment_id': parentId,
        'user_id': userId,
      });
    }, 'Não foi possível publicar o comentário.');
  }

  Future<void> setCommentLike(int commentId, bool liked) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para curtir.');
    return _guard(() async {
      if (liked) {
        await _supabase.from('comment_likes').insert({
          'comment_id': commentId,
          'user_id': userId,
        });
      } else {
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', userId);
      }
    }, 'Não foi possível atualizar a curtida.');
  }

  Future<void> setSupport(int occurrenceId, bool supported) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para apoiar.');
    return _guard(() async {
      if (supported) {
        await _supabase.from('occurrence_supports').insert({
          'occurrence_id': occurrenceId,
          'user_id': userId,
        });
      } else {
        await _supabase
            .from('occurrence_supports')
            .delete()
            .eq('occurrence_id', occurrenceId)
            .eq('user_id', userId);
      }
    }, 'Não foi possível registrar o apoio.');
  }

  Future<void> setFollowing(int occurrenceId, bool following) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para seguir.');
    return _guard(() async {
      if (following) {
        await _supabase.from('occurrence_followers').insert({
          'occurrence_id': occurrenceId,
          'user_id': userId,
        });
      } else {
        await _supabase
            .from('occurrence_followers')
            .delete()
            .eq('occurrence_id', occurrenceId)
            .eq('user_id', userId);
      }
    }, 'Não foi possível atualizar o acompanhamento.');
  }

  Future<List<TimelineEvent>> fetchTimeline(int occurrenceId) {
    return _guard(() async {
      final rows = await _supabase
          .from('occurrence_events')
          .select(
            'id, actor_kind, event_type, description, agency_id, metadata, created_at',
          )
          .eq('occurrence_id', occurrenceId)
          .order('created_at', ascending: false)
          .order('id', ascending: false);
      final events = (rows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final agencyIds = events
          .map((event) => (event['agency_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      final agencyNames = <int, String>{};
      if (agencyIds.isNotEmpty) {
        final agencies = await _supabase
            .from('public_agencies')
            .select('id, name')
            .inFilter('id', agencyIds.toList());
        for (final agency in agencies as List) {
          agencyNames[(agency['id'] as num).toInt()] = agency['name'] as String;
        }
      }

      final followingIds = events
          .map(
            (event) => (asJsonMap(event['metadata'])?['following_id'] as num?)
                ?.toInt(),
          )
          .whereType<int>()
          .toSet();
      final councilorByFollowing = <int, ({int id, String name})>{};
      if (followingIds.isNotEmpty) {
        final followings = await _supabase
            .from('councilor_followings')
            .select('id, councilor_profiles(id, public_name)')
            .inFilter('id', followingIds.toList());
        for (final following in followings as List) {
          final councilor = asJsonMap(following['councilor_profiles']);
          if (councilor == null) continue;
          councilorByFollowing[(following['id'] as num).toInt()] = (
            id: (councilor['id'] as num).toInt(),
            name: councilor['public_name'] as String,
          );
        }
      }

      return events.map((event) {
        final metadata = asJsonMap(event['metadata']) ?? const {};
        final type = event['event_type'] as String? ?? '';
        final actor = event['actor_kind'] as String? ?? 'system';
        final agencyId = (event['agency_id'] as num?)?.toInt();
        final followingId = (metadata['following_id'] as num?)?.toInt();
        final councilor = followingId == null
            ? null
            : councilorByFollowing[followingId];
        final description = event['description'] as String? ?? '';
        final presentation = _presentEvent(
          type: type,
          actor: actor,
          description: description,
          metadata: metadata,
          agencyName: agencyId == null ? null : agencyNames[agencyId],
          councilorName: councilor?.name,
        );
        return TimelineEvent(
          id: (event['id'] as num).toInt(),
          actorKind: actor,
          eventType: type,
          title: presentation.title,
          description: presentation.description,
          createdAt: DateTime.parse(event['created_at'] as String),
          kind: presentation.kind,
          evidenceUrl: imageUrl(metadata['evidence_storage_path'] as String?),
          agencyId: actor == 'agency' ? agencyId : null,
          councilorProfileId: councilor?.id,
        );
      }).toList();
    }, 'Não foi possível carregar o histórico.');
  }

  ({String title, String description, TimelineKind kind}) _presentEvent({
    required String type,
    required String actor,
    required String description,
    required Map<String, dynamic> metadata,
    String? agencyName,
    String? councilorName,
  }) {
    if (type.startsWith('institutional_')) {
      final action = type.substring('institutional_'.length);
      final label = institutionalActionLabels[action] ?? 'Ação oficial';
      final who = actor == 'administration'
          ? 'Prefeitura'
          : (agencyName ?? 'Órgão responsável');
      return (
        title: '$who · $label',
        description: description,
        kind: TimelineKind.official,
      );
    }
    if (type == 'councilor_following_started') {
      return (
        title: '${councilorName ?? 'Vereador'} iniciou acompanhamento',
        description: 'Acompanhamento voluntário da demanda.',
        kind: TimelineKind.councilor,
      );
    }
    if (type == 'councilor_following_ended') {
      return (
        title: '${councilorName ?? 'Vereador'} encerrou acompanhamento',
        description: description,
        kind: TimelineKind.councilor,
      );
    }
    if (type.startsWith('councilor_')) {
      final label =
          councilorActionLabels[type.substring('councilor_'.length)] ??
          'Ação registrada';
      return (
        title: '${councilorName ?? 'Vereador'} · $label',
        description: description,
        kind: TimelineKind.councilor,
      );
    }
    return switch (type) {
      'occurrence_created' => (
        title: 'Ocorrência criada',
        description: 'Primeiro relato e evidências registrados.',
        kind: TimelineKind.community,
      ),
      'report_added' => (
        title: 'Novo relato da comunidade',
        description: 'Uma nova contribuição foi adicionada.',
        kind: TimelineKind.community,
      ),
      'agency_assigned' => (
        title: 'Órgão responsável identificado pelo UrbApp',
        description: 'Responsável associado conforme cidade e categoria.',
        kind: TimelineKind.platform,
      ),
      'status_changed' => (
        title: description.replaceAll('.', ''),
        description: 'Registro automático da plataforma.',
        kind: TimelineKind.platform,
      ),
      'validation_opened' => (
        title: 'Possível resolução informada',
        description: 'Ocorrência enviada para validação comunitária.',
        kind: TimelineKind.validation,
      ),
      'resolution_confirmed' => (
        title: 'Comunidade confirmou a resolução',
        description: 'A ocorrência atingiu as confirmações necessárias.',
        kind: TimelineKind.validation,
      ),
      'validation_rejected' => (
        title: 'A comunidade informou que o problema continua',
        description: 'A ocorrência voltou ao estado anterior.',
        kind: TimelineKind.validation,
      ),
      'validation_expired' => (
        title: 'Validação encerrada sem quórum',
        description:
            'Sem confirmações suficientes; nada foi considerado resolvido.',
        kind: TimelineKind.validation,
      ),
      'occurrence_reopened' => (
        title: 'Ocorrência reaberta',
        description: description,
        kind: TimelineKind.community,
      ),
      'administration_changed' => (
        title: 'Herdada pela nova gestão municipal',
        description: 'Mudança de gestão registrada sem apagar o histórico.',
        kind: TimelineKind.platform,
      ),
      'occurrence_merged' || 'duplicate_merged' => (
        title: 'Relatos consolidados',
        description: description,
        kind: TimelineKind.moderation,
      ),
      'report_hidden' || 'comment_hidden' || 'occurrence_invalidated' => (
        title: 'Moderação',
        description: description,
        kind: TimelineKind.moderation,
      ),
      'jurisdiction_changed' => (
        title: 'Competência atualizada',
        description: description,
        kind: TimelineKind.platform,
      ),
      'status_restored' => (
        title: 'Estado operacional restaurado',
        description: description,
        kind: TimelineKind.platform,
      ),
      _ => (
        title: 'Atualização da ocorrência',
        description: description,
        kind: TimelineKind.platform,
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Validação comunitária
  // ---------------------------------------------------------------------------

  Future<ResolutionContext?> fetchResolutionContext(int occurrenceId) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'get_resolution_context',
        params: {'target_occurrence_id': occurrenceId},
      );
      final json = asJsonMap(data);
      return json == null
          ? null
          : ResolutionContext.fromJson(json, resolveImage: imageUrl);
    }, 'Não foi possível carregar a validação.');
  }

  Future<void> reportPossibleResolution({
    required int occurrenceId,
    required String description,
    String initiatorKind = 'citizen',
    XFile? evidence,
  }) {
    return _guard(() async {
      String? path;
      if (evidence != null) {
        path = await _uploadEvidence(occurrenceId, 'resolution', evidence);
      }
      try {
        await _supabase.rpc(
          'open_resolution_cycle_with_evidence',
          params: {
            'target_occurrence_id': occurrenceId,
            'resolution_description': description.trim(),
            'initiator_kind': initiatorKind,
            'evidence_storage_path': path,
          },
        );
      } catch (_) {
        if (path != null) await _discardUpload(path);
        rethrow;
      }
    }, 'Não foi possível informar a possível resolução.');
  }

  /// Registra o voto. A elegibilidade (raio, quórum, iniciador, voto único) é
  /// verificada no backend; aqui apenas enviamos a localização atual.
  Future<String> vote({
    required int cycleId,
    required bool confirm,
    required double latitude,
    required double longitude,
  }) {
    return _guard(() async {
      final result = await _supabase.rpc(
        'vote_resolution_cycle',
        params: {
          'target_cycle_id': cycleId,
          'vote_decision': confirm ? 'confirm' : 'reject',
          'voter_latitude': latitude,
          'voter_longitude': longitude,
        },
      );
      return asJsonMap(result)?['cycle_status'] as String? ?? 'pending';
    }, 'Não foi possível registrar sua validação.');
  }

  Future<void> reopen({
    required int occurrenceId,
    required String description,
    required XFile evidence,
  }) {
    return _guard(() async {
      final path = await _uploadEvidence(occurrenceId, 'reopening', evidence);
      try {
        await _supabase.rpc(
          'reopen_occurrence',
          params: {
            'target_occurrence_id': occurrenceId,
            'reopening_description': description.trim(),
            'evidence_storage_path': path,
          },
        );
      } catch (_) {
        await _discardUpload(path);
        rethrow;
      }
    }, 'Não foi possível reabrir a ocorrência.');
  }

  // ---------------------------------------------------------------------------
  // Relatar: duplicidade, nova ocorrência e relato adicionado
  // ---------------------------------------------------------------------------

  Future<List<DuplicateCandidate>> findPotentialDuplicates({
    required int cityId,
    required int categoryId,
    required double latitude,
    required double longitude,
    String? text,
  }) {
    return _guard(() async {
      final rows = await _supabase.rpc(
        'find_potential_duplicate_occurrences',
        params: {
          'target_city_id': cityId,
          'target_category_id': categoryId,
          'target_latitude': latitude,
          'target_longitude': longitude,
          'target_text': text,
          'maximum_distance_km': 1,
        },
      );
      final distances = <int, double>{
        for (final row in rows as List)
          (row['occurrence_id'] as num).toInt(): (row['distance_km'] as num)
              .toDouble(),
      };
      final occurrences = await fetchByIds(distances.keys);
      return occurrences
          .map(
            (occurrence) => DuplicateCandidate(
              occurrence: occurrence,
              distanceKm: distances[occurrence.id] ?? 0,
            ),
          )
          .toList()
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    }, 'Não foi possível verificar ocorrências próximas.');
  }

  Future<ReportSubmission> createOccurrence({
    required int cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    String? street,
    String? neighborhood,
    required bool anonymous,
    List<XFile> photos = const [],
  }) {
    return _guard(() async {
      if (photos.isEmpty) {
        throw Exception('Adicione pelo menos uma foto do problema.');
      }
      await _supabase.rpc('ensure_my_profile');
      // A foto sobe antes da publicação: o servidor só cria a ocorrência se
      // ela existir e a vincula ao primeiro relato na mesma transação.
      final uploaded = await _uploadPendingPhotos(photos);
      try {
        final result = await _supabase.rpc(
          'publish_occurrence_report',
          params: {
            'target_city_id': cityId,
            'target_category_id': categoryId,
            'report_title': title.trim(),
            'report_description': description.trim(),
            'report_latitude': latitude,
            'report_longitude': longitude,
            'report_street': street,
            'report_neighborhood': neighborhood,
            'report_anonymous': anonymous,
            'report_photo_paths': uploaded,
          },
        );
        final row = asJsonMap(result is List ? result.first : result)!;
        return ReportSubmission(
          occurrenceId: (row['occurrence_id'] as num).toInt(),
          postId: (row['post_id'] as num).toInt(),
          createdOccurrence: true,
          reportsCount: 1,
        );
      } catch (_) {
        for (final path in uploaded) {
          await _discardUpload(path);
        }
        rethrow;
      }
    }, 'Não foi possível registrar o problema.');
  }

  Future<ReportSubmission> addReport({
    required int occurrenceId,
    String? title,
    required String description,
    required bool anonymous,
    List<XFile> photos = const [],
  }) {
    return _guard(() async {
      await _supabase.rpc('ensure_my_profile');
      final result = await _supabase.rpc(
        'add_report_to_occurrence',
        params: {
          'target_occurrence_id': occurrenceId,
          'report_title': title,
          'report_description': description.trim(),
          'report_anonymous': anonymous,
        },
      );
      final postId = (result as num).toInt();
      await _attachPhotos(postId, photos);
      final updated = await fetchById(occurrenceId);
      return ReportSubmission(
        occurrenceId: occurrenceId,
        postId: postId,
        createdOccurrence: false,
        reportsCount: updated?.reportsCount,
      );
    }, 'Não foi possível adicionar seu relato.');
  }

  /// Envia as fotos para a pasta de pendentes; o caminho não identifica o autor
  /// (relatos anônimos, spec §37).
  Future<List<String>> _uploadPendingPhotos(List<XFile> photos) async {
    final folder = '${DateTime.now().microsecondsSinceEpoch}';
    final uploaded = <String>[];
    try {
      for (var index = 0; index < photos.length; index++) {
        final extension = _extensionOf(photos[index].name);
        final path = 'reports/pending/$folder/${index + 1}.$extension';
        await _supabase.storage
            .from(imagesBucket)
            .uploadBinary(
              path,
              await photos[index].readAsBytes(),
              fileOptions: FileOptions(contentType: _mimeOf(extension)),
            );
        uploaded.add(path);
      }
    } catch (_) {
      for (final path in uploaded) {
        await _discardUpload(path);
      }
      rethrow;
    }
    return uploaded;
  }

  Future<void> _attachPhotos(int postId, List<XFile> photos) async {
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final extension = _extensionOf(photo.name);
      // Caminho sem identificador do autor: preserva relatos anônimos (spec §37).
      final path =
          'reports/$postId/${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
      await _supabase.storage
          .from(imagesBucket)
          .uploadBinary(
            path,
            await photo.readAsBytes(),
            fileOptions: FileOptions(contentType: _mimeOf(extension)),
          );
      await _supabase.from('post_images').insert({
        'post_id': postId,
        'storage_path': path,
        'position': index + 1,
      });
    }
  }

  Future<String> _uploadEvidence(
    int occurrenceId,
    String folder,
    XFile file,
  ) async {
    final extension = _extensionOf(file.name);
    final path =
        'occurrences/$occurrenceId/$folder/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _supabase.storage
        .from(imagesBucket)
        .uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(contentType: _mimeOf(extension)),
        );
    return path;
  }

  Future<String> uploadInstitutionalEvidence(int occurrenceId, XFile file) =>
      _guard(
        () => _uploadEvidence(occurrenceId, 'institutional', file),
        'Não foi possível enviar a evidência.',
      );

  Future<void> _discardUpload(String path) async {
    try {
      await _supabase.storage.from(imagesBucket).remove([path]);
    } catch (_) {
      // Uploads órfãos expiram pela política de limpeza; não bloqueia o usuário.
    }
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? 'jpg' : name.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension)
        ? extension
        : 'jpg';
  }

  String _mimeOf(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };

  // ---------------------------------------------------------------------------
  // Catálogos e denúncias
  // ---------------------------------------------------------------------------

  Future<List<CategoryOption>> fetchCategories() {
    return _guard(() async {
      final rows = await _supabase
          .from('problem_categories')
          .select('id, name, slug, requires_resolution_evidence')
          .order('name', ascending: true);
      return (rows as List)
          .map(
            (row) => CategoryOption(
              id: (row['id'] as num).toInt(),
              name: row['name'] as String,
              slug: row['slug'] as String?,
              requiresResolutionEvidence:
                  row['requires_resolution_evidence'] == true,
            ),
          )
          .toList();
    }, 'Não foi possível carregar as categorias.');
  }

  Future<List<CityOption>> fetchCities() {
    return _guard(() async {
      final rows = await _supabase
          .from('cities')
          .select('id, name, state')
          .order('name', ascending: true);
      return (rows as List)
          .map(
            (row) => CityOption(
              id: (row['id'] as num).toInt(),
              name: row['name'] as String,
              stateCode: row['state'] as String,
            ),
          )
          .toList();
    }, 'Não foi possível carregar as cidades.');
  }

  /// Denúncia de relato ou comentário (spec §38).
  Future<void> reportContent({
    required String targetType,
    required int targetId,
    required String reason,
  }) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para denunciar.');
    return _guard(() async {
      try {
        await _supabase.from('moderation_reports').insert({
          'reporter_user_id': userId,
          'target_type': targetType,
          'target_id': targetId,
          'reason': reason.trim(),
        });
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          throw Exception('Você já denunciou este conteúdo.');
        }
        rethrow;
      }
    }, 'Não foi possível enviar a denúncia.');
  }
}
