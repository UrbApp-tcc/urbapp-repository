import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../utils/error_formatter.dart';

class InstitutionalMembership {
  const InstitutionalMembership({
    required this.id,
    required this.name,
    required this.cityId,
    this.cityName,
    required this.role,
  });

  final int id;
  final String name;
  final int cityId;
  final String? cityName;
  final String role;
}

class CouncilorIdentity {
  const CouncilorIdentity({
    required this.id,
    required this.publicName,
    required this.cityId,
    this.party,
    required this.status,
    required this.mandateStartsOn,
    required this.mandateEndsOn,
  });

  final int id;
  final String publicName;
  final int cityId;
  final String? party;
  final InstitutionalProfileStatus status;
  final DateTime mandateStartsOn;
  final DateTime mandateEndsOn;

  bool get isActive {
    final today = DateTime.now();
    return status.isVerified &&
        !today.isBefore(mandateStartsOn) &&
        !today.isAfter(mandateEndsOn.add(const Duration(days: 1)));
  }
}

/// Papéis adicionais do usuário. O UrbApp é um único aplicativo; papéis só
/// liberam capacidades contextuais (spec §44.7).
class InstitutionalAccess {
  const InstitutionalAccess({
    this.platformRoles = const {},
    this.administrations = const [],
    this.agencies = const [],
    this.councilor,
  });

  final Set<String> platformRoles;
  final List<InstitutionalMembership> administrations;
  final List<InstitutionalMembership> agencies;
  final CouncilorIdentity? councilor;

  bool get isPlatformAdmin =>
      platformRoles.contains('admin') || platformRoles.contains('moderator');
  bool get isCouncilor => councilor?.isActive ?? false;
  bool get hasInstitutionalRole =>
      administrations.isNotEmpty || agencies.isNotEmpty || isCouncilor;
}

/// O que o usuário pode fazer nesta ocorrência. A autorização definitiva é
/// sempre conferida pelas RPCs no backend.
class OccurrenceCapabilities {
  const OccurrenceCapabilities({
    this.canActForAdministration = false,
    this.canActForAgency = false,
    this.isEligibleCouncilor = false,
    this.councilorFollowingId,
    this.councilorFollowingStatus,
    this.councilorHasConcreteAction = false,
    this.councilorProfileId,
    this.councilorFollowingStartedAt,
  });

  final bool canActForAdministration;
  final bool canActForAgency;
  final bool isEligibleCouncilor;
  final int? councilorFollowingId;
  final String? councilorFollowingStatus;
  final bool councilorHasConcreteAction;

  /// Perfil parlamentar do usuário (quando é vereador elegível).
  final int? councilorProfileId;
  final DateTime? councilorFollowingStartedAt;

  bool get hasActiveFollowing =>
      councilorFollowingId != null &&
      councilorFollowingStatus != 'ended' &&
      councilorFollowingStatus != 'resolved';

  bool get hasAnyRole =>
      canActForAdministration || canActForAgency || isEligibleCouncilor;
}

class OccurrenceFollower {
  const OccurrenceFollower({
    required this.councilorProfileId,
    required this.name,
    this.party,
    required this.status,
  });

  final int councilorProfileId;
  final String name;
  final String? party;
  final String status;
}

class CouncilorFollowingItem {
  const CouncilorFollowingItem({
    required this.followingId,
    required this.occurrenceId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.lastActionType,
    this.lastActionAt,
  });

  final int followingId;
  final int occurrenceId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? lastActionType;
  final DateTime? lastActionAt;
}

class AgencyChoice {
  const AgencyChoice({
    required this.id,
    required this.name,
    required this.status,
  });

  final int id;
  final String name;
  final InstitutionalProfileStatus status;
}

class InstitutionalActionRecord {
  const InstitutionalActionRecord({
    required this.occurrenceId,
    required this.actorKind,
    required this.actionType,
    required this.description,
    required this.createdAt,
    this.forecastAt,
    this.targetAgencyId,
  });

  final int occurrenceId;
  final String actorKind;
  final String actionType;
  final String description;
  final DateTime createdAt;
  final DateTime? forecastAt;
  final int? targetAgencyId;
}

class AgencyAssignmentRecord {
  const AgencyAssignmentRecord({
    required this.occurrenceId,
    required this.agencyId,
    required this.startsAt,
    this.endsAt,
    this.reason,
  });

