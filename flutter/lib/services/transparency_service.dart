import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../utils/error_formatter.dart';

int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
double? _doubleOrNull(dynamic value) => (value as num?)?.toDouble();

class Breakdown {
  const Breakdown(this.label, this.total, this.resolved);

  final String label;
  final int total;
  final int resolved;
}

class MonthlyPoint {
  const MonthlyPoint(this.month, this.registered, this.resolved);

  final DateTime month;
  final int registered;
  final int resolved;
}

/// Indicadores contínuos da cidade (spec §33, §44.6): não reiniciam com a
/// troca de gestão. Uma ocorrência conta uma vez; duplicatas absorvidas,
/// invalidadas e fora da competência municipal ficam de fora.
class CityPanorama {
  const CityPanorama({
    required this.cityId,
    required this.cityName,
    this.stateCode = '',
    this.averageResolutionSeconds,
    this.inAnalysis = 0,
    this.inProgressOnly = 0,
    this.reopened = 0,
    this.closed = 0,
    required this.total,
    required this.resolved,
    required this.open,
    required this.inProgress,
    required this.awaitingValidation,
    required this.outsideMunicipal,
    required this.resolutionRate,
    this.medianResolutionSeconds,
    this.categories = const [],
    this.neighborhoods = const [],
    this.monthly = const [],
  });

  final int cityId;
  final String cityName;
  final String stateCode;
  final int total;
  final int resolved;
  final int open;

  /// Em análise, em andamento e reabertas, somadas (resumo da Transparência).
  final int inProgress;

  /// Indicador complementar; o ranking de cidades usa a mediana.
  final double? averageResolutionSeconds;
  final int inAnalysis;
  final int inProgressOnly;
  final int reopened;

  /// Encerradas sem resolução por motivo administrativo (seguem no universo).
  final int closed;
  final int awaitingValidation;
  final int outsideMunicipal;
  final double resolutionRate;
  final double? medianResolutionSeconds;
  final List<Breakdown> categories;
  final List<Breakdown> neighborhoods;
  final List<MonthlyPoint> monthly;
}

/// Gestão Municipal vinculada a um período (spec §11, §33).
class AdministrationProfile {
  const AdministrationProfile({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.name,
    this.mayorName,
    required this.startsOn,
    this.endsOn,
    required this.isPlaceholder,
    required this.isVerified,
    required this.registered,
    required this.inherited,
    required this.active,
    required this.leftPending,
    required this.resolvedDuringPeriod,
    required this.manifested,
    required this.prioritized,
    required this.forwarded,
    required this.forecasted,
    required this.conclusionsInformed,
    required this.confirmedConclusions,
    required this.rejectedConclusions,
    this.averageFirstManifestationSeconds,
    this.averageConclusionSeconds,
  });

  final int id;
  final int cityId;
  final String cityName;
  final String name;
  final String? mayorName;
  final DateTime startsOn;
  final DateTime? endsOn;
  final bool isPlaceholder;
  final bool isVerified;
  final int registered;
  final int inherited;
  final int active;
  final int leftPending;
  final int resolvedDuringPeriod;
  final int manifested;
  final int prioritized;
  final int forwarded;
  final int forecasted;
  final int conclusionsInformed;
  final int confirmedConclusions;
  final int rejectedConclusions;
  final double? averageFirstManifestationSeconds;
  final double? averageConclusionSeconds;

  String get periodLabel {
    if (isPlaceholder) return 'Gestão vigente';
    return 'Gestão ${startsOn.year}–${endsOn?.year ?? 'atual'}';
  }

  String get title => 'Prefeitura de $cityName';

  double get manifestationRate {
    final base = registered + inherited;
    return base == 0 ? 0 : manifested / base * 100;
  }

  factory AdministrationProfile.fromJson(Map<String, dynamic> json, String cityName) => AdministrationProfile(
        id: _int(json['administration_id']),
        cityId: _int(json['city_id']),
        cityName: cityName,
        name: json['name'] as String? ?? '',
        mayorName: json['mayor_name'] as String?,
        startsOn: DateTime.parse(json['starts_on'] as String),
        endsOn: json['ends_on'] == null ? null : DateTime.parse(json['ends_on'] as String),
        isPlaceholder: json['is_placeholder'] == true,
        isVerified: json['is_verified'] == true,
        registered: _int(json['registered_during_period']),
        inherited: _int(json['inherited_occurrences']),
        active: _int(json['active_occurrences']),
        leftPending: _int(json['left_pending_occurrences']),
        resolvedDuringPeriod: _int(json['resolved_during_period']),
        manifested: _int(json['manifested_occurrences']),
        prioritized: _int(json['prioritized_occurrences']),
        forwarded: _int(json['forwarded_occurrences']),
        forecasted: _int(json['forecasted_occurrences']),
        conclusionsInformed: _int(json['conclusions_informed']),
        confirmedConclusions: _int(json['confirmed_conclusions']),
        rejectedConclusions: _int(json['rejected_conclusions']),
        averageFirstManifestationSeconds: _doubleOrNull(json['average_seconds_to_first_manifestation']),
        averageConclusionSeconds: _doubleOrNull(json['average_seconds_to_conclusion']),
      );
}

