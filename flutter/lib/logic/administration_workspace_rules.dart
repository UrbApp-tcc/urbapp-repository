import '../domain/models.dart';
import '../domain/occurrence_status.dart';
import '../services/institutional_service.dart';

class AdministrationDemandItem {
  const AdministrationDemandItem({
    required this.occurrence,
    required this.context,
  });

  final Occurrence occurrence;
  final AdministrationOccurrenceContext context;
}

class AdministrationAttentionSignal {
  const AdministrationAttentionSignal(this.code, this.label);

  final String code;
  final String label;
}

class AdministrationAgencySummary {
  const AdministrationAgencySummary({
    required this.agencyId,
    required this.agencyName,
    required this.active,
    required this.withoutUpdate,
    required this.inProgress,
    required this.overdue,
    required this.awaitingValidation,
    this.lastUpdateAt,
  });

  final int? agencyId;
  final String agencyName;
  final int active;
  final int withoutUpdate;
  final int inProgress;
  final int overdue;
  final int awaitingValidation;
  final DateTime? lastUpdateAt;
}

enum AdministrationForecastGroup {
  overdue('Vencidas'),
  today('Para hoje'),
  nextSevenDays('Próximos 7 dias'),
  future('Futuras');

  const AdministrationForecastGroup(this.label);

  final String label;
}

enum AdministrationQueueFilter {
  all('Todas'),
  needsAttention('Precisam de atenção'),
  withoutManagementResponse('Sem manifestação'),
  prioritized('Priorizadas'),
  open('Abertas'),
  inAnalysis('Em análise'),
  inProgress('Em andamento'),
  awaitingValidation('Em validação'),
  reopened('Reabertas');

  const AdministrationQueueFilter(this.label);

  final String label;
}

enum AdministrationDemandOrder {
  attention('Mais urgentes'),
  oldest('Mais antigas'),
  newest('Mais recentes'),
  supports('Mais apoiadas'),
  inactive('Sem atualização há mais tempo');

  const AdministrationDemandOrder(this.label);

  final String label;
}

bool administrationForecastIsOverdue(
  AdministrationOccurrenceContext context,
  DateTime now,
) {
  final forecast = context.latestForecast?.forecastAt;
  return forecast != null && forecast.isBefore(now);
}

List<AdministrationAttentionSignal> administrationAttentionSignals(
  AdministrationDemandItem item, {
  DateTime? now,
}) {
  final occurrence = item.occurrence;
  final context = item.context;
  final reference = now ?? DateTime.now();
  final lastActivity =
      context.lastOfficialActivityAt ??
      occurrence.lastActivityAt ??
      occurrence.createdAt;
  final signals = <AdministrationAttentionSignal>[];

  if (context.latestAdministrationAction == null) {
    signals.add(
      const AdministrationAttentionSignal(
        'without_management_response',
        'Sem manifestação da gestão',
      ),
    );
  }
  if (context.latestAgencyAction == null) {
    signals.add(
      const AdministrationAttentionSignal(
        'without_agency_response',
        'Órgão sem atualização',
      ),
    );
  }
  if (occurrence.supportsCount >= 5 || occurrence.reportsCount >= 3) {
    signals.add(
      const AdministrationAttentionSignal(
        'high_mobilization',
        'Alta mobilização',
      ),
    );
  }
  if (reference.difference(lastActivity).inDays >= 7) {
    signals.add(
      AdministrationAttentionSignal(
        'stale',
        'Sem atualização há ${reference.difference(lastActivity).inDays} dias',
      ),
    );
  }
  if (administrationForecastIsOverdue(context, reference)) {
    signals.add(
      const AdministrationAttentionSignal(
        'overdue_forecast',
        'Previsão vencida',
      ),
    );
  }
  if (occurrence.status == OccurrenceStatus.reopened) {
    signals.add(
      const AdministrationAttentionSignal('reopened', 'Ocorrência reaberta'),
    );
  }
  return signals;
}

String administrationNextAction(
  AdministrationDemandItem item, {
  DateTime? now,
}) {
  final occurrence = item.occurrence;
  final context = item.context;
  final reference = now ?? DateTime.now();

  if (occurrence.status == OccurrenceStatus.awaitingValidation) {
    return 'Acompanhar a validação comunitária';
  }
  if (occurrence.status == OccurrenceStatus.reopened) {
    return 'Reavaliar e solicitar nova providência';
  }
  if (context.latestAdministrationAction == null) {
    return 'Registrar manifestação da gestão';
  }
  if (context.latestAgencyAction == null) {
    return 'Solicitar retorno ao órgão responsável';
  }
  if (administrationForecastIsOverdue(context, reference)) {
    return 'Atualizar a previsão de atendimento';
  }
  return switch (occurrence.status) {
    OccurrenceStatus.open => 'Analisar e encaminhar a demanda',
    OccurrenceStatus.inAnalysis => 'Acompanhar a análise e informar previsão',
    OccurrenceStatus.inProgress => 'Acompanhar a execução do serviço',
    OccurrenceStatus.resolved => 'Consultar o resultado da validação',
    OccurrenceStatus.closed => 'Consultar o encerramento',
    _ => 'Consultar os detalhes da demanda',
  };
}

