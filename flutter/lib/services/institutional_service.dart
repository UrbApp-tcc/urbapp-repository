import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InstitutionalAccess {
  const InstitutionalAccess({
    required this.platformRoles,
    required this.administrationMemberships,
    required this.agencyMemberships,
    this.councilorProfileId,
    this.councilorName,
  });

  final Set<String> platformRoles;
  final List<String> administrationMemberships;
  final List<String> agencyMemberships;
  final int? councilorProfileId;
  final String? councilorName;

  bool get isPlatformAdmin =>
      platformRoles.contains('admin') || platformRoles.contains('moderator');
  bool get hasInstitutionalRole =>
      administrationMemberships.isNotEmpty || agencyMemberships.isNotEmpty;
}

class OccurrenceActorCapabilities {
  const OccurrenceActorCapabilities({
    required this.occurrenceId,
    required this.cityId,
    required this.canActForAdministration,
    required this.canActForAgency,
    required this.isEligibleCouncilor,
    this.agencyId,
    this.councilorFollowingId,
    this.councilorFollowingStatus,
  });

  final int occurrenceId;
  final int cityId;
  final int? agencyId;
  final bool canActForAdministration;
  final bool canActForAgency;
  final bool isEligibleCouncilor;
  final int? councilorFollowingId;
  final String? councilorFollowingStatus;

  bool get hasActiveCouncilorFollowing =>
      councilorFollowingId != null &&
      councilorFollowingStatus != 'ended' &&
      councilorFollowingStatus != 'resolved';
}

class InstitutionalAgencyOption {
  const InstitutionalAgencyOption({required this.id, required this.name});