/// Órgão municipal: indicadores calculados pelo UrbApp (spec §12).
class AgencyProfile {
  const AgencyProfile({
    required this.id,
    required this.cityId,
    required this.name,
    this.type,
    required this.status,
    required this.assigned,
    required this.resolved,
    required this.open,
    required this.inProgress,
    required this.awaitingValidation,
    required this.officialActions,
    required this.officialResponsePercentage,
    required this.conclusionsInformed,
    required this.confirmedConclusions,
    required this.rejectedConclusions,
    this.medianResponsibilitySeconds,
    this.averageFirstResponseSeconds,
    this.categories = const [],
  });

  final int id;
  final int cityId;
  final String name;
  final String? type;
  final InstitutionalProfileStatus status;
  final int assigned;
  final int resolved;
  final int open;
  final int inProgress;
  final int awaitingValidation;
  final int officialActions;
  final double officialResponsePercentage;
  final int conclusionsInformed;
  final int confirmedConclusions;
  final int rejectedConclusions;
  final double? medianResponsibilitySeconds;
  final double? averageFirstResponseSeconds;
  final List<String> categories;

  int get current => open + inProgress + awaitingValidation;

  String get abbreviation {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && word[0] == word[0].toUpperCase())
        .toList();
    if (words.isEmpty) return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
    return words.take(4).map((word) => word[0]).join().toUpperCase();
  }

  factory AgencyProfile.fromJson(Map<String, dynamic> json, {String? type, List<String> categories = const []}) =>
      AgencyProfile(
        id: _int(json['agency_id']),
        cityId: _int(json['city_id']),
        name: json['name'] as String? ?? '',
        type: type,
        status: InstitutionalProfileStatus.fromCode(json['profile_status'] as String?),
        assigned: _int(json['assigned_occurrences']),
        resolved: _int(json['resolved_occurrences']),
        open: _int(json['open_occurrences']),
        inProgress: _int(json['in_progress_occurrences']),
        awaitingValidation: _int(json['awaiting_validation_occurrences']),
        officialActions: _int(json['official_actions']),
        officialResponsePercentage: (json['official_response_percentage'] as num?)?.toDouble() ?? 0,
        conclusionsInformed: _int(json['conclusions_informed']),
        confirmedConclusions: _int(json['confirmed_conclusions']),
        rejectedConclusions: _int(json['rejected_conclusions']),
        medianResponsibilitySeconds: _doubleOrNull(json['median_responsibility_seconds']),
        averageFirstResponseSeconds: _doubleOrNull(json['average_seconds_to_first_response']),
        categories: categories,
      );
}

/// Vereador: atividade factual na plataforma, sem notas ou rankings (spec §13).
class CouncilorProfile {
  const CouncilorProfile({
    required this.id,
    required this.cityId,
    required this.publicName,
    this.party,
    required this.status,
    this.mandateStartsOn,
    this.mandateEndsOn,
    required this.followed,
    required this.followedOpen,
    required this.registeredActions,
    required this.awaitingResponse,
    required this.reachedResolution,
    required this.endedWithoutResolution,
    required this.forwardingActions,
    required this.chargeActions,
    required this.officialLetters,
    this.averageFollowupSeconds,
  });

  final int id;
  final int cityId;
  final String publicName;
  final String? party;
  final InstitutionalProfileStatus status;
  final DateTime? mandateStartsOn;
  final DateTime? mandateEndsOn;
  final int followed;
  final int followedOpen;
  final int registeredActions;
  final int awaitingResponse;
  final int reachedResolution;
  final int endedWithoutResolution;
  final int forwardingActions;
  final int chargeActions;
  final int officialLetters;
  final double? averageFollowupSeconds;

  String get mandateLabel {
    if (mandateStartsOn == null) return '';
    return 'Mandato ${mandateStartsOn!.year}–${mandateEndsOn?.year ?? ''}';
  }
}

