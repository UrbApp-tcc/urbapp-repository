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