  final int occurrenceId;
  final int agencyId;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? reason;
}

class AdministrationOccurrenceContext {
  const AdministrationOccurrenceContext({
    this.actions = const [],
    this.currentAssignment,
  });

  final List<InstitutionalActionRecord> actions;
  final AgencyAssignmentRecord? currentAssignment;

  InstitutionalActionRecord? get latestAdministrationAction => actions
      .where((action) => action.actorKind == 'administration')
      .firstOrNull;

  InstitutionalActionRecord? get latestAgencyAction =>
      actions.where((action) => action.actorKind == 'agency').firstOrNull;

  InstitutionalActionRecord? get latestForecast => actions
      .where(
        (action) =>
            action.actionType == 'forecast' && action.forecastAt != null,
      )
      .firstOrNull;

  DateTime? get lastOfficialActivityAt => actions.firstOrNull?.createdAt;
}

class ValidationSettingsInfo {
  const ValidationSettingsInfo({
    required this.confirmations,
    required this.rejections,
    required this.radiusKm,
    required this.durationHours,
    required this.cooldownHours,
  });

  final int confirmations;
  final int rejections;
  final double radiusKm;
  final int durationHours;
  final int cooldownHours;
}

class ModerationQueueItem {
  const ModerationQueueItem({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.occurrenceId,
    this.targetPreview,
  });

  final int id;
  final String targetType;
  final int targetId;
  final int? occurrenceId;
  final String reason;
  final String status;
  final String? targetPreview;
  final DateTime createdAt;
}

class InstitutionalVerificationRequest {
  const InstitutionalVerificationRequest({
    required this.id,
    required this.kind,
    required this.name,
    required this.cityName,
    required this.institutionalEmail,
    required this.proofSummary,
    required this.createdAt,
  });

  final int id;
  final String kind;
  final String name;
  final String cityName;
  final String institutionalEmail;
  final String proofSummary;
  final DateTime createdAt;
}

class InstitutionalService {
  InstitutionalService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static InstitutionalAccess? _cachedAccess;
  static String? _cachedFor;