  final int id;
  final String name;
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
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.occurrenceId,
    this.postTitle,
  });

  final int id;
  final int targetId;
  final int? occurrenceId;
  final String reason;
  final String status;
  final String? postTitle;
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

  Future<InstitutionalAccess> fetchMyAccess() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const InstitutionalAccess(
        platformRoles: {},
        administrationMemberships: [],
        agencyMemberships: [],
      );
    }

    try {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('platform_user_roles')
            .select('role')
            .eq('user_id', userId),
        _supabase
            .from('administration_users')
            .select(
              'role, municipal_administrations!administration_users_administration_id_fkey(name)',
            )
            .eq('user_id', userId)
            .eq('is_active', true),
        _supabase
            .from('agency_users')
            .select('role, public_agencies!agency_users_agency_id_fkey(name)')
            .eq('user_id', userId)
            .eq('is_active', true),
        _supabase
            .from('councilor_profiles')
            .select('id, public_name')
            .eq('profile_id', userId)
            .inFilter('profile_status', ['verified', 'participant'])
            .maybeSingle(),
      ]);

      return InstitutionalAccess(
        platformRoles: (responses[0] as List<dynamic>)
            .map((item) => (item as Map<String, dynamic>)['role'] as String)
            .toSet(),
        administrationMemberships: (responses[1] as List<dynamic>)
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final administration =
                  item['municipal_administrations'] as Map<String, dynamic>?;
              return '${administration?['name'] ?? 'Gestão municipal'} · ${item['role']}';
            })
            .toList(),
        agencyMemberships: (responses[2] as List<dynamic>)
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final agency = item['public_agencies'] as Map<String, dynamic>?;
              return '${agency?['name'] ?? 'Órgão municipal'} · ${item['role']}';
            })
            .toList(),
        councilorProfileId:
            ((responses[3] as Map<String, dynamic>?)?['id'] as num?)?.toInt(),
        councilorName:
            (responses[3] as Map<String, dynamic>?)?['public_name'] as String?,
      );
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao carregar acessos institucionais: ${error.message}',
      );
    }
  }

  Future<OccurrenceActorCapabilities> fetchCapabilitiesForPost(
    int postId,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    final post = await _supabase
        .from('posts')
        .select(
          'occurrence_id, occurrences(administration_id, agency_id, city_id)',
        )
        .eq('id', postId)
        .single();
    final occurrenceId = (post['occurrence_id'] as num).toInt();
    final occurrence = post['occurrences'] as Map<String, dynamic>;

    if (userId == null) {
      return OccurrenceActorCapabilities(
        occurrenceId: occurrenceId,
        cityId: (occurrence['city_id'] as num).toInt(),
        agencyId: (occurrence['agency_id'] as num?)?.toInt(),
        canActForAdministration: false,
        canActForAgency: false,
        isEligibleCouncilor: false,
      );
    }

    final administrationId = (occurrence['administration_id'] as num).toInt();
    final agencyId = (occurrence['agency_id'] as num?)?.toInt();
    final cityId = (occurrence['city_id'] as num).toInt();

    final responses = await Future.wait<dynamic>([
      _supabase
          .from('administration_users')
          .select('user_id')
          .eq('administration_id', administrationId)
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle(),
      agencyId == null
          ? Future<Map<String, dynamic>?>.value(null)
          : _supabase
                .from('agency_users')
                .select('user_id')
                .eq('agency_id', agencyId)
                .eq('user_id', userId)
                .eq('is_active', true)
                .maybeSingle(),
      _supabase
          .from('councilor_profiles')
          .select('id')
          .eq('profile_id', userId)
          .eq('city_id', cityId)
          .inFilter('profile_status', ['verified', 'participant'])
          .lte(
            'mandate_starts_on',
            DateTime.now().toIso8601String().substring(0, 10),
          )
          .gte(
            'mandate_ends_on',
            DateTime.now().toIso8601String().substring(0, 10),
          )
          .maybeSingle(),
    ]);

    final councilorId = ((responses[2] as Map<String, dynamic>?)?['id'] as num?)
        ?.toInt();
    int? followingId;
    String? followingStatus;
    if (councilorId != null) {
      final following = await _supabase
          .from('councilor_followings')
          .select('id, status')
          .eq('occurrence_id', occurrenceId)
          .eq('councilor_profile_id', councilorId)
          .maybeSingle();
      followingId = (following?['id'] as num?)?.toInt();
      followingStatus = following?['status'] as String?;
    }

    return OccurrenceActorCapabilities(
      occurrenceId: occurrenceId,
      cityId: cityId,
      agencyId: agencyId,
      canActForAdministration: responses[0] != null,
      canActForAgency: responses[1] != null,
      isEligibleCouncilor: councilorId != null,
      councilorFollowingId: followingId,
      councilorFollowingStatus: followingStatus,
    );
  }

  Future<void> registerInstitutionalAction({
    required int occurrenceId,
    required String actionType,
    required String description,
    int? targetAgencyId,
    DateTime? forecastAt,
    String? evidenceStoragePath,
  }) async {
    try {
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
    } on PostgrestException catch (error) {
      throw Exception('Erro ao registrar ação oficial: ${error.message}');
    }
  }

  Future<List<InstitutionalAgencyOption>> fetchAgenciesForCity(
    int cityId,
  ) async {
    try {
      final response = await _supabase
          .from('public_agencies')
          .select('id, name')
          .eq('city_id', cityId)
          .order('name');
      return (response as List<dynamic>)
          .map((raw) => raw as Map<String, dynamic>)
          .map(
            (row) => InstitutionalAgencyOption(
              id: (row['id'] as num).toInt(),
              name: row['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar órgãos: ${error.message}');
    }
  }

  Future<int> startCouncilorFollowing(int occurrenceId) async {
    try {
      final response = await _supabase.rpc(
        'start_councilor_following',
        params: {'target_occurrence_id': occurrenceId},
      );
      return (response as num).toInt();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao iniciar acompanhamento: ${error.message}');
    }
  }

  Future<void> registerCouncilorAction({
    required int followingId,
    required String actionType,
    required String description,
    String? evidenceStoragePath,
  }) async {
    try {
      await _supabase.rpc(
        'register_councilor_action',
        params: {
          'target_following_id': followingId,
          'councilor_action_type': actionType,
          'action_description': description.trim(),
          'evidence_storage_path': evidenceStoragePath,
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao registrar atuação: ${error.message}');
    }
  }

  Future<String> uploadActionEvidence({
    required int occurrenceId,
    required XFile file,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Entre na sua conta para anexar uma evidência.');
    }
    final extension = file.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension)) {
      throw Exception('Selecione uma imagem válida como evidência.');
    }
    final path =
        'occurrences/$occurrenceId/institutional/'
        '${DateTime.now().microsecondsSinceEpoch}.$extension';
    try {
      await _supabase.storage
          .from('post-images')
          .uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: false,
              contentType: switch (extension) {
                'png' => 'image/png',
                'gif' => 'image/gif',
                'webp' => 'image/webp',
                _ => 'image/jpeg',
              },
            ),
          );
      return path;
    } on StorageException catch (error) {
      throw Exception('Erro ao enviar evidência: ${error.message}');
    }
  }

  Future<void> deleteActionEvidence(String storagePath) async {
    try {
      await _supabase.storage.from('post-images').remove([storagePath]);
    } catch (_) {
      // Limpeza compensatória: a falha original da ação continua prioritária.
    }
  }

  Future<void> endCouncilorFollowing({
    required int followingId,
    required String description,
  }) async {
    try {
      await _supabase.rpc(
        'end_councilor_following',
        params: {
          'target_following_id': followingId,
          'closing_description': description.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao encerrar acompanhamento: ${error.message}');
    }
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
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    try {
      await _supabase.from('councilor_profile_requests').insert({
        'requester_user_id': userId,
        'city_id': cityId,
        'public_name': publicName.trim(),
        'party': party.trim().isEmpty ? null : party.trim(),
        'mandate_starts_on': _dateOnly(mandateStartsOn),
        'mandate_ends_on': _dateOnly(mandateEndsOn),
        'institutional_email': institutionalEmail.trim().toLowerCase(),
        'proof_summary': proofSummary.trim(),
        'proof_links': proofLinks?.trim().isEmpty == true
            ? null
            : proofLinks?.trim(),
      });
    } on PostgrestException catch (error) {
      throw Exception('Erro ao enviar solicitação: ${error.message}');
    }
  }

  Future<List<ModerationQueueItem>> fetchModerationQueue() async {
    try {
      final response = await _supabase
          .from('moderation_reports')
          .select('id, target_id, occurrence_id, reason, status, created_at')
          .inFilter('status', ['pending', 'in_analysis'])
          .order('created_at');
      final rows = response as List<dynamic>;
      final targetIds = rows
          .map(
            (item) =>
                ((item as Map<String, dynamic>)['target_id'] as num).toInt(),
          )
          .toSet()
          .toList();
      final titles = <int, String>{};
      if (targetIds.isNotEmpty) {
        final posts = await _supabase
            .from('posts')
            .select('id, title')
            .inFilter('id', targetIds);
        for (final raw in posts as List<dynamic>) {
          final item = raw as Map<String, dynamic>;
          titles[(item['id'] as num).toInt()] = item['title'] as String;
        }
      }

      return rows
          .map((item) => item as Map<String, dynamic>)
          .map(
            (item) => ModerationQueueItem(
              id: (item['id'] as num).toInt(),
              targetId: (item['target_id'] as num).toInt(),
              occurrenceId: (item['occurrence_id'] as num?)?.toInt(),
              reason: item['reason'] as String,
              status: item['status'] as String,
              postTitle: titles[(item['target_id'] as num).toInt()],
              createdAt: DateTime.parse(item['created_at'] as String),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar moderação: ${error.message}');
    }
  }

  Future<void> startModerationReview(int reportId) async {
    await _supabase.rpc(
      'start_moderation_review',
      params: {'target_report_id': reportId},
    );
  }

  Future<void> reviewModerationReport({
    required int reportId,
    required bool uphold,
    required String notes,
    required bool invalidateWholeOccurrence,
  }) async {
    try {
      await _supabase.rpc(
        'review_moderation_report',
        params: {
          'target_report_id': reportId,
          'decision': uphold ? 'upheld' : 'dismissed',
          'notes': notes.trim(),
          'invalidate_whole_occurrence': invalidateWholeOccurrence,
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao concluir moderação: ${error.message}');
    }
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
            .order('created_at'),
        _supabase
            .from('councilor_profile_requests')
            .select(
              'id, public_name, institutional_email, proof_summary, created_at, cities(name)',
            )
            .eq('status', 'pending')
            .order('created_at'),
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
