import 'package:supabase_flutter/supabase_flutter.dart';

class AdministrationIndicator {
  const AdministrationIndicator({
    required this.id,
    required this.name,
    required this.mayorName,
    required this.startsOn,
    required this.endsOn,
    required this.isPlaceholder,
    required this.isVerified,
    required this.registered,
    required this.inherited,
    required this.active,
    required this.leftPending,
    required this.resolved,
    required this.manifested,
    required this.prioritized,
    required this.forwarded,
    required this.forecasted,
    required this.conclusions,
    required this.confirmedConclusions,
    required this.rejectedConclusions,
    required this.averageFirstResponseSeconds,
    required this.averageConclusionSeconds,
  });

  final int id;
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
  final int resolved;
  final int manifested;
  final int prioritized;
  final int forwarded;
  final int forecasted;
  final int conclusions;
  final int confirmedConclusions;
  final int rejectedConclusions;
  final double? averageFirstResponseSeconds;
  final double? averageConclusionSeconds;
}

class AgencyIndicator {
  const AgencyIndicator({
    required this.id,
    required this.name,
    required this.profileStatus,
    required this.assigned,
    required this.open,
    required this.inProgress,
    required this.awaitingValidation,
    required this.resolved,
    required this.officialActions,
    required this.officiallyAnswered,
    required this.officialResponsePercentage,
    required this.conclusions,
    required this.confirmedConclusions,
    required this.rejectedConclusions,
    required this.averageResponsibilitySeconds,
    required this.medianResponsibilitySeconds,
    required this.averageFirstResponseSeconds,
    required this.categoriesCount,
    required this.neighborhoodsCount,
  });

  final int id;
  final String name;
  final String profileStatus;
  final int assigned;
  final int open;
  final int inProgress;
  final int awaitingValidation;
  final int resolved;
  final int officialActions;
  final int officiallyAnswered;
  final double officialResponsePercentage;
  final int conclusions;
  final int confirmedConclusions;
  final int rejectedConclusions;
  final double? averageResponsibilitySeconds;
  final double? medianResponsibilitySeconds;
  final double? averageFirstResponseSeconds;
  final int categoriesCount;
  final int neighborhoodsCount;
}

class CouncilorIndicator {
  const CouncilorIndicator({
    required this.id,
    required this.name,
    required this.party,
    required this.profileStatus,
    required this.followed,
    required this.actions,
    required this.reachedResolution,
    required this.forwardingActions,
    required this.chargeActions,
    required this.officialLetters,
    required this.awaitingResponse,
    required this.openDemands,
    required this.endedWithoutResolution,
    required this.averageFollowupSeconds,
  });

  final int id;
  final String name;
  final String? party;
  final String profileStatus;
  final int followed;
  final int actions;
  final int reachedResolution;
  final int forwardingActions;
  final int chargeActions;
  final int officialLetters;
  final int awaitingResponse;
  final int openDemands;
  final int endedWithoutResolution;
  final double? averageFollowupSeconds;
}

class InstitutionalIndicatorBundle {
  const InstitutionalIndicatorBundle({
    required this.administrations,
    required this.agencies,
    required this.councilors,
  });

  final List<AdministrationIndicator> administrations;
  final List<AgencyIndicator> agencies;
  final List<CouncilorIndicator> councilors;
}

class InstitutionalIndicatorService {
  InstitutionalIndicatorService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<InstitutionalIndicatorBundle> fetchForCity(int cityId) async {
    try {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('administration_occurrence_metrics')
            .select()
            .eq('city_id', cityId)
            .order('starts_on', ascending: false),
        _supabase
            .from('agency_occurrence_metrics')
            .select()
            .eq('city_id', cityId)
            .order('assigned_occurrences', ascending: false),
        _supabase
            .from('councilor_activity_metrics')
            .select()
            .eq('city_id', cityId)
            .order('registered_actions', ascending: false),
      ]);

