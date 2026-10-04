import 'package:supabase_flutter/supabase_flutter.dart';

class PublicCityMetrics {
  const PublicCityMetrics({
    required this.cityId,
    required this.cityName,
    required this.totalOccurrences,
    required this.resolvedOccurrences,
    required this.openOccurrences,
    required this.activeOccurrences,
    required this.awaitingValidationOccurrences,
    required this.resolutionRate,
    required this.medianResolutionSeconds,
    required this.outsideMunicipalOccurrences,
  });

  final int cityId;
  final String cityName;
  final int totalOccurrences;
  final int resolvedOccurrences;
  final int openOccurrences;
  final int activeOccurrences;
  final int awaitingValidationOccurrences;
  final double resolutionRate;
  final double? medianResolutionSeconds;
  final int outsideMunicipalOccurrences;
}

class IndicatorBreakdown {
  const IndicatorBreakdown({
    required this.label,
    required this.total,
    required this.resolved,
  });

  final String label;
  final int total;
  final int resolved;
}

class MonthlyIndicator {
  const MonthlyIndicator({
    required this.month,
    required this.registered,
    required this.resolved,
  });

  final DateTime month;
  final int registered;
  final int resolved;
}

class CityIndicatorBundle {
  const CityIndicatorBundle({
    required this.metrics,
    required this.categories,
    required this.neighborhoods,
    required this.monthly,
  });

  final PublicCityMetrics metrics;
  final List<IndicatorBreakdown> categories;
  final List<IndicatorBreakdown> neighborhoods;
  final List<MonthlyIndicator> monthly;
}

class IndicatorService {
  IndicatorService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<CityIndicatorBundle> fetchCityIndicators(int cityId) async {
    try {
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('city_occurrence_metrics')
            .select()
            .eq('city_id', cityId)
            .single(),
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

      final metricsData = responses[0] as Map<String, dynamic>;
      return CityIndicatorBundle(
        metrics: PublicCityMetrics(
          cityId: (metricsData['city_id'] as num).toInt(),
          cityName: metricsData['city_name'] as String? ?? 'Cidade',
          totalOccurrences:
              (metricsData['total_occurrences'] as num?)?.toInt() ?? 0,
          resolvedOccurrences:
              (metricsData['resolved_occurrences'] as num?)?.toInt() ?? 0,
          openOccurrences:
              (metricsData['open_occurrences'] as num?)?.toInt() ?? 0,
          activeOccurrences:
              (metricsData['active_occurrences'] as num?)?.toInt() ?? 0,
          awaitingValidationOccurrences:
              (metricsData['awaiting_validation_occurrences'] as num?)
                  ?.toInt() ??
              0,
          resolutionRate:
              (metricsData['resolution_rate'] as num?)?.toDouble() ?? 0,
          medianResolutionSeconds:
              (metricsData['median_resolution_seconds'] as num?)?.toDouble(),
          outsideMunicipalOccurrences:
              (metricsData['outside_municipal_occurrences'] as num?)?.toInt() ??
              0,
        ),
        categories: _mapBreakdowns(
          responses[1] as List<dynamic>,
          'category_name',
        ),
        neighborhoods: _mapBreakdowns(
          responses[2] as List<dynamic>,
          'neighborhood',
        ),
        monthly: (responses[3] as List<dynamic>)
            .map((item) => item as Map<String, dynamic>)
            .map(
              (item) => MonthlyIndicator(
                month: DateTime.parse(item['month'] as String),
                registered: (item['registered_count'] as num).toInt(),
                resolved: (item['resolved_count'] as num).toInt(),
              ),
            )
            .toList()
            .reversed
            .toList(),
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar indicadores: ${error.message}');
    }
  }

  List<IndicatorBreakdown> _mapBreakdowns(List<dynamic> rows, String labelKey) {
    return rows
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => IndicatorBreakdown(
            label: item[labelKey] as String? ?? 'Não informado',
            total: (item['occurrences_count'] as num).toInt(),
            resolved: (item['resolved_count'] as num).toInt(),
          ),
        )
        .toList();
  }
}
