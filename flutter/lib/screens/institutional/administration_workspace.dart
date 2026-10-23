import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../logic/administration_workspace_rules.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../occurrence/occurrence_sheets.dart';
import '../transparency/transparency_widgets.dart';

/// Área operacional da Prefeitura. A visão pública da gestão permanece na
/// aba Transparência; este espaço reúne apenas acompanhamento e coordenação.
class AdministrationWorkspace extends StatefulWidget {
  const AdministrationWorkspace({super.key, required this.membership});

  final InstitutionalMembership membership;

  @override
  State<AdministrationWorkspace> createState() =>
      _AdministrationWorkspaceState();
}

class _AdministrationWorkspaceState extends State<AdministrationWorkspace> {
  final _searchController = TextEditingController();
  List<AdministrationDemandItem> _items = const [];
  AdministrationProfile? _metrics;
  AdministrationQueueFilter _filter = AdministrationQueueFilter.all;
  AdministrationDemandOrder _order = AdministrationDemandOrder.attention;
  int? _agencyId;
  int? _categoryId;
  String? _neighborhood;
  int _section = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        OccurrenceService().fetchByAdministration(widget.membership.id),
        TransparencyService().fetchAdministration(widget.membership.id),
      ]);
      final occurrences = results[0] as List<Occurrence>;
      final contexts = await InstitutionalService()
          .fetchAdministrationOccurrenceContexts(
            widget.membership.id,
            occurrences.map((item) => item.id),
          );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final occurrence in occurrences)
            AdministrationDemandItem(
              occurrence: occurrence,
              context:
                  contexts[occurrence.id] ??
                  const AdministrationOccurrenceContext(),
            ),
        ];
        _metrics = results[1] as AdministrationProfile?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AdministrationDemandItem> get _visibleItems =>
      filterAdministrationDemands(
        _items,
        query: _searchController.text,
        filter: _filter,
        order: _order,
        agencyId: _agencyId,
        categoryId: _categoryId,
        neighborhood: _neighborhood,
      );

  int get _advancedFilterCount =>
      [
        _agencyId,
        _categoryId,
        _neighborhood,
      ].where((value) => value != null).length +
      (_order == AdministrationDemandOrder.attention ? 0 : 1);

  void _showQueue({AdministrationQueueFilter? filter}) {
    setState(() {
      _section = 1;
      if (filter != null) _filter = filter;
    });
  }

  Future<void> _openDemand(AdministrationDemandItem item) async {
    await openOccurrence(
      context,
      occurrenceId: item.occurrence.id,
      initial: item.occurrence,
    );
    if (mounted) await _load();
  }

  Future<void> _registerQuickAction(
    AdministrationDemandItem item,
    String actionType,
  ) async {
    final registered = await showInstitutionalActionSheet(
      context,
      occurrence: item.occurrence,
      actor: 'administration',
      initialActionType: actionType,
    );
    if (registered && mounted) {
      showUrbToast(context, 'Ação da gestão registrada com sucesso.');
      await _load();
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _filter = AdministrationQueueFilter.all;
      _order = AdministrationDemandOrder.attention;
      _agencyId = null;
      _categoryId = null;
      _neighborhood = null;
    });
  }

  Future<void> _showAdvancedFilters() async {
    var agencyId = _agencyId;
    var categoryId = _categoryId;
    var neighborhood = _neighborhood;
    var order = _order;
    final agencies = <int, String>{
      for (final item in _items)
        if (item.occurrence.agencyId != null &&
            item.occurrence.agencyName != null)
          item.occurrence.agencyId!: item.occurrence.agencyName!,
    };
    final categories = <int, String>{
      for (final item in _items)
        item.occurrence.categoryId: item.occurrence.categoryName,
    };
    final neighborhoods =
        _items
            .map((item) => item.occurrence.neighborhood)
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filtrar e ordenar demandas', style: UrbText.h3),
                const SizedBox(height: 18),
                _FilterDropdown<int>(
                  label: 'Órgão responsável',
                  value: agencyId,
                  allLabel: 'Todos os órgãos',
                  entries: agencies.entries.toList()
                    ..sort((a, b) => a.value.compareTo(b.value)),
                  onChanged: (value) => setSheetState(() => agencyId = value),
                ),
                const SizedBox(height: 14),
                _FilterDropdown<int>(
                  label: 'Categoria',
                  value: categoryId,
                  allLabel: 'Todas as categorias',
                  entries: categories.entries.toList()
                    ..sort((a, b) => a.value.compareTo(b.value)),
                  onChanged: (value) => setSheetState(() => categoryId = value),
                ),
                const SizedBox(height: 14),
                _FilterDropdown<String>(
                  label: 'Bairro',
                  value: neighborhood,
                  allLabel: 'Todos os bairros',
                  entries: [
                    for (final value in neighborhoods) MapEntry(value, value),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => neighborhood = value),
                ),
                const SizedBox(height: 14),
                Text('Ordenação', style: UrbText.label),
                const SizedBox(height: 8),
                DropdownButtonFormField<AdministrationDemandOrder>(
                  initialValue: order,
                  decoration: const InputDecoration(),
                  items: [
                    for (final value in AdministrationDemandOrder.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => order = value);
                  },
                ),
                const SizedBox(height: 20),
                UrbButton(
                  label: 'Aplicar filtros',
                  expand: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _agencyId = agencyId;
        _categoryId = categoryId;
        _neighborhood = neighborhood;
        _order = order;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const UrbLoadingView();
    if (_error != null) return UrbErrorState(message: _error!, onRetry: _load);
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final section in const [
                  (0, 'Visão geral'),
                  (1, 'Demandas'),
                  (2, 'Órgãos'),
                  (3, 'Previsões'),
                ]) ...[
                  UrbChip(
                    label: section.$2,
                    selected: _section == section.$1,
                    onTap: () => setState(() => _section = section.$1),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_section) {
            0 => _buildOverview(),
            1 => _buildQueue(),
            2 => _buildAgencies(),
            _ => _buildForecasts(),
          },
        ),
      ],
    );
  }

  Widget _buildOverview() {
    final metrics = _metrics;
    final attention = filterAdministrationDemands(
      _items,
      filter: AdministrationQueueFilter.needsAttention,
    );
    final withoutManagement = _items
        .where((item) => item.context.latestAdministrationAction == null)
        .length;
    final withoutAgency = _items
        .where((item) => item.context.latestAgencyAction == null)
        .length;
    final reopened = _items
        .where((item) => item.occurrence.status.name == 'reopened')
        .length;
    final overdue = _items
        .where(
          (item) =>
              administrationForecastIsOverdue(item.context, DateTime.now()),
        )
        .length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          TransSection(
            white: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metrics?.title ?? widget.membership.name,
                            style: UrbText.h3,
                          ),
                          Text(
                            metrics?.periodLabel ?? 'Gestão municipal',
                            style: UrbText.label.copyWith(
                              color: UrbColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    UrbTextButton(
                      'Perfil público',
                      onPressed: () => openAdministration(
                        context,
                        administrationId: widget.membership.id,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                UrbStatRow(
                  items: [
                    UrbStatItem(
                      '${metrics?.active ?? _items.length}',
                      'demandas ativas',
                    ),
                    UrbStatItem(
                      '${metrics?.prioritized ?? _items.where((item) => item.occurrence.administrativePriority).length}',
                      'priorizadas',
                    ),
                    UrbStatItem(
                      '${metrics?.conclusionsInformed ?? 0}',
                      'conclusões informadas',
                    ),
                  ],
                ),
              ],
            ),
          ),
          TransSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TransEyebrow(
                  'Precisa de atenção',
                  subtitle:
                      '${attention.length} demandas com algum sinal operacional',
                  trailing: UrbTextButton(
                    'Ver fila',
                    onPressed: () => _showQueue(
                      filter: AdministrationQueueFilter.needsAttention,
                    ),
                  ),
                ),
                _AttentionSummaryRow(
                  label: 'Sem manifestação da gestão',
                  count: withoutManagement,
                  onTap: () => _showQueue(
                    filter: AdministrationQueueFilter.withoutManagementResponse,
                  ),
                ),
                _AttentionSummaryRow(
                  label: 'Órgão sem atualização',
                  count: withoutAgency,
                  onTap: () => _showQueue(
                    filter: AdministrationQueueFilter.needsAttention,
                  ),
                ),
                _AttentionSummaryRow(
                  label: 'Previsão vencida',
                  count: overdue,
                  onTap: () => _showQueue(
                    filter: AdministrationQueueFilter.needsAttention,
                  ),
                ),
                _AttentionSummaryRow(
                  label: 'Ocorrência reaberta',
                  count: reopened,
                  last: true,
                  onTap: () =>
                      _showQueue(filter: AdministrationQueueFilter.reopened),
                ),
              ],
            ),
          ),
          TransSection(
            last: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TransEyebrow(
                  'Próximas ações',
                  subtitle: 'Demandas ordenadas pelos sinais de atenção',
                  trailing: UrbTextButton('Ver todas', onPressed: _showQueue),
                ),
                if (attention.isEmpty)
                  Text(
                    'Nenhuma providência pendente foi identificada.',
                    style: UrbText.caption,
                  )
                else
                  for (var index = 0; index < attention.take(5).length; index++)
                    _DemandRow(
                      item: attention[index],
                      onTap: () => _openDemand(attention[index]),
                      onQuickAction: (action) =>
                          _registerQuickAction(attention[index], action),
                      last: index == attention.take(5).length - 1,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueue() {
    final visible = _visibleItems;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          UrbTextField(
            controller: _searchController,
            hint: 'Buscar por título, rua, bairro, categoria ou órgão',
            prefix: const Padding(
              padding: EdgeInsets.all(14),
              child: UrbIcon(UrbIcons.search, size: 17, color: UrbColors.muted),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in AdministrationQueueFilter.values) ...[
                  UrbChip(
                    label: value.label,
                    selected: _filter == value,
                    onTap: () => setState(() => _filter = value),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} ${visible.length == 1 ? 'demanda encontrada' : 'demandas encontradas'} · ${_order.label}',
                  style: UrbText.caption,
                ),
              ),
              UrbButton(
                label: _advancedFilterCount == 0
                    ? 'Filtros'
                    : 'Filtros · $_advancedFilterCount',
                icon: UrbIcons.filter,
                tone: UrbButtonTone.outline,
                height: 38,
                onPressed: _showAdvancedFilters,
              ),
            ],
          ),
          if (_advancedFilterCount > 0 ||
              _filter != AdministrationQueueFilter.all ||
              _searchController.text.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: UrbTextButton('Limpar filtros', onPressed: _clearFilters),
            ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const UrbEmptyState(
              icon: UrbIcons.search,
              title: 'Nenhuma demanda encontrada',
              message:
                  'Ajuste a busca ou os filtros para consultar outras demandas.',
            )
          else
            for (var index = 0; index < visible.length; index++)
              _DemandRow(
                item: visible[index],
                onTap: () => _openDemand(visible[index]),
                onQuickAction: (action) =>
                    _registerQuickAction(visible[index], action),
                last: index == visible.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _buildAgencies() {
    final summaries = buildAdministrationAgencySummaries(_items);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Text('Coordenação dos órgãos', style: UrbText.h3),
          const SizedBox(height: 4),
          Text(
            'Acompanhe a distribuição das demandas e identifique onde é preciso cobrar atualização.',
            style: UrbText.bodySmall,
          ),
          const SizedBox(height: 18),
          if (summaries.isEmpty)
            const UrbEmptyState(
              icon: UrbIcons.building,
              title: 'Nenhum órgão na fila',
              message: 'As demandas encaminhadas aparecerão aqui.',
            )
          else
            for (var index = 0; index < summaries.length; index++)
              _AgencySummaryRow(
                summary: summaries[index],
                last: index == summaries.length - 1,
                onTap: () {
                  setState(() {
                    _agencyId = summaries[index].agencyId;
                    _section = 1;
                  });
                },
              ),
        ],
      ),
    );
  }

  Widget _buildForecasts() {
    final groups = groupAdministrationForecasts(_items);
    final total = groups.values.fold<int>(
      0,
      (sum, items) => sum + items.length,
    );
    final overdue = groups[AdministrationForecastGroup.overdue]!.length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Text('Controle de previsões', style: UrbText.h3),
          const SizedBox(height: 4),
          Text(
            'Consulte os prazos informados e atualize previsões vencidas ou próximas.',
            style: UrbText.bodySmall,
          ),
          const SizedBox(height: 16),
          UrbStatRow(
            items: [
              UrbStatItem('$total', 'com previsão'),
              UrbStatItem('$overdue', 'vencidas'),
              UrbStatItem(
                '${groups[AdministrationForecastGroup.nextSevenDays]!.length}',
                'próximos 7 dias',
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (total == 0)
            const UrbEmptyState(
              icon: UrbIcons.clock,
              title: 'Nenhuma previsão informada',
              message:
                  'Registre uma previsão nas ações rápidas de uma demanda.',
            )
          else
            for (final group in AdministrationForecastGroup.values)
              if (groups[group]!.isNotEmpty) ...[
                TransEyebrow(
                  group.label,
                  subtitle:
                      '${groups[group]!.length} ${groups[group]!.length == 1 ? 'demanda' : 'demandas'}',
                ),
                for (var index = 0; index < groups[group]!.length; index++)
                  _DemandRow(
                    item: groups[group]![index],
                    contextNote:
                        'Previsão: ${formatDate(groups[group]![index].context.latestForecast!.forecastAt!)}',
                    onTap: () => _openDemand(groups[group]![index]),
                    onQuickAction: (action) =>
                        _registerQuickAction(groups[group]![index], action),
                    last: index == groups[group]!.length - 1,
                  ),
                const SizedBox(height: 22),
              ],
        ],
      ),
    );
  }
}