  Future<T> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw Exception(friendlyBackendMessage(error.message, fallback));
    }
  }

  static void clearCache() {
    _cachedAccess = null;
    _cachedFor = null;
  }

  Future<InstitutionalAccess> fetchMyAccess({bool refresh = false}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const InstitutionalAccess();
    if (!refresh && _cachedFor == userId && _cachedAccess != null) {
      return _cachedAccess!;
    }

    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('platform_user_roles')
            .select('role')
            .eq('user_id', userId),
        _supabase
            .from('administration_users')
            .select(
              'role, municipal_administrations!administration_users_administration_id_fkey(id, name, city_id, cities(name))',
            )
            .eq('user_id', userId)
            .eq('is_active', true),
        _supabase
            .from('agency_users')
            .select(
              'role, public_agencies!agency_users_agency_id_fkey(id, name, city_id, cities(name))',
            )
            .eq('user_id', userId)
            .eq('is_active', true),
        _supabase
            .from('councilor_profiles')
            .select(
              'id, public_name, city_id, party, profile_status, mandate_starts_on, mandate_ends_on',
            )
            .eq('profile_id', userId)
            .maybeSingle(),
      ]);

      InstitutionalMembership membership(dynamic raw, String key) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entity = asJsonMap(row[key]) ?? const {};
        return InstitutionalMembership(
          id: (entity['id'] as num).toInt(),
          name: entity['name'] as String? ?? '',
          cityId: (entity['city_id'] as num).toInt(),
          cityName: asJsonMap(entity['cities'])?['name'] as String?,
          role: row['role'] as String? ?? '',
        );
      }

      final councilorRow = asJsonMap(responses[3]);
      final access = InstitutionalAccess(
        platformRoles: (responses[0] as List)
            .map((row) => row['role'] as String)
            .toSet(),
        administrations: (responses[1] as List)
            .map((row) => membership(row, 'municipal_administrations'))
            .toList(),
        agencies: (responses[2] as List)
            .map((row) => membership(row, 'public_agencies'))
            .toList(),
        councilor: councilorRow == null
            ? null
            : CouncilorIdentity(
                id: (councilorRow['id'] as num).toInt(),
                publicName: councilorRow['public_name'] as String,
                cityId: (councilorRow['city_id'] as num).toInt(),
                party: councilorRow['party'] as String?,
                status: InstitutionalProfileStatus.fromCode(
                  councilorRow['profile_status'] as String?,
                ),
                mandateStartsOn: DateTime.parse(
                  councilorRow['mandate_starts_on'] as String,
                ),
                mandateEndsOn: DateTime.parse(
                  councilorRow['mandate_ends_on'] as String,
                ),
              ),
      );
      _cachedAccess = access;
      _cachedFor = userId;
      return access;
    }, 'Não foi possível carregar seus acessos institucionais.');
  }

  Future<OccurrenceCapabilities> fetchCapabilities(
    Occurrence occurrence,
  ) async {
    final access = await fetchMyAccess();
    final canAdministration = access.administrations.any(
      (item) => item.id == occurrence.administrationId,
    );
    final canAgency =
        occurrence.agencyId != null &&
        access.agencies.any((item) => item.id == occurrence.agencyId);
    final councilor = access.councilor;
    final eligibleCouncilor =
        councilor != null &&
        councilor.isActive &&
        councilor.cityId == occurrence.cityId;

    int? followingId;
    String? followingStatus;
    DateTime? followingStartedAt;
    var hasConcreteAction = false;
    if (eligibleCouncilor) {
      final following = await _supabase
          .from('councilor_followings')
          .select('id, status, started_at, councilor_actions(action_type)')
          .eq('occurrence_id', occurrence.id)
          .eq('councilor_profile_id', councilor.id)
          .maybeSingle();
      followingId = (following?['id'] as num?)?.toInt();
      followingStatus = following?['status'] as String?;
      followingStartedAt = DateTime.tryParse(
        following?['started_at'] as String? ?? '',
      )?.toLocal();
      hasConcreteAction =
          ((following?['councilor_actions'] as List?) ?? const []).any(
            (action) => action['action_type'] != 'possible_resolution',
          );
    }

    return OccurrenceCapabilities(
      canActForAdministration: canAdministration,
      canActForAgency: canAgency,
      isEligibleCouncilor: eligibleCouncilor,
      councilorFollowingId: followingId,
      councilorFollowingStatus: followingStatus,
      councilorHasConcreteAction: hasConcreteAction,
      councilorProfileId: eligibleCouncilor ? councilor.id : null,
      councilorFollowingStartedAt: followingStartedAt,
    );
  }

  Future<Map<int, AdministrationOccurrenceContext>>
  fetchAdministrationOccurrenceContexts(
    int administrationId,
    Iterable<int> occurrenceIds,
  ) {
    final ids = occurrenceIds.toSet().toList();
    if (ids.isEmpty) return Future.value(const {});
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('institutional_actions')
            .select(
              'occurrence_id, actor_kind, action_type, description, created_at, forecast_at, target_agency_id',
            )
            .eq('administration_id', administrationId)
            .inFilter('occurrence_id', ids)
            .order('created_at', ascending: false),
        _supabase
            .from('occurrence_agency_assignments')
            .select('occurrence_id, agency_id, reason, starts_at, ends_at')
            .eq('administration_id', administrationId)
            .inFilter('occurrence_id', ids)
            .isFilter('ends_at', null),
      ]);

      final actionsByOccurrence = <int, List<InstitutionalActionRecord>>{};
      for (final raw in responses[0] as List) {
        final occurrenceId = (raw['occurrence_id'] as num).toInt();
        actionsByOccurrence
            .putIfAbsent(occurrenceId, () => [])
            .add(
              InstitutionalActionRecord(
                occurrenceId: occurrenceId,
                actorKind: raw['actor_kind'] as String? ?? 'agency',
                actionType: raw['action_type'] as String? ?? '',
                description: raw['description'] as String? ?? '',
                createdAt: DateTime.parse(
                  raw['created_at'] as String,
                ).toLocal(),
                forecastAt: DateTime.tryParse(
                  raw['forecast_at'] as String? ?? '',
                )?.toLocal(),
                targetAgencyId: (raw['target_agency_id'] as num?)?.toInt(),
              ),
            );
      }

      final assignmentByOccurrence = <int, AgencyAssignmentRecord>{};
      for (final raw in responses[1] as List) {
        final occurrenceId = (raw['occurrence_id'] as num).toInt();
        assignmentByOccurrence[occurrenceId] = AgencyAssignmentRecord(
          occurrenceId: occurrenceId,
          agencyId: (raw['agency_id'] as num).toInt(),
          startsAt: DateTime.parse(raw['starts_at'] as String).toLocal(),
          endsAt: DateTime.tryParse(raw['ends_at'] as String? ?? '')?.toLocal(),
          reason: raw['reason'] as String?,
        );
      }

      return {
        for (final id in ids)
          id: AdministrationOccurrenceContext(
            actions: actionsByOccurrence[id] ?? const [],
            currentAssignment: assignmentByOccurrence[id],
          ),
      };
    }, 'Não foi possível carregar o contexto operacional da gestão.');
  }

  /// Vereadores que acompanham a ocorrência (vários podem acompanhar, spec §35).
  Future<List<OccurrenceFollower>> fetchCouncilorsFollowing(int occurrenceId) {
    return _guard(() async {
      final rows = await _supabase
          .from('councilor_followings')
          .select('status, councilor_profiles(id, public_name, party)')
          .eq('occurrence_id', occurrenceId)
          .order('started_at', ascending: true);
      return (rows as List)
          .map((raw) {
            final councilor = asJsonMap(raw['councilor_profiles']);
            if (councilor == null) return null;
            return OccurrenceFollower(
              councilorProfileId: (councilor['id'] as num).toInt(),
              name: councilor['public_name'] as String,
              party: councilor['party'] as String?,
              status: raw['status'] as String? ?? 'started',
            );
          })
          .whereType<OccurrenceFollower>()
          .toList();
    }, 'Não foi possível carregar o acompanhamento parlamentar.');
  }

  Future<List<CouncilorFollowingItem>> fetchCouncilorFollowings(
    int councilorProfileId, {
    bool activeOnly = false,
  }) {
    return _guard(() async {
      var query = _supabase
          .from('councilor_followings')
          .select(
            'id, occurrence_id, status, started_at, ended_at, councilor_actions(action_type, created_at)',
          )
          .eq('councilor_profile_id', councilorProfileId);
      if (activeOnly) query = query.isFilter('ended_at', null);
      final rows = await query.order('started_at', ascending: false);
      return (rows as List).map((raw) {
        final actions =
            ((raw['councilor_actions'] as List?) ?? const [])
                .map((action) => Map<String, dynamic>.from(action as Map))
                .toList()
              ..sort(
                (a, b) => (b['created_at'] as String).compareTo(
                  a['created_at'] as String,
                ),
              );
        return CouncilorFollowingItem(
          followingId: (raw['id'] as num).toInt(),
          occurrenceId: (raw['occurrence_id'] as num).toInt(),
          status: raw['status'] as String? ?? 'started',
          startedAt: DateTime.parse(raw['started_at'] as String),
          endedAt: raw['ended_at'] == null
              ? null
              : DateTime.parse(raw['ended_at'] as String),
          lastActionType: actions.isEmpty
              ? null
              : actions.first['action_type'] as String?,
          lastActionAt: actions.isEmpty
              ? null
              : DateTime.parse(actions.first['created_at'] as String),
        );
      }).toList();
    }, 'Não foi possível carregar os acompanhamentos.');
  }

  /// Ocorrências com acompanhamento parlamentar. Usado nos filtros de
  /// descoberta sem misturar acompanhamento institucional com favoritos.
  Future<Set<int>> fetchFollowingOccurrenceIds(
    Iterable<int> occurrenceIds, {
    int? councilorProfileId,
    bool activeOnly = true,
  }) {
    final ids = occurrenceIds.toSet().toList();
    if (ids.isEmpty) return Future.value(<int>{});
    return _guard(() async {
      var query = _supabase
          .from('councilor_followings')
          .select('occurrence_id, status')
          .inFilter('occurrence_id', ids);
      if (councilorProfileId != null) {
        query = query.eq('councilor_profile_id', councilorProfileId);
      }
      final rows = await query;
      return (rows as List)
          .where(
            (raw) =>
                !activeOnly ||
                (raw['status'] != 'ended' && raw['status'] != 'resolved'),
          )
          .map((raw) => (raw['occurrence_id'] as num).toInt())
          .toSet();
    }, 'Não foi possível carregar os acompanhamentos parlamentares.');
  }

  Future<void> registerInstitutionalAction({
    required int occurrenceId,
    required String actionType,
    required String description,
    int? targetAgencyId,
    DateTime? forecastAt,
    String? evidenceStoragePath,
  }) {
    return _guard(() async {
      await _supabase.rpc(
        'register_institutional_action',
        params: {
          'target_occurrence_id': occurrenceId,
          'institutional_action_type': actionType,
          'action_description': description.trim(),
          'action_target_agency_id': targetAgencyId,
          'action_forecast_at': forecastAt?.toUtc().toIso8601String(),
          'evidence_storage_path': evidenceStoragePath,
        },
      );
    }, 'Não foi possível registrar a ação oficial.');
  }

  Future<List<AgencyChoice>> fetchAgenciesForCity(int cityId) {
    return _guard(() async {
      final rows = await _supabase
          .from('public_agencies')
          .select('id, name, profile_status')
          .eq('city_id', cityId)
          .order('name', ascending: true);
      return (rows as List)
          .map(
            (row) => AgencyChoice(
              id: (row['id'] as num).toInt(),
              name: row['name'] as String,
              status: InstitutionalProfileStatus.fromCode(
                row['profile_status'] as String?,
              ),
            ),
          )
          .toList();
    }, 'Não foi possível carregar os órgãos.');
  }

  Future<int> startCouncilorFollowing(int occurrenceId) {
    return _guard(() async {
      final response = await _supabase.rpc(
        'start_councilor_following',
        params: {'target_occurrence_id': occurrenceId},
      );
      return (response as num).toInt();
    }, 'Não foi possível iniciar o acompanhamento.');
  }

  Future<void> registerCouncilorAction({
    required int followingId,
    required String actionType,
    required String description,
    String? evidenceStoragePath,
  }) {
    return _guard(() async {
      await _supabase.rpc(
        'register_councilor_action',
        params: {
          'target_following_id': followingId,
          'councilor_action_type': actionType,
          'action_description': description.trim(),
          'evidence_storage_path': evidenceStoragePath,
        },
      );
    }, 'Não foi possível registrar a atuação.');
  }

  Future<void> endCouncilorFollowing({
    required int followingId,
    required String description,
  }) {
    return _guard(() async {
      await _supabase.rpc(
        'end_councilor_following',
        params: {
          'target_following_id': followingId,
          'closing_description': description.trim(),
        },
      );
    }, 'Não foi possível encerrar o acompanhamento.');
  }

  Future<void> submitCouncilorRequest({
    required int cityId,
    required String publicName,
    required String party,
    required DateTime mandateStartsOn,
    required DateTime mandateEndsOn,
    required String institutionalEmail,
    required String proofSummary,
    String? proofLinks,
  }) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      await _supabase.from('councilor_profile_requests').insert({
        'requester_user_id': userId,
        'city_id': cityId,
        'public_name': publicName.trim(),
        'party': party.trim().isEmpty ? null : party.trim(),
        'mandate_starts_on': _dateOnly(mandateStartsOn),
        'mandate_ends_on': _dateOnly(mandateEndsOn),
        'institutional_email': institutionalEmail.trim().toLowerCase(),
        'proof_summary': proofSummary.trim(),
        'proof_links': (proofLinks?.trim().isEmpty ?? true)
            ? null
            : proofLinks!.trim(),
      });
    }, 'Não foi possível enviar a solicitação.');
  }

  Future<List<ModerationQueueItem>> fetchModerationQueue() {
    return _guard(() async {
      final rows =
          (await _supabase
                  .from('moderation_reports')
                  .select(
                    'id, target_type, target_id, occurrence_id, reason, status, created_at',
                  )
                  .inFilter('status', ['pending', 'in_analysis'])
                  .order('created_at', ascending: true))
              as List;
      final postIds = rows
          .where((row) => row['target_type'] == 'post')
          .map((row) => (row['target_id'] as num).toInt())
          .toSet();
      final commentIds = rows
          .where((row) => row['target_type'] == 'comment')
          .map((row) => (row['target_id'] as num).toInt())
          .toSet();
      final previews = <String, String>{};
      if (postIds.isNotEmpty) {
        final posts = await _supabase
            .from('post_feed_rows')
            .select('id, title, description')
            .inFilter('id', postIds.toList());
        for (final post in posts as List) {
          previews['post:${post['id']}'] =
              '${post['title']} — ${post['description']}';
        }
      }
      if (commentIds.isNotEmpty) {
        final comments = await _supabase
            .from('comments')
            .select('id, body')
            .inFilter('id', commentIds.toList());
        for (final comment in comments as List) {
          previews['comment:${comment['id']}'] = comment['body'] as String;
        }
      }
      return rows
          .map(
            (row) => ModerationQueueItem(
              id: (row['id'] as num).toInt(),
              targetType: row['target_type'] as String,
              targetId: (row['target_id'] as num).toInt(),
              occurrenceId: (row['occurrence_id'] as num?)?.toInt(),
              reason: row['reason'] as String,
              status: row['status'] as String,
              targetPreview:
                  previews['${row['target_type']}:${row['target_id']}'],
              createdAt: DateTime.parse(row['created_at'] as String),
            ),
          )
          .toList();
    }, 'Não foi possível carregar a fila de moderação.');
  }

  Future<void> startModerationReview(int reportId) {
    return _guard(() async {
      await _supabase.rpc(
        'start_moderation_review',
        params: {'target_report_id': reportId},
      );
    }, 'Não foi possível iniciar a análise.');
  }

  Future<void> reviewModerationReport({
    required int reportId,
    required bool uphold,
    required String notes,
    required bool invalidateWholeOccurrence,
  }) {
    return _guard(() async {
      await _supabase.rpc(
        'review_moderation_report',
        params: {
          'target_report_id': reportId,
          'decision': uphold ? 'upheld' : 'dismissed',
          'notes': notes.trim(),
          'invalidate_whole_occurrence': invalidateWholeOccurrence,
        },
      );
    }, 'Não foi possível concluir a moderação.');
  }

  Future<List<InstitutionalVerificationRequest>>
  fetchInstitutionalVerificationQueue() async {
    try {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('agency_profile_requests')
            .select(
              'id, agency_name, request_kind, institutional_email, proof_summary, created_at, cities(name)',
            )
            .eq('status', 'pending')
            .order('created_at', ascending: true),
        _supabase
            .from('councilor_profile_requests')
            .select(
              'id, public_name, institutional_email, proof_summary, created_at, cities(name)',
            )
            .eq('status', 'pending')
            .order('created_at', ascending: true),
      ]);

      final requests = <InstitutionalVerificationRequest>[];
      for (final raw in responses[0] as List<dynamic>) {
        final item = raw as Map<String, dynamic>;
        requests.add(
          InstitutionalVerificationRequest(
            id: (item['id'] as num).toInt(),
            kind: item['request_kind'] as String? ?? 'agency',
            name: item['agency_name'] as String,
            cityName:
                (item['cities'] as Map<String, dynamic>?)?['name'] as String? ??
                'Cidade',
            institutionalEmail: item['institutional_email'] as String,
            proofSummary: item['proof_summary'] as String,
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        );
      }
      for (final raw in responses[1] as List<dynamic>) {
        final item = raw as Map<String, dynamic>;
        requests.add(
          InstitutionalVerificationRequest(
            id: (item['id'] as num).toInt(),
            kind: 'councilor',
            name: item['public_name'] as String,
            cityName:
                (item['cities'] as Map<String, dynamic>?)?['name'] as String? ??
                'Cidade',
            institutionalEmail: item['institutional_email'] as String,
            proofSummary: item['proof_summary'] as String,
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        );
      }
      requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return requests;
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao carregar verificações institucionais: ${error.message}',
      );
    }
  }

  Future<void> reviewInstitutionalRequest({
    required InstitutionalVerificationRequest request,
    required bool approve,
    required String notes,
  }) async {
    final function = request.kind != 'councilor'
        ? 'review_agency_profile_request'
        : 'review_councilor_profile_request';
    try {
      await _supabase.rpc(
        function,
        params: {
          'target_request_id': request.id,
          'decision': approve ? 'approved' : 'rejected',
          'notes': notes.trim().isEmpty ? null : notes.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao revisar solicitação: ${error.message}');
    }
  }

  Future<void> configureValidation({
    required int cityId,
    required int confirmations,
    required int rejections,
    required double radiusKm,
    required int durationHours,
    required int cooldownHours,
  }) async {
    await _supabase.rpc(
      'configure_validation_settings',
      params: {
        'target_city_id': cityId,
        'required_confirmations': confirmations,
        'required_rejections': rejections,
        'maximum_radius_km': radiusKm,
        'duration_hours': durationHours,
        'cooldown_hours': cooldownHours,
      },
    );
  }

  Future<ValidationSettingsInfo> fetchValidationSettings(int cityId) async {
    try {
      final citySettings = await _supabase
          .from('validation_settings')
          .select(
            'confirmations_required, rejections_required, radius_km, cycle_duration, initiator_cooldown',
          )
          .eq('city_id', cityId)
          .maybeSingle();
      final settings =
          citySettings ??
          await _supabase
              .from('validation_settings')
              .select(
                'confirmations_required, rejections_required, radius_km, cycle_duration, initiator_cooldown',
              )
              .isFilter('city_id', null)
              .single();
      return ValidationSettingsInfo(
        confirmations: (settings['confirmations_required'] as num).toInt(),
        rejections: (settings['rejections_required'] as num).toInt(),
        radiusKm: (settings['radius_km'] as num).toDouble(),
        durationHours: _intervalHours(settings['cycle_duration']),
        cooldownHours: _intervalHours(settings['initiator_cooldown']),
      );
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao carregar parâmetros de validação: ${error.message}',
      );
    }
  }

  Future<void> rolloverMunicipalAdministration({
    required int cityId,
    required String name,
    required String mayorName,
    required DateTime startsOn,
    DateTime? endsOn,
  }) async {
    try {
      await _supabase.rpc(
        'rollover_municipal_administration',
        params: {
          'target_city_id': cityId,
          'administration_name': name.trim(),
          'mayor_name': mayorName.trim(),
          'starts_on': _dateOnly(startsOn),
          'ends_on': endsOn == null ? null : _dateOnly(endsOn),
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao registrar nova gestão: ${error.message}');
    }
  }

  Future<void> mergeOccurrences({
    required int primaryOccurrenceId,
    required int duplicateOccurrenceId,
    required String reason,
  }) async {
    await _supabase.rpc(
      'merge_duplicate_occurrences',
      params: {
        'primary_occurrence_id': primaryOccurrenceId,
        'duplicate_occurrence_id': duplicateOccurrenceId,
        'merge_reason': reason.trim(),
      },
    );
  }

  Future<void> setOccurrenceJurisdiction({
    required int occurrenceId,
    required String jurisdiction,
    required String externalResponsible,
    required String reason,
  }) async {
    await _supabase.rpc(
      'set_occurrence_jurisdiction',
      params: {
        'target_occurrence_id': occurrenceId,
        'jurisdiction': jurisdiction,
        'external_responsible': externalResponsible.trim(),
        'change_reason': reason.trim(),
      },
    );
  }

  Future<void> upsertProblemCategory({
    int? categoryId,
    required String name,
    required String slug,
    required String description,
  }) async {
    await _supabase.rpc(
      'upsert_problem_category',
      params: {
        'target_category_id': categoryId,
        'category_name': name.trim(),
        'category_slug': slug.trim().toLowerCase(),
        'category_description': description.trim(),
      },
    );
  }

  Future<void> configureAgencyResponsibility({
    required int cityId,
    required int categoryId,
    required int agencyId,
    required String reason,
  }) async {
    await _supabase.rpc(
      'configure_agency_responsibility',
      params: {
        'target_city_id': cityId,
        'target_category_id': categoryId,
        'target_agency_id': agencyId,
        'change_reason': reason.trim(),
      },
    );
  }

  Future<void> setCategoryResolutionEvidence({
    required int categoryId,
    required bool required,
  }) {
    return _guard(() async {
      await _supabase.rpc(
        'set_category_resolution_evidence',
        params: {
          'target_category_id': categoryId,
          'evidence_required': required,
        },
      );
    }, 'Não foi possível atualizar a categoria.');
  }

  int _intervalHours(Object? value) {
    final raw = value?.toString().trim() ?? '';
    final days = RegExp(r'(-?\d+)\s+days?').firstMatch(raw);
    final time = RegExp(r'(-?\d+):(\d+)(?::\d+(?:\.\d+)?)?').firstMatch(raw);
    if (days != null || time != null) {
      return (int.tryParse(days?.group(1) ?? '0') ?? 0) * 24 +
          (int.tryParse(time?.group(1) ?? '0') ?? 0);
    }
    final hours = RegExp(r'(-?\d+)\s+hours?').firstMatch(raw);
    return int.tryParse(hours?.group(1) ?? raw) ?? 0;
  }

  String _dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);
}
