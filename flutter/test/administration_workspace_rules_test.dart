import 'package:flutter_test/flutter_test.dart';
import 'package:meu_app/domain/models.dart';
import 'package:meu_app/domain/occurrence_status.dart';
import 'package:meu_app/logic/administration_workspace_rules.dart';
import 'package:meu_app/services/institutional_service.dart';

Occurrence _occurrence({
  required int id,
  OccurrenceStatus status = OccurrenceStatus.open,
  DateTime? createdAt,
  String title = 'Buraco na avenida',
  String neighborhood = 'Centro',
  int supports = 0,
  int reports = 1,
  bool prioritized = false,
  int? agencyId = 10,
}) => Occurrence(
  id: id,
  title: title,
  status: status,
  createdAt: createdAt ?? DateTime(2026, 10, 1),
  latitude: -23.5,
  longitude: -47.4,
  street: 'Avenida Brasil',
  neighborhood: neighborhood,
  cityId: 1,
  cityName: 'Sorocaba',
  categoryId: 2,
  categoryName: 'Pavimentação',
  agencyId: agencyId,
  agencyName: agencyId == null ? null : 'Secretaria de Obras',
  administrationId: 1,
  supportsCount: supports,
  reportsCount: reports,
  administrativePriority: prioritized,
);

InstitutionalActionRecord _action({
  required int occurrenceId,
  required String actor,
  String type = 'official_position',
  DateTime? createdAt,
  DateTime? forecastAt,
}) => InstitutionalActionRecord(
  occurrenceId: occurrenceId,
  actorKind: actor,
  actionType: type,
  description: 'Atualização registrada.',
  createdAt: createdAt ?? DateTime(2026, 10, 20),
  forecastAt: forecastAt,
);

AdministrationDemandItem _item(
  Occurrence occurrence, {
  List<InstitutionalActionRecord> actions = const [],
}) => AdministrationDemandItem(
  occurrence: occurrence,
  context: AdministrationOccurrenceContext(actions: actions),
);

