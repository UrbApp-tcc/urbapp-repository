import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../logic/administration_workspace_rules.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/file_download.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/occurrence_map.dart';
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
  static const _pageSize = 30;
  static const _quickFilters = [
    AdministrationQueueFilter.all,
    AdministrationQueueFilter.needsAttention,
    AdministrationQueueFilter.withoutManagementResponse,
    AdministrationQueueFilter.prioritized,
  ];
  final _searchController = TextEditingController();
  List<AdministrationDemandItem> _items = const [];
  Map<int, String> _citizenNames = const {};
  List<AdministrationCollaborator> _collaborators = const [];
  List<AdministrationActionHistoryItem> _history = const [];
  AdministrationProfile? _metrics;
  AdministrationQueueFilter _filter = AdministrationQueueFilter.all;
  AdministrationDemandOrder _order = AdministrationDemandOrder.attention;
  AdministrationAgencyOrder _agencyOrder = AdministrationAgencyOrder.attention;
  int? _agencyId;
  int? _categoryId;
  String? _neighborhood;
  String? _personKey;
  int? _selectedMapOccurrenceId;
  int _section = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _exporting = false;
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
      final service = InstitutionalService();
      final results = await Future.wait<dynamic>([
        OccurrenceService().fetchByAdministration(
          widget.membership.id,
          limit: _pageSize,
        ),
        TransparencyService().fetchAdministration(widget.membership.id),
        service.fetchAdministrationActionHistory(widget.membership.id),
      ]);
      final occurrences = results[0] as List<Occurrence>;
      final details = await Future.wait<dynamic>([
        service.fetchAdministrationOccurrenceContexts(
          widget.membership.id,
          occurrences.map((item) => item.id),
        ),
        service.fetchOccurrenceCitizenNames(occurrences.map((item) => item.id)),
        service.fetchAdministrationCollaborators(widget.membership.id),
      ]);
      final contexts = details[0] as Map<int, AdministrationOccurrenceContext>;
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
        _citizenNames = details[1] as Map<int, String>;
        _collaborators = details[2] as List<AdministrationCollaborator>;
        _history = results[2] as List<AdministrationActionHistoryItem>;
        _hasMore = occurrences.length == _pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ValueChanged<String>? _quickActionFor(AdministrationDemandItem item) =>
      widget.membership.canRegisterActions
      ? (action) => _registerQuickAction(item, action)
      : null;

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final occurrences = await OccurrenceService().fetchByAdministration(
        widget.membership.id,
        limit: _pageSize,
        offset: _items.length,
      );
      final service = InstitutionalService();
      final details = await Future.wait<dynamic>([
        service.fetchAdministrationOccurrenceContexts(
          widget.membership.id,
          occurrences.map((item) => item.id),
        ),
        service.fetchOccurrenceCitizenNames(occurrences.map((item) => item.id)),
      ]);
      final contexts = details[0] as Map<int, AdministrationOccurrenceContext>;
      if (!mounted) return;
      setState(() {
        _items = [
          ..._items,
          for (final occurrence in occurrences)
            AdministrationDemandItem(
              occurrence: occurrence,
              context:
                  contexts[occurrence.id] ??
                  const AdministrationOccurrenceContext(),
            ),
        ];
        _citizenNames = {..._citizenNames, ...details[1] as Map<int, String>};
        _hasMore = occurrences.length == _pageSize;
      });
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _csvCell(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';

  Future<void> _exportVisibleDemands() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      while (_hasMore) {
        final previousLength = _items.length;
        await _loadMore();
        if (!mounted) return;
        if (_items.length == previousLength) break;
      }
      final rows = _visibleItems;
      if (rows.isEmpty) {
        showUrbToast(context, 'Não há demandas para exportar.');
        return;
      }
      final csv = <String>[
        [
          'ID',
          'Título',
          'Bairro',
          'Categoria',
          'Órgão',
          'Status',
          'Prioridade',
          'Apoios',
          'Tempo sem resposta',
          'Previsão',
        ].map(_csvCell).join(','),
        for (final item in rows)
          [
            item.occurrence.id,
            item.occurrence.title,
            item.occurrence.neighborhood,
            item.occurrence.categoryName,
            item.occurrence.agencyName,
            item.occurrence.status.label,
            item.occurrence.administrativePriority ? 'Sim' : 'Não',
            item.occurrence.supportsCount,
            administrationResponseWaitLabel(item),
            item.context.latestForecast?.forecastAt == null
                ? ''
                : formatDate(item.context.latestForecast!.forecastAt!),
          ].map(_csvCell).join(','),
      ].join('\r\n');
      final downloaded = await downloadFile(
        fileName: 'demandas_${widget.membership.cityName ?? 'municipio'}.csv',
        bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
        mimeType: 'text/csv;charset=utf-8',
      );
      if (mounted && downloaded) {
        showUrbToast(context, 'Arquivo CSV gerado com sucesso.');
      }
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _exporting = false);
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
        linkedOccurrenceIds: _selectedPerson?.occurrenceIds,
      );

  AdministrationCollaborator? get _selectedPerson => _collaborators
      .where((person) => person.identityKey == _personKey)
      .firstOrNull;

  List<AdministrationCollaborator> get _people => _collaborators
      .where((person) => person.organizationKind == 'councilor')
      .toList();

  int get _advancedFilterCount =>
      [
        _agencyId,
        _categoryId,
        _neighborhood,
        _personKey,
      ].where((value) => value != null).length +
      (_order == AdministrationDemandOrder.attention ? 0 : 1) +
      (_quickFilters.contains(_filter) ? 0 : 1);

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
    if (!widget.membership.canRegisterActions) {
      showUrbToast(context, 'Seu acesso permite apenas consultar a gestão.');
      return;
    }
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
      _personKey = null;
    });
  }

  Future<void> _showAdvancedFilters() async {
    var agencyId = _agencyId;
    var categoryId = _categoryId;
    var neighborhood = _neighborhood;
    var order = _order;
    var situation = _filter;
    var personKey = _personKey;
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
                Text('Situação', style: UrbText.label),
                const SizedBox(height: 8),
                DropdownButtonFormField<AdministrationQueueFilter>(
                  initialValue: situation,
                  decoration: const InputDecoration(),
                  items: [
                    for (final value in AdministrationQueueFilter.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => situation = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                _FilterDropdown<String>(
                  label: 'Pessoa vinculada',
                  value: personKey,
                  allLabel: 'Todas as pessoas',
                  entries: [
                    for (final person in _people)
                      MapEntry(
                        person.identityKey,
                        '${person.name} · ${person.roleLabel}',
                      ),
                  ]..sort((a, b) => a.value.compareTo(b.value)),
                  onChanged: (value) => setSheetState(() => personKey = value),
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
        _filter = situation;
        _personKey = personKey;
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
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final section in const [
                (0, 'Visão geral'),
                (1, 'Demandas'),
                (2, 'Órgãos'),
                (3, 'Pessoas'),
                (4, 'Previsões'),
                (5, 'Mapa'),
                (6, 'Histórico'),
              ])
                UrbChip(
                  label: section.$2,
                  selected: _section == section.$1,
                  onTap: () => setState(() => _section = section.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_section) {
            0 => _buildOverview(),
            1 => _buildQueue(),
            2 => _buildAgencies(),
            3 => _buildPeople(),
            4 => _buildForecasts(),
            5 => _buildOperationalMap(),
            _ => _buildHistory(),
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
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: UrbColors.blueSoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const UrbIcon(
                        UrbIcons.profile,
                        size: 16,
                        color: UrbColors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.membership.canRegisterActions
                              ? 'Atuando como ${widget.membership.roleLabel} da Prefeitura'
                              : 'Acesso de consulta: ações oficiais estão desativadas',
                          style: UrbText.caption.copyWith(
                            color: UrbColors.blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                    FullBleed(
                      bleed: 20,
                      child: _DemandRow(
                        item: attention[index],
                        citizenName:
                            _citizenNames[attention[index].occurrence.id],
                        horizontalInset: 20,
                        onTap: () => _openDemand(attention[index]),
                        onQuickAction: _quickActionFor(attention[index]),
                        last: index == attention.take(5).length - 1,
                      ),
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
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final value in _quickFilters)
                UrbChip(
                  label: value.label,
                  selected: _filter == value,
                  onTap: () => setState(() => _filter = value),
                ),
            ],
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
          Align(
            alignment: Alignment.centerRight,
            child: UrbTextButton(
              _exporting ? 'Preparando CSV...' : 'Exportar fila em CSV',
              onPressed: _exporting ? null : _exportVisibleDemands,
            ),
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
              FullBleed(
                bleed: 20,
                child: _DemandRow(
                  item: visible[index],
                  citizenName: _citizenNames[visible[index].occurrence.id],
                  horizontalInset: 20,
                  onTap: () => _openDemand(visible[index]),
                  onQuickAction: _quickActionFor(visible[index]),
                  last: index == visible.length - 1,
                ),
              ),
          if (_hasMore || _loadingMore) ...[
            const SizedBox(height: 18),
            UrbButton(
              label: _loadingMore ? 'Carregando...' : 'Carregar mais demandas',
              tone: UrbButtonTone.outline,
              expand: true,
              onPressed: _loadingMore ? null : _loadMore,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgencies() {
    final agencySummaries = buildAdministrationAgencySummaries(
      _items.where((item) => item.occurrence.agencyId != null),
      order: _agencyOrder,
    );
    final administrationProfile = _collaborators
        .where((person) => person.organizationKind == 'administration')
        .firstOrNull;
    final administrationUpdates =
        _items
            .map((item) => item.context.latestAdministrationAction?.createdAt)
            .whereType<DateTime>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final summaries = [
      AdministrationAgencySummary(
        agencyId: null,
        agencyName: administrationProfile?.name ?? widget.membership.name,
        active: _items.length,
        withoutUpdate: _items
            .where((item) => item.context.latestAdministrationAction == null)
            .length,
        inProgress: _items
            .where(
              (item) => item.occurrence.status == OccurrenceStatus.inProgress,
            )
            .length,
        overdue: _items
            .where(
              (item) =>
                  administrationForecastIsOverdue(item.context, DateTime.now()),
            )
            .length,
        awaitingValidation: _items
            .where(
              (item) =>
                  item.occurrence.status == OccurrenceStatus.awaitingValidation,
            )
            .length,
        lastUpdateAt: administrationUpdates.firstOrNull,
      ),
      ...agencySummaries,
    ];
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
          const SizedBox(height: 14),
          Row(
            children: [
              const UrbIcon(UrbIcons.filter, size: 15, color: UrbColors.muted),
              const SizedBox(width: 7),
              Text('Ordenar por', style: UrbText.caption),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<AdministrationAgencyOrder>(
                  initialValue: _agencyOrder,
                  isDense: true,
                  decoration: const InputDecoration(),
                  items: [
                    for (final value in AdministrationAgencyOrder.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _agencyOrder = value);
                  },
                ),
              ),
            ],
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
                profile: summaries[index].agencyId == null
                    ? administrationProfile
                    : _collaborators
                          .where(
                            (person) =>
                                person.organizationKind == 'agency' &&
                                person.organizationName ==
                                    summaries[index].agencyName,
                          )
                          .firstOrNull,
                last: index == summaries.length - 1,
                onTap: () {
                  setState(() {
                    _agencyId = summaries[index].agencyId;
                    _personKey = null;
                    _section = 1;
                  });
                },
              ),
        ],
      ),
    );
  }

  Widget _buildPeople() => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Text('Pessoas da cidade', style: UrbText.h3),
        const SizedBox(height: 4),
        Text(
          'Perfis institucionais da gestão, dos órgãos municipais e do Legislativo vinculados à cidade.',
          style: UrbText.bodySmall,
        ),
        const SizedBox(height: 18),
        if (_people.isEmpty)
          const UrbEmptyState(
            icon: UrbIcons.profile,
            title: 'Nenhuma pessoa vinculada',
            message:
                'Os perfis institucionais credenciados da cidade aparecerão aqui.',
          )
        else
          for (var index = 0; index < _people.length; index++)
            _CollaboratorRow(
              collaborator: _people[index],
              last: index == _people.length - 1,
              onTap: () {
                setState(() {
                  _personKey = _people[index].identityKey;
                  _agencyId = null;
                  _section = 1;
                });
              },
            ),
      ],
    ),
  );

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
                  FullBleed(
                    bleed: 20,
                    child: _DemandRow(
                      item: groups[group]![index],
                      citizenName:
                          _citizenNames[groups[group]![index].occurrence.id],
                      horizontalInset: 20,
                      contextNote:
                          'Previsão: ${formatDate(groups[group]![index].context.latestForecast!.forecastAt!)}',
                      emphasizeContext: true,
                      onTap: () => _openDemand(groups[group]![index]),
                      onQuickAction: _quickActionFor(groups[group]![index]),
                      last: index == groups[group]!.length - 1,
                    ),
                  ),
                const SizedBox(height: 22),
              ],
        ],
      ),
    );
  }

  Widget _buildOperationalMap() {
    final visible = _visibleItems;
    final occurrences = visible.map((item) => item.occurrence).toList();
    final selected = visible
        .where((item) => item.occurrence.id == _selectedMapOccurrenceId)
        .firstOrNull;
    final center = occurrences.isEmpty
        ? const LatLng(-23.5015, -47.4526)
        : LatLng(
            occurrences
                    .map((occurrence) => occurrence.latitude)
                    .reduce((a, b) => a + b) /
                occurrences.length,
            occurrences
                    .map((occurrence) => occurrence.longitude)
                    .reduce((a, b) => a + b) /
                occurrences.length,
          );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Text('Mapa operacional', style: UrbText.h3),
          const SizedBox(height: 4),
          Text(
            'Visualize a distribuição das demandas e identifique concentrações por região.',
            style: UrbText.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${occurrences.length} ${occurrences.length == 1 ? 'demanda visível' : 'demandas visíveis'}',
                  style: UrbText.caption.copyWith(fontWeight: FontWeight.w700),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final value in _quickFilters)
                UrbChip(
                  label: value.label,
                  selected: _filter == value,
                  onTap: () => setState(() => _filter = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (occurrences.isEmpty)
            const UrbEmptyState(
              icon: UrbIcons.map,
              title: 'Nenhuma demanda no mapa',
              message: 'Ajuste os filtros para visualizar outras regiões.',
            )
          else ...[
            SizedBox(
              height: 430,
              child: OccurrenceMap(
                occurrences: occurrences,
                center: center,
                selectedId: _selectedMapOccurrenceId,
                label: widget.membership.cityName ?? 'Área municipal',
                onSelect: (occurrence) =>
                    setState(() => _selectedMapOccurrenceId = occurrence?.id),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              FullBleed(
                bleed: 20,
                child: _DemandRow(
                  item: selected,
                  citizenName: _citizenNames[selected.occurrence.id],
                  horizontalInset: 20,
                  onTap: () => _openDemand(selected),
                  onQuickAction: _quickActionFor(selected),
                  last: true,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHistory() => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Text('Histórico da Prefeitura', style: UrbText.h3),
        const SizedBox(height: 4),
        Text(
          'Registro cronológico das ações oficiais realizadas pela gestão e pelos órgãos.',
          style: UrbText.bodySmall,
        ),
        const SizedBox(height: 18),
        if (_history.isEmpty)
          const UrbEmptyState(
            icon: UrbIcons.list,
            title: 'Nenhuma ação registrada',
            message: 'As ações institucionais aparecerão aqui.',
          )
        else
          for (var index = 0; index < _history.length; index++)
            FullBleed(
              bleed: 20,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => openOccurrence(
                    context,
                    occurrenceId: _history[index].occurrenceId,
                  ),
                  hoverColor: const Color(0xFFF1F3F1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: index == _history.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(color: UrbColors.divider),
                            ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: UrbColors.blueSoft,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const UrbIcon(
                            UrbIcons.building,
                            size: 16,
                            color: UrbColors.blue,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                institutionalActionLabels[_history[index]
                                        .actionType] ??
                                    'Ação institucional',
                                style: UrbText.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _history[index].occurrenceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UrbText.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _history[index].description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: UrbText.caption,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_history[index].actorKind == 'agency' ? 'Órgão municipal' : 'Prefeitura'} · ${formatRelativeTime(_history[index].createdAt)}',
                                style: UrbText.caption.copyWith(
                                  color: UrbColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const UrbIcon(
                          UrbIcons.chevron,
                          size: 15,
                          color: UrbColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

class _DemandRow extends StatelessWidget {
  const _DemandRow({
    required this.item,
    required this.onTap,
    required this.onQuickAction,
    this.last = false,
    this.contextNote,
    this.citizenName,
    this.horizontalInset = 0,
    this.emphasizeContext = false,
  });

  final AdministrationDemandItem item;
  final VoidCallback onTap;
  final ValueChanged<String>? onQuickAction;
  final bool last;
  final String? contextNote;
  final String? citizenName;
  final double horizontalInset;
  final bool emphasizeContext;

  @override
  Widget build(BuildContext context) {
    final occurrence = item.occurrence;
    final signals = administrationAttentionSignals(item);
    final waitLabel = administrationResponseWaitLabel(item);
    final validation = item.context.validation;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFFF1F3F1),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: UrbColors.divider)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OccurrenceImage(
                url: occurrence.primaryImageUrl,
                categoryName: occurrence.categoryName,
                categorySlug: occurrence.categorySlug,
                width: 82,
                height: 108,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
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
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        StatusPill(occurrence.status, compact: true),
                        if (onQuickAction != null)
                          SizedBox(
                            width: 30,
                            height: 28,
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
                    const SizedBox(height: 3),
                    Text(
                      'Relato de ${citizenName ?? 'Cidadão'} · ${occurrence.supportsCount} ${occurrence.supportsCount == 1 ? 'apoio' : 'apoios'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption.copyWith(
                        color: const Color(0xFF59697D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (contextNote != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: emphasizeContext ? 10 : 0,
                          vertical: emphasizeContext ? 8 : 0,
                        ),
                        decoration: emphasizeContext
                            ? BoxDecoration(
                                color: const Color(0xFFFFF4DF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: UrbColors.warning.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              )
                            : null,
                        child: Row(
                          children: [
                            const UrbIcon(
                              UrbIcons.clock,
                              size: 14,
                              color: UrbColors.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                contextNote!,
                                style: UrbText.caption.copyWith(
                                  color: UrbColors.warning,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Criada ${formatRelativeTime(occurrence.createdAt).toLowerCase()}',
                      style: UrbText.caption,
                    ),
                    if (waitLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        waitLabel,
                        style: UrbText.caption.copyWith(
                          color: UrbColors.warning,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (validation != null) ...[
                      const SizedBox(height: 9),
                      _ValidationProgressCard(progress: validation),
                    ],
                    if (signals.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final signal in signals.take(3))
                            UrbChip(
                              label: signal.label,
                              dotColor: UrbColors.warning,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const UrbIcon(
                          UrbIcons.arrow,
                          size: 14,
                          color: UrbColors.blue,
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidationProgressCard extends StatelessWidget {
  const _ValidationProgressCard({required this.progress});

  final AdministrationValidationProgress progress;

  String get _deadlineLabel {
    if (!progress.pending) {
      return administrationValidationStatusLabel(progress.status);
    }
    final remaining = progress.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Prazo encerrado';
    if (remaining.inHours < 24) {
      return '${remaining.inHours} ${remaining.inHours == 1 ? 'hora restante' : 'horas restantes'}';
    }
    return '${remaining.inDays} ${remaining.inDays == 1 ? 'dia restante' : 'dias restantes'}';
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: UrbColors.blueSoft.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _deadlineLabel,
          style: UrbText.caption.copyWith(
            color: UrbColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${progress.confirmations}/${progress.confirmationsRequired} confirmações · '
          '${progress.rejections}/${progress.rejectionsRequired} rejeições',
          style: UrbText.caption,
        ),
      ],
    ),
  );
}

class _AgencySummaryRow extends StatelessWidget {
  const _AgencySummaryRow({
    required this.summary,
    required this.profile,
    required this.onTap,
    this.last = false,
  });

  final AdministrationAgencySummary summary;
  final AdministrationCollaborator? profile;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profile != null) ...[
                UrbAvatar(
                  name: profile!.name,
                  imageUrl: profile!.avatarUrl,
                  size: 44,
                  rounded: false,
                  gradientSeed: profile!.userId.hashCode,
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.agencyName, style: UrbText.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.active} ativas · ${summary.inProgress} em andamento · ${summary.awaitingValidation} em validação',
                      style: UrbText.caption,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: UrbIcon(
                  UrbIcons.chevron,
                  size: 15,
                  color: UrbColors.muted,
                ),
              ),
            ],
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

class _CollaboratorRow extends StatelessWidget {
  const _CollaboratorRow({
    required this.collaborator,
    required this.onTap,
    this.last = false,
  });

  final AdministrationCollaborator collaborator;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: UrbColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UrbAvatar(
            name: collaborator.name,
            imageUrl: collaborator.avatarUrl,
            size: 42,
            rounded: false,
            gradientSeed: collaborator.userId.hashCode,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(collaborator.name, style: UrbText.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${collaborator.organizationName} · ${collaborator.roleLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UrbText.caption,
                ),
                const SizedBox(height: 6),
                Text(
                  '${collaborator.demandsCount} ${collaborator.demandsCount == 1 ? 'demanda vinculada' : 'demandas vinculadas'} · '
                  '${collaborator.actionsCount} ${collaborator.actionsCount == 1 ? 'ação registrada' : 'ações registradas'}',
                  style: UrbText.caption.copyWith(fontWeight: FontWeight.w700),
                ),
                if (collaborator.lastActionAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Última atuação ${formatRelativeTime(collaborator.lastActionAt!).toLowerCase()}',
                    style: UrbText.caption.copyWith(color: UrbColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 13),
            child: UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
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