List<AdministrationDemandItem> filterAdministrationDemands(
  Iterable<AdministrationDemandItem> source, {
  String query = '',
  AdministrationQueueFilter filter = AdministrationQueueFilter.all,
  AdministrationDemandOrder order = AdministrationDemandOrder.attention,
  int? agencyId,
  int? categoryId,
  String? neighborhood,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final normalizedQuery = query.trim().toLowerCase();
  final items = source.where((item) {
    final occurrence = item.occurrence;
    final searchable = [
      occurrence.title,
      occurrence.street,
      occurrence.neighborhood,
      occurrence.categoryName,
      occurrence.agencyName,
    ].whereType<String>().join(' ').toLowerCase();
    if (normalizedQuery.isNotEmpty && !searchable.contains(normalizedQuery)) {
      return false;
    }
    if (agencyId != null && occurrence.agencyId != agencyId) return false;
    if (categoryId != null && occurrence.categoryId != categoryId) return false;
    if (neighborhood != null && occurrence.neighborhood != neighborhood) {
      return false;
    }
    return switch (filter) {
      AdministrationQueueFilter.all => true,
      AdministrationQueueFilter.needsAttention =>
        administrationAttentionSignals(item, now: reference).isNotEmpty,
      AdministrationQueueFilter.withoutManagementResponse =>
        item.context.latestAdministrationAction == null,
      AdministrationQueueFilter.prioritized =>
        occurrence.administrativePriority,
      AdministrationQueueFilter.open =>
        occurrence.status == OccurrenceStatus.open,
      AdministrationQueueFilter.inAnalysis =>
        occurrence.status == OccurrenceStatus.inAnalysis,
      AdministrationQueueFilter.inProgress =>
        occurrence.status == OccurrenceStatus.inProgress,
      AdministrationQueueFilter.awaitingValidation =>
        occurrence.status == OccurrenceStatus.awaitingValidation,
      AdministrationQueueFilter.reopened =>
        occurrence.status == OccurrenceStatus.reopened,
    };
  }).toList();

  int attentionScore(AdministrationDemandItem item) {
    final occurrence = item.occurrence;
    var score =
        administrationAttentionSignals(item, now: reference).length * 100;
    if (occurrence.administrativePriority) score += 80;
    score += occurrence.supportsCount.clamp(0, 50);
    return score;
  }

  items.sort(switch (order) {
    AdministrationDemandOrder.attention => (a, b) => attentionScore(
      b,
    ).compareTo(attentionScore(a)),
    AdministrationDemandOrder.oldest =>
      (a, b) => a.occurrence.createdAt.compareTo(b.occurrence.createdAt),
    AdministrationDemandOrder.newest =>
      (a, b) => b.occurrence.createdAt.compareTo(a.occurrence.createdAt),
    AdministrationDemandOrder.supports =>
      (a, b) =>
          b.occurrence.supportsCount.compareTo(a.occurrence.supportsCount),
    AdministrationDemandOrder.inactive => (a, b) {
      final aDate =
          a.context.lastOfficialActivityAt ??
          a.occurrence.lastActivityAt ??
          a.occurrence.createdAt;
      final bDate =
          b.context.lastOfficialActivityAt ??
          b.occurrence.lastActivityAt ??
          b.occurrence.createdAt;
      return aDate.compareTo(bDate);
    },
  });
  return items;
}

List<AdministrationAgencySummary> buildAdministrationAgencySummaries(
  Iterable<AdministrationDemandItem> source, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final groups = <int?, List<AdministrationDemandItem>>{};
  for (final item in source) {
    groups.putIfAbsent(item.occurrence.agencyId, () => []).add(item);
  }

  final summaries = groups.entries.map((entry) {
    final items = entry.value;
    final updates =
        items
            .map((item) => item.context.latestAgencyAction?.createdAt)
            .whereType<DateTime>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return AdministrationAgencySummary(
      agencyId: entry.key,
      agencyName: items.first.occurrence.agencyName ?? 'Sem órgão definido',
      active: items.length,
      withoutUpdate: items
          .where((item) => item.context.latestAgencyAction == null)
          .length,
      inProgress: items
          .where(
            (item) => item.occurrence.status == OccurrenceStatus.inProgress,
          )
          .length,
      overdue: items
          .where(
            (item) => administrationForecastIsOverdue(item.context, reference),
          )
          .length,
      awaitingValidation: items
          .where(
            (item) =>
                item.occurrence.status == OccurrenceStatus.awaitingValidation,
          )
          .length,
      lastUpdateAt: updates.firstOrNull,
    );
  }).toList();
  summaries.sort((a, b) {
    final attentionA = a.withoutUpdate + a.overdue;
    final attentionB = b.withoutUpdate + b.overdue;
    final byAttention = attentionB.compareTo(attentionA);
    return byAttention != 0
        ? byAttention
        : a.agencyName.compareTo(b.agencyName);
  });
  return summaries;
}

Map<AdministrationForecastGroup, List<AdministrationDemandItem>>
groupAdministrationForecasts(
  Iterable<AdministrationDemandItem> source, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final tomorrow = today.add(const Duration(days: 1));
  final nextWeek = tomorrow.add(const Duration(days: 7));
  final result = {
    for (final group in AdministrationForecastGroup.values)
      group: <AdministrationDemandItem>[],
  };
  for (final item in source) {
    final forecast = item.context.latestForecast?.forecastAt;
    if (forecast == null) continue;
    final day = DateTime(forecast.year, forecast.month, forecast.day);
    final group = day.isBefore(today)
        ? AdministrationForecastGroup.overdue
        : day.isBefore(tomorrow)
        ? AdministrationForecastGroup.today
        : day.isBefore(nextWeek)
        ? AdministrationForecastGroup.nextSevenDays
        : AdministrationForecastGroup.future;
    result[group]!.add(item);
  }
  for (final items in result.values) {
    items.sort(
      (a, b) => a.context.latestForecast!.forecastAt!.compareTo(
        b.context.latestForecast!.forecastAt!,
      ),
    );
  }
  return result;
}
