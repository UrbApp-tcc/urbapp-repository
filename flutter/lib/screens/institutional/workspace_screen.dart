import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../occurrence/occurrence_sheets.dart';
import '../transparency/activity_list.dart';
import '../transparency/transparency_widgets.dart';
import 'administration_workspace.dart';

/// "Sua atuação": capacidades adicionais por papel dentro do mesmo app
/// (spec §44.7). Composição derivada da Home, Transparência e perfis públicos.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  InstitutionalAccess? _access;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final access = await InstitutionalService().fetchMyAccess(refresh: true);
      if (mounted) setState(() => _access = access);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final tabs = <(String, Widget)>[
      if (access?.isCouncilor ?? false)
        ('Vereador', CouncilorWorkspace(councilor: access!.councilor!)),
      for (final agency
          in access?.agencies ?? const <InstitutionalMembership>[])
        (agency.name, _AgencyWorkspace(membership: agency)),
      for (final administration
          in access?.administrations ?? const <InstitutionalMembership>[])
        (
          'Gestão municipal',
          AdministrationWorkspace(membership: administration),
        ),
    ];
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Sua atuação'),
      body: access == null
          ? (_error != null
                ? UrbErrorState(message: _error!, onRetry: _load)
                : const UrbLoadingView())
          : tabs.isEmpty
          ? const UrbEmptyState(
              icon: UrbIcons.building,
              title: 'Nenhum papel institucional ativo',
              message:
                  'Solicite um perfil institucional em Perfil → Configurações para atuar como vereador, órgão ou gestão.',
            )
          : DefaultTabController(
              length: tabs.length,
              child: Column(
                children: [
                  if (tabs.length > 1)
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [for (final tab in tabs) Tab(text: tab.$1)],
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [for (final tab in tabs) tab.$2],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Área de trabalho do vereador. Em [embedded], vira a aba "Atuação" do
/// próprio Perfil: sem cabeçalho de identidade (o Perfil já mostra) e sem
/// rolagem própria.
class CouncilorWorkspace extends StatefulWidget {
  const CouncilorWorkspace({
    super.key,
    required this.councilor,
    this.embedded = false,
  });

  final CouncilorIdentity councilor;
  final bool embedded;

  @override
  State<CouncilorWorkspace> createState() => _CouncilorWorkspaceState();
}

class _CouncilorWorkspaceState extends State<CouncilorWorkspace> {
  CouncilorProfile? _metrics;
  List<(CouncilorFollowingItem, Occurrence)> _followings = const [];
  bool _loading = true;
  bool _showAllFollowings = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        TransparencyService().fetchCouncilor(widget.councilor.id),
        InstitutionalService().fetchCouncilorFollowings(
          widget.councilor.id,
          activeOnly: true,
        ),
      ]);
      final followings = results[1] as List<CouncilorFollowingItem>;
      final occurrences = await OccurrenceService().fetchByIds(
        followings.map((item) => item.occurrenceId),
      );
      final byId = {
        for (final occurrence in occurrences) occurrence.id: occurrence,
      };
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as CouncilorProfile?;
        // Quem está há mais tempo sem novidade vem primeiro.
        _followings = [
          for (final item in followings)
            if (byId[item.occurrenceId] != null)
              (item, byId[item.occurrenceId]!),
        ]..sort((a, b) => _quietSince(a.$1).compareTo(_quietSince(b.$1)));
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open((CouncilorFollowingItem, Occurrence) following) async {
    await openOccurrence(
      context,
      occurrenceId: following.$2.id,
      initial: following.$2,
    );
    _load();
  }

  /// A ação acontece na própria linha, sem abrir a ocorrência.
  Future<void> _register((CouncilorFollowingItem, Occurrence) following) async {
    final saved = await showCouncilorActionSheet(
      context,
      occurrence: following.$2,
      followingId: following.$1.followingId,
    );
    if (!saved || !mounted) return;
    showUrbToast(context, 'Atuação registrada no histórico público.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.embedded
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: UrbLoadingView(),
            )
          : const UrbLoadingView();
    }
    if (_error != null) return UrbErrorState(message: _error!, onRetry: _load);
    // Sua vez: acompanha, mas ainda não agiu. Aguardando o órgão: já cobrou
    // (encaminhamento, solicitação, cobrança, ofício ou contato).
    final yourTurn = _followings
        .where((item) => item.$1.status == 'started')
        .toList();
    final waiting = _followings
        .where((item) => item.$1.status == 'awaiting_response')
        .toList();
    final following = _followings
        .where(
          (item) =>
              item.$1.status != 'started' &&
              item.$1.status != 'awaiting_response',
        )
        .toList();
    final sections = <Widget>[
      if (!widget.embedded) _CouncilorHeader(councilor: widget.councilor),
      if (yourTurn.isNotEmpty)
        _QueueSection(
          title: 'Sua vez',
          description:
              'Você acompanha estas demandas, mas ainda não registrou nenhuma ação.',
          items: yourTurn,
          yourTurn: true,
          onOpen: _open,
          onRegister: _register,
        ),
      _QueueSection(
        title: 'Aguardando o órgão',
        description:
            'Você já atuou nesta demanda. Aguarde o retorno ou registre uma nova ação.',
        emptyText: 'Nenhuma cobrança sua está esperando resposta.',
        items: waiting,
        yourTurn: false,
        onOpen: _open,
        onRegister: _register,
      ),
      _FollowingSection(
        items: following,
        expanded: _showAllFollowings,
        onToggle: () =>
            setState(() => _showAllFollowings = !_showAllFollowings),
        onOpen: _open,
      ),
      _HistoryFooter(
        actions: _metrics?.registeredActions ?? 0,
        onOpen: () => openCouncilor(context, widget.councilor.id),
      ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: sections,
      ),
    );
  }
}