      return InstitutionalIndicatorBundle(
        administrations: (responses[0] as List<dynamic>)
            .map((row) => _administration(row as Map<String, dynamic>))
            .toList(),
        agencies: (responses[1] as List<dynamic>)
            .map((row) => _agency(row as Map<String, dynamic>))
            .toList(),
        councilors: (responses[2] as List<dynamic>)
            .map((row) => _councilor(row as Map<String, dynamic>))
            .toList(),
      );
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao carregar indicadores institucionais: ${error.message}',
      );
    }
  }

  AdministrationIndicator _administration(Map<String, dynamic> row) {
    return AdministrationIndicator(
      id: _integer(row, 'administration_id'),
      name: row['name'] as String? ?? 'Gestão municipal',
      mayorName: row['mayor_name'] as String?,
      startsOn: DateTime.parse(row['starts_on'] as String),
      endsOn: _date(row['ends_on']),
      isPlaceholder: row['is_placeholder'] as bool? ?? false,
      isVerified: row['is_verified'] as bool? ?? false,
      registered: _integer(row, 'registered_during_period'),
      inherited: _integer(row, 'inherited_occurrences'),
      active: _integer(row, 'active_occurrences'),
      leftPending: _integer(row, 'left_pending_occurrences'),
      resolved: _integer(row, 'resolved_during_period'),
      manifested: _integer(row, 'manifested_occurrences'),
      prioritized: _integer(row, 'prioritized_occurrences'),
      forwarded: _integer(row, 'forwarded_occurrences'),
      forecasted: _integer(row, 'forecasted_occurrences'),
      conclusions: _integer(row, 'conclusions_informed'),
      confirmedConclusions: _integer(row, 'confirmed_conclusions'),
      rejectedConclusions: _integer(row, 'rejected_conclusions'),
      averageFirstResponseSeconds: _decimal(
        row,
        'average_seconds_to_first_manifestation',
      ),
      averageConclusionSeconds: _decimal(row, 'average_seconds_to_conclusion'),
    );
  }

  AgencyIndicator _agency(Map<String, dynamic> row) {
    return AgencyIndicator(
      id: _integer(row, 'agency_id'),
      name: row['name'] as String? ?? 'Órgão municipal',
      profileStatus: row['profile_status'] as String? ?? 'unclaimed',
      assigned: _integer(row, 'assigned_occurrences'),
      open: _integer(row, 'open_occurrences'),
      inProgress: _integer(row, 'in_progress_occurrences'),
      awaitingValidation: _integer(row, 'awaiting_validation_occurrences'),
      resolved: _integer(row, 'resolved_occurrences'),
      officialActions: _integer(row, 'official_actions'),
      officiallyAnswered: _integer(row, 'officially_answered_occurrences'),
      officialResponsePercentage:
          _decimal(row, 'official_response_percentage') ?? 0,
      conclusions: _integer(row, 'conclusions_informed'),
      confirmedConclusions: _integer(row, 'confirmed_conclusions'),
      rejectedConclusions: _integer(row, 'rejected_conclusions'),
      averageResponsibilitySeconds: _decimal(
        row,
        'average_responsibility_seconds',
      ),
      medianResponsibilitySeconds: _decimal(
        row,
        'median_responsibility_seconds',
      ),
      averageFirstResponseSeconds: _decimal(
        row,
        'average_seconds_to_first_response',
      ),
      categoriesCount: _integer(row, 'categories_count'),
      neighborhoodsCount: _integer(row, 'neighborhoods_count'),
    );
  }

  CouncilorIndicator _councilor(Map<String, dynamic> row) {
    return CouncilorIndicator(
      id: _integer(row, 'councilor_profile_id'),
      name: row['public_name'] as String? ?? 'Vereador',
      party: row['party'] as String?,
      profileStatus: row['profile_status'] as String? ?? 'verified',
      followed: _integer(row, 'followed_demands'),
      actions: _integer(row, 'registered_actions'),
      reachedResolution: _integer(
        row,
        'followed_demands_that_reached_resolution',
      ),
      forwardingActions: _integer(row, 'forwarding_actions'),
      chargeActions: _integer(row, 'charge_actions'),
      officialLetters: _integer(row, 'official_letters'),
      awaitingResponse: _integer(row, 'awaiting_response_demands'),
      openDemands: _integer(row, 'followed_open_demands'),
      endedWithoutResolution: _integer(row, 'ended_without_resolution'),
      averageFollowupSeconds: _decimal(row, 'average_followup_seconds'),
    );
  }

  int _integer(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toInt() ?? 0;

  double? _decimal(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble();

  DateTime? _date(dynamic value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}