class _DemandRow extends StatelessWidget {
  const _DemandRow({
    required this.item,
    required this.onTap,
    required this.onQuickAction,
    this.last = false,
    this.contextNote,
  });

  final AdministrationDemandItem item;
  final VoidCallback onTap;
  final ValueChanged<String> onQuickAction;
  final bool last;
  final String? contextNote;

  @override
  Widget build(BuildContext context) {
    final occurrence = item.occurrence;
    final signals = administrationAttentionSignals(item);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: UrbColors.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    occurrence.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(occurrence.status, compact: true),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: PopupMenuButton<String>(
                        tooltip: 'Ações rápidas',
                        padding: EdgeInsets.zero,
                        icon: const UrbIcon(
                          UrbIcons.more,
                          size: 18,
                          color: UrbColors.muted,
                        ),
                        onSelected: onQuickAction,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: occurrence.administrativePriority
                                ? 'priority_removed'
                                : 'priority',
                            child: Text(
                              occurrence.administrativePriority
                                  ? 'Retirar prioridade'
                                  : 'Priorizar',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'forwarding',
                            child: Text('Encaminhar a outro órgão'),
                          ),
                          const PopupMenuItem(
                            value: 'request',
                            child: Text('Solicitar providências'),
                          ),
                          const PopupMenuItem(
                            value: 'official_position',
                            child: Text('Registrar manifestação'),
                          ),
                          const PopupMenuItem(
                            value: 'forecast',
                            child: Text('Informar previsão'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              [
                occurrence.locationLabel,
                occurrence.agencyName ?? 'Sem órgão definido',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UrbText.caption,
            ),
            if (contextNote != null) ...[
              const SizedBox(height: 5),
              Text(
                contextNote!,
                style: UrbText.caption.copyWith(
                  color: UrbColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              '${occurrence.supportsCount} ${occurrence.supportsCount == 1 ? 'apoio' : 'apoios'} · criada ${formatRelativeTime(occurrence.createdAt).toLowerCase()}',
              style: UrbText.caption,
            ),
            if (signals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final signal in signals.take(3))
                    UrbChip(label: signal.label, dotColor: UrbColors.warning),
                ],
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                const UrbIcon(UrbIcons.arrow, size: 14, color: UrbColors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Próxima ação: ${administrationNextAction(item)}',
                    style: UrbText.caption.copyWith(
                      color: UrbColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AgencySummaryRow extends StatelessWidget {
  const _AgencySummaryRow({
    required this.summary,
    required this.onTap,
    this.last = false,
  });

  final AdministrationAgencySummary summary;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: UrbColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(summary.agencyName, style: UrbText.titleSmall),
              ),
              const UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.active} ativas · ${summary.inProgress} em andamento · ${summary.awaitingValidation} em validação',
            style: UrbText.caption,
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (summary.withoutUpdate > 0)
                UrbChip(
                  label: '${summary.withoutUpdate} sem atualização',
                  dotColor: UrbColors.warning,
                ),
              if (summary.overdue > 0)
                UrbChip(
                  label: '${summary.overdue} com previsão vencida',
                  dotColor: UrbColors.danger,
                ),
              if (summary.lastUpdateAt != null)
                UrbChip(
                  label:
                      'Última atualização ${formatRelativeTime(summary.lastUpdateAt!).toLowerCase()}',
                  dotColor: UrbColors.success,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AttentionSummaryRow extends StatelessWidget {
  const _AttentionSummaryRow({
    required this.label,
    required this.count,
    required this.onTap,
    this.last = false,
  });

  final String label;
  final int count;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => UrbDotRow(
    title: label,
    subtitle: count == 1 ? '1 demanda' : '$count demandas',
    dotColor: count > 0 ? UrbColors.warning : UrbColors.success,
    onTap: onTap,
    last: last,
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.allLabel,
    required this.entries,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final String allLabel;
  final List<MapEntry<T, String>> entries;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: UrbText.label),
      const SizedBox(height: 8),
      DropdownButtonFormField<T?>(
        initialValue: value,
        decoration: const InputDecoration(),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
          for (final entry in entries)
            DropdownMenuItem<T?>(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}