class InstitutionSearchResult {
  const InstitutionSearchResult({required this.kind, required this.id, required this.name, this.detail});

  /// `agency` ou `councilor`.
  final String kind;
  final int id;
  final String name;
  final String? detail;
}

class InstitutionalActivity {
  const InstitutionalActivity({
    required this.occurrenceId,
    required this.actionType,
    required this.description,
    required this.createdAt,
    this.occurrence,
  });

  final int occurrenceId;
  final String actionType;
  final String description;
  final DateTime createdAt;
  final Occurrence? occurrence;

  InstitutionalActivity withOccurrence(Occurrence? value) => InstitutionalActivity(
        occurrenceId: occurrenceId,
        actionType: actionType,
        description: description,
        createdAt: createdAt,
        occurrence: value,
      );
}

/// Transparência: panorama da cidade, Gestão Municipal, órgãos e vereadores.
class TransparencyService {
  TransparencyService({SupabaseClient? supabase}) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<T> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw Exception(friendlyBackendMessage(error.message, fallback));
    }
  }

  Future<CityPanorama> fetchCityPanorama(int cityId, {bool detailed = false}) {
    return _guard(() async {
      final metrics = await _supabase.from('city_occurrence_metrics').select().eq('city_id', cityId).single();
      var categories = <Breakdown>[];
      var neighborhoods = <Breakdown>[];
      var monthly = <MonthlyPoint>[];
      if (detailed) {
        final responses = await Future.wait<dynamic>([
          _supabase
              .from('city_category_metrics')
              .select('category_name, occurrences_count, resolved_count')
              .eq('city_id', cityId)
              .order('occurrences_count', ascending: false)
              .limit(8),
          _supabase
              .from('city_neighborhood_metrics')
              .select('neighborhood, occurrences_count, resolved_count')
              .eq('city_id', cityId)
              .order('occurrences_count', ascending: false)
              .limit(8),
          _supabase
              .from('city_monthly_metrics')
              .select('month, registered_count, resolved_count')
              .eq('city_id', cityId)
              .order('month', ascending: false)
              .limit(12),
        ]);
        categories = (responses[0] as List)
            .map((row) => Breakdown(row['category_name'] as String? ?? 'Outros', _int(row['occurrences_count']),
                _int(row['resolved_count'])))
            .toList();
        neighborhoods = (responses[1] as List)
            .map((row) => Breakdown(row['neighborhood'] as String? ?? 'Não informado',
                _int(row['occurrences_count']), _int(row['resolved_count'])))
            .toList();
        monthly = (responses[2] as List)
            .map((row) => MonthlyPoint(
                DateTime.parse(row['month'] as String), _int(row['registered_count']), _int(row['resolved_count'])))
            .toList()
            .reversed
            .toList();
      }
      return CityPanorama(
        cityId: cityId,
        cityName: metrics['city_name'] as String? ?? '',
        stateCode: (metrics['state'] as String? ?? '').toUpperCase(),
        averageResolutionSeconds: _doubleOrNull(metrics['average_resolution_seconds']),
        inAnalysis: _int(metrics['in_analysis_occurrences']),
        inProgressOnly: _int(metrics['in_progress_occurrences']),
        reopened: _int(metrics['reopened_occurrences']),
        closed: _int(metrics['closed_occurrences']),
        total: _int(metrics['total_occurrences']),
        resolved: _int(metrics['resolved_occurrences']),
        open: _int(metrics['open_occurrences']),
        inProgress: _int(metrics['active_occurrences']),
        awaitingValidation: _int(metrics['awaiting_validation_occurrences']),
        outsideMunicipal: _int(metrics['outside_municipal_occurrences']),
        resolutionRate: (metrics['resolution_rate'] as num?)?.toDouble() ?? 0,
        medianResolutionSeconds: _doubleOrNull(metrics['median_resolution_seconds']),
        categories: categories,
        neighborhoods: neighborhoods,
        monthly: monthly,
      );
    }, 'Não foi possível carregar o panorama da cidade.');
  }

  Future<String> _cityName(int cityId) async {
    final city = await _supabase.from('cities').select('name').eq('id', cityId).single();
    return city['name'] as String;
  }

  Future<AdministrationProfile?> fetchCurrentAdministration(int cityId) {
    return _guard(() async {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await _supabase
          .from('administration_occurrence_metrics')
          .select()
          .eq('city_id', cityId)
          .lte('starts_on', today)
          .order('starts_on', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return AdministrationProfile.fromJson(Map<String, dynamic>.from(rows.first as Map), await _cityName(cityId));
    }, 'Não foi possível carregar a gestão municipal.');
  }

  Future<List<AdministrationProfile>> fetchAdministrationHistory(int cityId) {
    return _guard(() async {
      final rows = await _supabase
          .from('administration_occurrence_metrics')
          .select()
          .eq('city_id', cityId)
          .order('starts_on', ascending: false);
      final cityName = await _cityName(cityId);
      return (rows as List)
          .map((row) => AdministrationProfile.fromJson(Map<String, dynamic>.from(row as Map), cityName))
          .toList();
    }, 'Não foi possível carregar as gestões.');
  }

  Future<AdministrationProfile?> fetchAdministration(int administrationId) {
    return _guard(() async {
      final row = await _supabase
          .from('administration_occurrence_metrics')
          .select()
          .eq('administration_id', administrationId)
          .maybeSingle();
      if (row == null) return null;
      return AdministrationProfile.fromJson(row, await _cityName(_int(row['city_id'])));
    }, 'Não foi possível carregar a gestão municipal.');
  }

  /// Órgãos em ordem alfabética: a ordem não sugere classificação (spec §44.6).
  Future<List<AgencyProfile>> fetchAgencies(int cityId) {
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase.from('agency_occurrence_metrics').select().eq('city_id', cityId).order('name', ascending: true),
        _supabase.from('public_agencies').select('id').eq('city_id', cityId).eq('type', 'generic'),
      ]);
      // O órgão genérico só existe para não deixar categorias sem vínculo;
      // aparece na lista apenas quando de fato tem ocorrências.
      final generic = {for (final row in responses[1] as List) _int(row['id'])};
      return (responses[0] as List)
          .map((row) => AgencyProfile.fromJson(Map<String, dynamic>.from(row as Map)))
          .where((agency) => !generic.contains(agency.id) || agency.assigned > 0)
          .toList();
    }, 'Não foi possível carregar os órgãos públicos.');
  }

  Future<AgencyProfile?> fetchAgency(int agencyId) {
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase.from('agency_occurrence_metrics').select().eq('agency_id', agencyId).maybeSingle(),
        _supabase.from('public_agencies').select('type').eq('id', agencyId).maybeSingle(),
        _supabase
            .from('agency_responsibilities')
            .select('problem_categories(name)')
            .eq('agency_id', agencyId)
            .isFilter('ends_on', null),
      ]);
      final row = asJsonMap(responses[0]);
      if (row == null) return null;
      final categories = (responses[2] as List)
          .map((item) => asJsonMap(item['problem_categories'])?['name'] as String?)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
      return AgencyProfile.fromJson(row, type: asJsonMap(responses[1])?['type'] as String?, categories: categories);
    }, 'Não foi possível carregar o órgão.');
  }

  Future<List<InstitutionalActivity>> fetchAgencyActivity(int agencyId, {int limit = 10}) {
    return _guard(() async {
      final rows = await _supabase
          .from('institutional_actions')
          .select('occurrence_id, action_type, description, created_at')
          .eq('agency_id', agencyId)
          .eq('actor_kind', 'agency')
          .order('created_at', ascending: false)
          .limit(limit);
      return _activities(rows as List);
    }, 'Não foi possível carregar as atualizações oficiais.');
  }

  Future<List<InstitutionalActivity>> fetchAdministrationActivity(int administrationId, {int limit = 10}) {
    return _guard(() async {
      final rows = await _supabase
          .from('institutional_actions')
          .select('occurrence_id, action_type, description, created_at')
          .eq('administration_id', administrationId)
          .eq('actor_kind', 'administration')
          .order('created_at', ascending: false)
          .limit(limit);
      return _activities(rows as List);
    }, 'Não foi possível carregar a atuação da gestão.');
  }

  /// Vereadores em ordem alfabética (sem ranking político).
  Future<List<CouncilorProfile>> fetchCouncilors(int cityId) {
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('councilor_activity_metrics')
            .select()
            .eq('city_id', cityId)
            .inFilter('profile_status', ['verified', 'participant'])
            .order('public_name', ascending: true),
        _supabase
            .from('councilor_profiles')
            .select('id, mandate_starts_on, mandate_ends_on')
            .eq('city_id', cityId),
      ]);
      final mandates = {
        for (final row in responses[1] as List)
          _int(row['id']): (
            DateTime.tryParse(row['mandate_starts_on'] as String? ?? ''),
            DateTime.tryParse(row['mandate_ends_on'] as String? ?? ''),
          ),
      };
      return (responses[0] as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final mandate = mandates[_int(row['councilor_profile_id'])];
        return _councilor(row, mandate?.$1, mandate?.$2);
      }).toList();
    }, 'Não foi possível carregar os vereadores.');
  }

  Future<CouncilorProfile?> fetchCouncilor(int councilorProfileId) {
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase.from('councilor_activity_metrics').select().eq('councilor_profile_id', councilorProfileId).maybeSingle(),
        _supabase
            .from('councilor_profiles')
            .select('mandate_starts_on, mandate_ends_on')
            .eq('id', councilorProfileId)
            .maybeSingle(),
      ]);
      final row = asJsonMap(responses[0]);
      if (row == null) return null;
      final profile = asJsonMap(responses[1]);
      return _councilor(
        row,
        DateTime.tryParse(profile?['mandate_starts_on'] as String? ?? ''),
        DateTime.tryParse(profile?['mandate_ends_on'] as String? ?? ''),
      );
    }, 'Não foi possível carregar o vereador.');
  }

  CouncilorProfile _councilor(Map<String, dynamic> row, DateTime? starts, DateTime? ends) => CouncilorProfile(
        id: _int(row['councilor_profile_id']),
        cityId: _int(row['city_id']),
        publicName: row['public_name'] as String? ?? '',
        party: row['party'] as String?,
        status: InstitutionalProfileStatus.fromCode(row['profile_status'] as String?),
        mandateStartsOn: starts,
        mandateEndsOn: ends,
        followed: _int(row['followed_demands']),
        followedOpen: _int(row['followed_open_demands']),
        registeredActions: _int(row['registered_actions']),
        awaitingResponse: _int(row['awaiting_response_demands']),
        reachedResolution: _int(row['followed_demands_that_reached_resolution']),
        endedWithoutResolution: _int(row['ended_without_resolution']),
        forwardingActions: _int(row['forwarding_actions']),
        chargeActions: _int(row['charge_actions']),
        officialLetters: _int(row['official_letters']),
        averageFollowupSeconds: _doubleOrNull(row['average_followup_seconds']),
      );

  Future<List<InstitutionalActivity>> fetchCouncilorActivity(int councilorProfileId, {int limit = 10}) {
    return _guard(() async {
      final rows = await _supabase
          .from('councilor_actions')
          .select('action_type, description, created_at, councilor_followings!inner(occurrence_id, councilor_profile_id)')
          .eq('councilor_followings.councilor_profile_id', councilorProfileId)
          .order('created_at', ascending: false)
          .limit(limit);
      final mapped = (rows as List).map((raw) {
        final following = asJsonMap(raw['councilor_followings'])!;
        return {
          'occurrence_id': following['occurrence_id'],
          'action_type': raw['action_type'],
          'description': raw['description'],
          'created_at': raw['created_at'],
        };
      }).toList();
      return _activities(mapped);
    }, 'Não foi possível carregar a atuação do vereador.');
  }

  /// Busca pode localizar órgãos e vereadores, mas não é a única porta de
  /// descoberta institucional (spec §44.5).
  Future<List<InstitutionSearchResult>> searchInstitutions(int cityId, String query) {
    final term = query.trim().replaceAll(RegExp(r'[%_,()]'), ' ');
    if (term.length < 3) return Future.value(const []);
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase.from('public_agencies').select('id, name, type').eq('city_id', cityId).ilike('name', '%$term%').limit(5),
        _supabase
            .from('councilor_profiles')
            .select('id, public_name, party')
            .eq('city_id', cityId)
            .inFilter('profile_status', ['verified', 'participant'])
            .ilike('public_name', '%$term%')
            .limit(5),
      ]);
      return [
        for (final row in responses[0] as List)
          InstitutionSearchResult(kind: 'agency', id: _int(row['id']), name: row['name'] as String, detail: 'Órgão municipal'),
        for (final row in responses[1] as List)
          InstitutionSearchResult(
            kind: 'councilor',
            id: _int(row['id']),
            name: row['public_name'] as String,
            detail: ['Vereador', if (row['party'] != null) row['party'] as String].join(' · '),
          ),
      ];
    }, 'Não foi possível buscar instituições.');
  }

  Future<List<InstitutionalActivity>> _activities(List rows) async {
    return rows
        .map((row) => InstitutionalActivity(
              occurrenceId: _int(row['occurrence_id']),
              actionType: row['action_type'] as String? ?? '',
              description: row['description'] as String? ?? '',
              createdAt: DateTime.parse(row['created_at'] as String),
            ))
        .toList();
  }
}