/// Momento da última novidade do acompanhamento (ação dela ou início).
DateTime _quietSince(CouncilorFollowingItem item) =>
    item.lastActionAt ?? item.startedAt;

/// Tempo sem novidade em forma curta: "agora", "35 min", "4 h", "6 d".
(String short, String spoken) _elapsed(DateTime since) {
  final diff = DateTime.now().difference(since);
  if (diff.inHours < 1) return ('< 1 h', 'menos de uma hora');
  if (diff.inDays < 1) {
    return ('${diff.inHours} h', plural(diff.inHours, 'hora', 'horas'));
  }
  return ('${diff.inDays} d', plural(diff.inDays, 'dia', 'dias'));
}

/// Cabeçalho só para a tela avulsa; dentro do Perfil a identidade já aparece.
class _CouncilorHeader extends StatelessWidget {
  const _CouncilorHeader({required this.councilor});

  final CouncilorIdentity councilor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          PersonAvatar(
            name: councilor.publicName,
            seed: councilor.id,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(councilor.publicName, style: UrbText.title),
                const SizedBox(height: 2),
                Text(
                  [
                    'Vereador(a)',
                    if (councilor.party != null) councilor.party!,
                  ].join(' · '),
                  style: UrbText.meta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma fila da área de trabalho. "Sua vez" pede a primeira ação da
/// vereadora; "Aguardando o órgão" mostra o que ela já cobrou e há quanto
/// tempo o órgão está sem responder.
class _QueueSection extends StatelessWidget {
  const _QueueSection({
    required this.title,
    required this.description,
    required this.items,
    required this.yourTurn,
    required this.onOpen,
    required this.onRegister,
    this.emptyText,
  });

  final String title;
  final String description;
  final String? emptyText;
  final List<(CouncilorFollowingItem, Occurrence)> items;
  final bool yourTurn;
  final Future<void> Function((CouncilorFollowingItem, Occurrence)) onOpen;
  final Future<void> Function((CouncilorFollowingItem, Occurrence)) onRegister;

  @override
  Widget build(BuildContext context) {
    final accent = yourTurn ? UrbColors.blue : UrbColors.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: UrbText.h3)),
              if (items.isNotEmpty)
                Text(
                  '${items.length}',
                  style: UrbText.h3.copyWith(color: accent),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            items.isEmpty ? (emptyText ?? description) : description,
            style: UrbText.bodySmall.copyWith(color: UrbColors.textBody),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: UrbColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++)
                    _QueueRow(
                      item: items[index].$1,
                      occurrence: items[index].$2,
                      yourTurn: yourTurn,
                      last: index == items.length - 1,
                      onOpen: () => onOpen(items[index]),
                      onRegister: () => onRegister(items[index]),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.occurrence,
    required this.yourTurn,
    required this.last,
    required this.onOpen,
    required this.onRegister,
  });

  final CouncilorFollowingItem item;
  final Occurrence occurrence;
  final bool yourTurn;
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final responsible = occurrence.agencyName ?? 'Órgão não identificado';
    final lastAt = item.lastActionAt;
    // Confirma o que ela acabou de fazer: ação registrada há menos de 1 h.
    final justDone =
        lastAt != null && DateTime.now().difference(lastAt).inHours < 1;
    final step = yourTurn || item.lastActionType == null
        ? 'Acompanhando desde ${formatRelativeTime(item.startedAt).toLowerCase()}'
        : 'Sua última ação: ${councilorActionLabels[item.lastActionType] ?? 'Ação registrada'} · ${formatRelativeTime(lastAt!).toLowerCase()}';
    final (short, spoken) = _elapsed(_quietSince(item));
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: UrbColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: yourTurn
                ? '${occurrence.title}. $responsible. $step. Abrir demanda'
                : '${occurrence.title}. $responsible, sem resposta há $spoken. $step. Abrir demanda',
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            occurrence.title,
                            style: UrbText.title.copyWith(
                              fontSize: 15,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            responsible,
                            style: UrbText.meta.copyWith(
                              color: UrbColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (justDone) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: UrbColors.blue,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: UrbColors.blue.withValues(
                                          alpha: 0.2,
                                        ),
                                        spreadRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  step,
                                  style: UrbText.caption.copyWith(
                                    color: UrbColors.navy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!yourTurn) ...[
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            short,
                            style: UrbText.title.copyWith(
                              color: UrbColors.warning,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            'sem resposta',
                            style: UrbText.caption.copyWith(
                              color: UrbColors.warning,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRegister,
                style: TextButton.styleFrom(
                  foregroundColor: UrbColors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  visualDensity: VisualDensity.compact,
                  textStyle: UrbText.label.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const UrbIcon(
                  UrbIcons.pencil,
                  size: 15,
                  color: UrbColors.blue,
                ),
                label: Text(
                  yourTurn
                      ? 'Registrar primeira ação'
                      : 'Registrar nova atuação',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Demandas acompanhadas sem pendência do órgão: lista leve, sem superfície.
class _FollowingSection extends StatelessWidget {
  const _FollowingSection({
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final List<(CouncilorFollowingItem, Occurrence)> items;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function((CouncilorFollowingItem, Occurrence)) onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? items : items.take(4).toList();
    final hidden = items.length - visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Acompanhando',
                  style: UrbText.title.copyWith(fontSize: 15),
                ),
              ),
              if (items.isNotEmpty)
                Text(
                  '${items.length}',
                  style: UrbText.title.copyWith(
                    fontSize: 15,
                    color: UrbColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text(
              'Toque em "Acompanhar" em uma ocorrência da cidade para começar.',
              style: UrbText.bodySmall.copyWith(color: UrbColors.textBody),
            )
          else ...[
            for (var index = 0; index < visible.length; index++)
              _FollowingRow(
                item: visible[index].$1,
                occurrence: visible[index].$2,
                last: index == visible.length - 1,
                onOpen: () => onOpen(visible[index]),
              ),
            if (items.length > 4)
              Align(
                alignment: Alignment.centerLeft,
                child: UrbTextButton(
                  expanded ? 'Mostrar menos' : 'Ver mais $hidden',
                  onPressed: onToggle,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FollowingRow extends StatelessWidget {
  const _FollowingRow({
    required this.item,
    required this.occurrence,
    required this.last,
    required this.onOpen,
  });

  final CouncilorFollowingItem item;
  final Occurrence occurrence;
  final bool last;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final lastStep = item.lastActionType != null
        ? (councilorActionLabels[item.lastActionType] ?? 'Ação registrada')
        : (councilorFollowingStatusLabels[item.status] ?? 'Em acompanhamento');
    final when = formatRelativeTime(_quietSince(item)).toLowerCase();
    return Semantics(
      button: true,
      label: '${occurrence.title}. $lastStep, $when. Abrir demanda',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: UrbColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$lastStep · $when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.meta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// O histórico completo é público; aqui fica só o caminho até ele.
class _HistoryFooter extends StatelessWidget {
  const _HistoryFooter({required this.actions, required this.onOpen});

  final int actions;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Semantics(
        button: true,
        label:
            '${plural(actions, 'ação registrada', 'ações registradas')}. Ver histórico público',
        excludeSemantics: true,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: UrbColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    actions == 0
                        ? 'Nenhuma ação registrada ainda'
                        : plural(
                            actions,
                            'ação registrada',
                            'ações registradas',
                          ),
                    style: UrbText.meta,
                  ),
                ),
                Text(
                  'Ver histórico público',
                  style: UrbText.label.copyWith(
                    color: UrbColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const UrbIcon(
                  UrbIcons.chevron,
                  size: 14,
                  color: UrbColors.blue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila operacional do órgão (spec §44.7 "Órgão verificado").
class _AgencyWorkspace extends StatefulWidget {
  const _AgencyWorkspace({required this.membership});

  final InstitutionalMembership membership;

  @override
  State<_AgencyWorkspace> createState() => _AgencyWorkspaceState();
}

class _AgencyWorkspaceState extends State<_AgencyWorkspace> {
  List<Occurrence> _queue = const [];
  AgencyProfile? _metrics;
  int _filter = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        OccurrenceService().fetchByAgency(
          widget.membership.id,
          activeOnly: true,
          limit: 100,
        ),
        TransparencyService().fetchAgency(widget.membership.id),
      ]);
      if (!mounted) return;
      setState(() {
        _queue = results[0] as List<Occurrence>;
        _metrics = results[1] as AgencyProfile?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Occurrence> get _filtered => switch (_filter) {
    0 => _queue.where((item) => item.latestOfficialAction == null).toList(),
    1 =>
      _queue
          .where(
            (item) =>
                item.status == OccurrenceStatus.inAnalysis ||
                item.status == OccurrenceStatus.inProgress,
          )
          .toList(),
    2 =>
      _queue
          .where((item) => item.status == OccurrenceStatus.awaitingValidation)
          .toList(),
    _ => _queue,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const UrbLoadingView();
    if (_error != null) return UrbErrorState(message: _error!, onRetry: _load);
    final filtered = _filtered;
    final metrics = _metrics;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          TransSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.membership.name, style: UrbText.h3),
                    ),
                    UrbTextButton(
                      'Perfil público',
                      onPressed: () =>
                          openAgency(context, widget.membership.id),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (metrics != null)
                  UrbStatRow(
                    items: [
                      UrbStatItem(
                        '${metrics.open}',
                        pluralWord(metrics.open, 'aberta', 'abertas'),
                      ),
                      UrbStatItem('${metrics.inProgress}', 'em andamento'),
                      UrbStatItem(
                        '${metrics.awaitingValidation}',
                        'aguardando validação',
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  'Você pode confirmar recebimento, informar análise, previsão e execução, publicar atualizações e informar conclusão. '
                  'A resolução só é confirmada pela comunidade.',
                  style: UrbText.caption,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, label) in const [
                  'Sem resposta oficial',
                  'Em andamento',
                  'Aguardando validação',
                  'Todas',
                ].indexed)
                  UrbChip(
                    label: label,
                    selected: _filter == index,
                    onTap: () => setState(() => _filter = index),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: filtered.isEmpty
                ? const UrbEmptyState(
                    compact: true,
                    icon: UrbIcons.check,
                    title: 'Nada por aqui',
                    message: 'Nenhuma ocorrência nesta etapa.',
                  )
                : Column(
                    children: [
                      for (var index = 0; index < filtered.length; index++)
                        RelatedOccurrenceRow(
                          occurrence: filtered[index],
                          note: filtered[index].latestOfficialAction == null
                              ? 'Sem atualização oficial · criada ${formatRelativeTime(filtered[index].createdAt).toLowerCase()}'
                              : '${institutionalActionLabels[filtered[index].latestOfficialAction!.actionType] ?? 'Atualização'} · '
                                    '${formatRelativeTime(filtered[index].latestOfficialAction!.createdAt).toLowerCase()}',
                          last: index == filtered.length - 1,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