void main() {
  final now = DateTime(2026, 10, 23, 12);

  test('distingue manifestação da gestão de atualização do órgão', () {
    final item = _item(
      _occurrence(id: 1),
      actions: [_action(occurrenceId: 1, actor: 'agency')],
    );

    final signals = administrationAttentionSignals(item, now: now);

    expect(
      signals.map((signal) => signal.code),
      contains('without_management_response'),
    );
    expect(
      signals.map((signal) => signal.code),
      isNot(contains('without_agency_response')),
    );
    expect(
      administrationNextAction(item, now: now),
      'Registrar manifestação da gestão',
    );
  });

  test('identifica previsão vencida, inatividade e alta mobilização', () {
    final item = _item(
      _occurrence(id: 2, supports: 8, reports: 4),
      actions: [
        _action(
          occurrenceId: 2,
          actor: 'administration',
          type: 'forecast',
          createdAt: DateTime(2026, 10, 10),
          forecastAt: DateTime(2026, 10, 22),
        ),
        _action(
          occurrenceId: 2,
          actor: 'agency',
          createdAt: DateTime(2026, 10, 9),
        ),
      ],
    );

    final codes = administrationAttentionSignals(
      item,
      now: now,
    ).map((signal) => signal.code);

    expect(
      codes,
      containsAll(['overdue_forecast', 'stale', 'high_mobilization']),
    );
  });

  test('filtra a fila por texto, situação, órgão e prioridade', () {
    final prioritized = _item(
      _occurrence(
        id: 3,
        title: 'Árvore sobre a fiação',
        neighborhood: 'Vila Hortência',
        prioritized: true,
        agencyId: 20,
      ),
    );
    final regular = _item(_occurrence(id: 4));

    expect(
      filterAdministrationDemands([
        regular,
        prioritized,
      ], query: 'hortência').single.occurrence.id,
      3,
    );
    expect(
      filterAdministrationDemands(
        [regular, prioritized],
        filter: AdministrationQueueFilter.prioritized,
        agencyId: 20,
      ).single.occurrence.id,
      3,
    );
  });

  test('prioriza reabertura e validação na próxima ação', () {
    expect(
      administrationNextAction(
        _item(_occurrence(id: 5, status: OccurrenceStatus.reopened)),
        now: now,
      ),
      'Reavaliar e solicitar nova providência',
    );
    expect(
      administrationNextAction(
        _item(_occurrence(id: 6, status: OccurrenceStatus.awaitingValidation)),
        now: now,
      ),
      'Acompanhar a validação comunitária',
    );
  });

  test('consolida a carga e os alertas por órgão', () {
    final updated = _item(
      _occurrence(id: 7, agencyId: 20, status: OccurrenceStatus.inProgress),
      actions: [
        _action(
          occurrenceId: 7,
          actor: 'agency',
          createdAt: DateTime(2026, 10, 22),
        ),
      ],
    );
    final withoutUpdate = _item(
      _occurrence(id: 8, agencyId: 20),
      actions: [_action(occurrenceId: 8, actor: 'administration')],
    );

    final summary = buildAdministrationAgencySummaries([
      updated,
      withoutUpdate,
    ], now: now).single;

    expect(summary.active, 2);
    expect(summary.inProgress, 1);
    expect(summary.withoutUpdate, 1);
    expect(summary.lastUpdateAt, DateTime(2026, 10, 22));
  });

  test('agrupa previsões por vencimento e próximos sete dias', () {
    AdministrationDemandItem withForecast(int id, DateTime forecast) => _item(
      _occurrence(id: id),
      actions: [
        _action(
          occurrenceId: id,
          actor: 'administration',
          type: 'forecast',
          forecastAt: forecast,
        ),
      ],
    );

    final groups = groupAdministrationForecasts([
      withForecast(9, DateTime(2026, 10, 22)),
      withForecast(10, DateTime(2026, 10, 23)),
      withForecast(11, DateTime(2026, 10, 27)),
      withForecast(12, DateTime(2026, 12, 1)),
    ], now: now);

    expect(
      groups[AdministrationForecastGroup.overdue]!.single.occurrence.id,
      9,
    );
    expect(groups[AdministrationForecastGroup.today]!.single.occurrence.id, 10);
    expect(
      groups[AdministrationForecastGroup.nextSevenDays]!.single.occurrence.id,
      11,
    );
    expect(
      groups[AdministrationForecastGroup.future]!.single.occurrence.id,
      12,
    );
  });

  test('informa há quanto tempo a gestão ainda não respondeu', () {
    final item = _item(
      _occurrence(id: 13, createdAt: DateTime(2026, 10, 17)),
      actions: [_action(occurrenceId: 13, actor: 'agency')],
    );

    expect(
      administrationResponseWaitLabel(item, now: now),
      'Sem resposta da gestão há 6 dias',
    );
  });

  test('mantém atualização do órgão na fila sem manifestação da gestão', () {
    final item = _item(
      _occurrence(id: 14),
      actions: [_action(occurrenceId: 14, actor: 'agency')],
    );

    final filtered = filterAdministrationDemands(
      [item],
      filter: AdministrationQueueFilter.withoutManagementResponse,
      now: now,
    );

    expect(filtered.single.occurrence.id, 14);
  });

  test('resume os indicadores institucionais da tela inicial', () {
    final pending = _item(_occurrence(id: 17, prioritized: true));
    final forecast = _item(
      _occurrence(id: 18),
      actions: [
        _action(
          occurrenceId: 18,
          actor: 'administration',
          type: 'forecast',
          forecastAt: DateTime(2026, 10, 25),
        ),
        _action(occurrenceId: 18, actor: 'agency'),
      ],
    );

    final summary = buildAdministrationQuickSummary([
      pending,
      forecast,
    ], now: now);

    expect(summary.needsAttention, 1);
    expect(summary.withoutManagementResponse, 1);
    expect(summary.prioritized, 1);
    expect(summary.forecastLabel(now), '2 d');
  });

  test('ordena órgãos pelo indicador escolhido', () {
    final works = _item(
      _occurrence(id: 15, agencyId: 10),
      actions: [_action(occurrenceId: 15, actor: 'agency')],
    );
    final lighting = _item(
      _occurrence(id: 16, agencyId: 20, status: OccurrenceStatus.inProgress),
    );

    final summaries = buildAdministrationAgencySummaries(
      [works, lighting],
      now: now,
      order: AdministrationAgencyOrder.inProgress,
    );

    expect(summaries.first.agencyId, 20);
  });

  test('restringe ações oficiais no papel de consulta', () {
    const manager = InstitutionalMembership(
      id: 1,
      name: 'Prefeitura',
      cityId: 1,
      role: 'manager',
    );
    const analyst = InstitutionalMembership(
      id: 1,
      name: 'Prefeitura',
      cityId: 1,
      role: 'analyst',
    );

    expect(manager.canRegisterActions, isTrue);
    expect(manager.roleLabel, 'Gestor');
    expect(analyst.canRegisterActions, isFalse);
    expect(analyst.roleLabel, 'Consulta');
  });
}
