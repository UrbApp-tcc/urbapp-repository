import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/occurrence_status.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'activity_list.dart';
import 'transparency_kit.dart';

/// Perfil público de um órgão municipal (spec §12, §19, §44.6). Duas abas
/// separam os indicadores calculados pelo UrbApp das atualizações oficiais
/// publicadas pelo órgão. Sem adesão, a página explica a ausência.
class AgencyProfileScreen extends StatefulWidget {
  const AgencyProfileScreen({super.key, required this.agencyId});

  final int agencyId;

  @override
  State<AgencyProfileScreen> createState() => _AgencyProfileScreenState();
}

class _AgencyProfileScreenState extends State<AgencyProfileScreen> {
  final _service = TransparencyService();

  AgencyProfile? _agency;
  String? _cityName;
  List<InstitutionalActivity> _activity = const [];
  String? _error;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final agency = await _service.fetchAgency(widget.agencyId);
      if (agency == null) {
        if (mounted) setState(() => _error = 'Órgão não encontrado.');
        return;
      }
      final results = await Future.wait<dynamic>([
        _service.fetchAgencyActivity(agency.id, limit: 30).then(attachOccurrences),
        _service.fetchCurrentAdministration(agency.cityId),
      ]);
      if (!mounted) return;
      setState(() {
        _agency = agency;
        _activity = results[0] as List<InstitutionalActivity>;
        _cityName = (results[1] as AdministrationProfile?)?.cityName;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agency = _agency;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Órgão'),
      body: _error != null
          ? UrbErrorState(message: _error!, onRetry: _load)
          : _loading || agency == null
          ? const UrbLoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                children: [
                  _hero(agency),
                  const SizedBox(height: 18),
                  BentoSegments(
                    labels: const ['Indicadores', 'Atualizações oficiais'],
                    flex: const [10, 14],
                    selected: _tab,
                    onChanged: (index) => setState(() => _tab = index),
                  ),
                  const SizedBox(height: 16),
                  ...(_tab == 0 ? _indicators(agency) : _updates(agency)),
                ],
              ),
            ),
    );
  }

  Widget _hero(AgencyProfile agency) {
    final claimed = agency.status.isVerified;
    final tone = claimed ? TileTone.blue : TileTone.white;
    final categories = agency.categories;
    return IdentityHero(
      tone: tone,
      leading: claimed
          ? Monogram(name: agency.name, background: Colors.white, foreground: UrbColors.blue)
          : Monogram(name: agency.name),
      badge: claimed
          ? institutionalPill(agency.status.label, claimed: true, participant: true)
          : const TilePill('Não reivindicado', tone: PillTone.ghost),
      name: agency.name,
      line2: categories.isEmpty ? 'Órgão municipal' : _joinCategories(categories),
      line3: _cityName == null ? null : 'Vinculado à Prefeitura de $_cityName',
    );
  }

  String _joinCategories(List<String> categories) {
    final shown = categories.take(3).toList();
    final extra = categories.length - shown.length;
    final text = shown.length == 1
        ? shown.first
        : '${shown.sublist(0, shown.length - 1).join(', ')} e ${shown.last}';
    return extra > 0 ? '$text e mais $extra' : text;
  }

  // ---------------------------------------------------------------------------
  // Indicadores calculados pelo UrbApp.
  // ---------------------------------------------------------------------------

  List<Widget> _indicators(AgencyProfile agency) {
    final responded = (agency.officialResponsePercentage * agency.assigned / 100).round();
    final hasResponse = agency.officialResponsePercentage > 0;
    final median = agency.medianResponsibilitySeconds;
    return [
      const Provenance.calculated('Calculado pelo UrbApp'),
      const SizedBox(height: 8),
      TilePair(
        left: StatTile(
          glyph: DotsGlyph(colors: _dots(agency)),
          stat: TileStat(
            value: formatCount(agency.assigned),
            faintValue: agency.assigned == 0,
            title: pluralWord(agency.assigned, 'atribuída ao órgão', 'atribuídas ao órgão'),
            subtitle: _currentLabel(agency),
          ),
        ),
        right: StatTile(
          tone: hasResponse ? TileTone.lime : TileTone.white,
          glyph: hasResponse ? const ResponseGlyph() : const RoundGlyph(UrbIcons.message, background: kSoft, color: kFaint),
          stat: TileStat(
            tone: hasResponse ? TileTone.lime : TileTone.white,
            value: '${formatDecimal(agency.officialResponsePercentage, digits: 0)}%',
            faintValue: !hasResponse,
            title: 'com resposta oficial',
            subtitle: '$responded de ${plural(agency.assigned, 'ocorrência', 'ocorrências')}',
          ),
        ),
      ),
      const SizedBox(height: 10),
      WideStat(
        value: formatCount(agency.resolved),
        faintValue: agency.resolved == 0,
        title: pluralWord(agency.resolved, 'resolução confirmada por vizinhos', 'resoluções confirmadas por vizinhos'),
        subtitle: agency.conclusionsInformed == 0
            ? 'Nenhuma conclusão informada ainda'
            : [
                plural(agency.conclusionsInformed, 'conclusão informada', 'conclusões informadas'),
                if (agency.rejectedConclusions > 0)
                  plural(agency.rejectedConclusions, 'rejeitada pelos vizinhos', 'rejeitadas pelos vizinhos'),
              ].join(' · '),
      ),
      if (median != null) ...[
        const SizedBox(height: 10),
        WideStat(
          value: shortDays(median),
          valueSize: 22,
          title: 'até assumir a ocorrência',
          subtitle: 'Mediana desde o registro',
        ),
      ],
    ];
  }

  /// Um ponto por ocorrência atual: azul em andamento, navy aguardando
  /// validação, cinza aberta.
  List<Color> _dots(AgencyProfile agency) {
    final colors = [
      for (var index = 0; index < agency.inProgress; index++) UrbColors.blue,
      for (var index = 0; index < agency.awaitingValidation; index++) UrbColors.navy,
      for (var index = 0; index < agency.open; index++) UrbColors.line,
    ];
    if (colors.isEmpty) return const [UrbColors.line];
    return colors.take(8).toList();
  }

  String _currentLabel(AgencyProfile agency) {
    final parts = [
      if (agency.inProgress > 0) '${agency.inProgress} em andamento',
      if (agency.awaitingValidation > 0) '${agency.awaitingValidation} aguardando validação',
      if (agency.open > 0) plural(agency.open, 'aberta', 'abertas'),
    ];
    return parts.isEmpty ? 'Nenhuma em aberto' : parts.join(' · ');
  }

  // ---------------------------------------------------------------------------
  // Atualizações oficiais: linha do tempo por ocorrência.
  // ---------------------------------------------------------------------------

  List<Widget> _updates(AgencyProfile agency) {
    if (!agency.status.isVerified) {
      return [
        SoftEmpty(
          glyph: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: const UrbIcon(UrbIcons.lock, size: 22, color: kFaint, strokeWidth: 2.4),
          ),
          title: 'Perfil institucional ainda não reivindicado',
          message: 'Este órgão ainda não publica no UrbApp. As ocorrências continuam vinculadas a ele, '
              'e os indicadores seguem calculados pelo UrbApp.',
        ),
        const SizedBox(height: 10),
        WideStat(
          value: formatCount(agency.current),
          faintValue: agency.current == 0,
          title: pluralWord(agency.current, 'ocorrência sob responsabilidade', 'ocorrências sob responsabilidade'),
          subtitle: 'Sem resposta oficial',
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Trabalha no órgão? A adesão é feita pela Prefeitura, que confirma o vínculo institucional.',
            style: tileSubtitleStyle().copyWith(height: 1.5),
          ),
        ),
      ];
    }
    final groups = <int, List<InstitutionalActivity>>{};
    for (final item in _activity) {
      groups.putIfAbsent(item.occurrenceId, () => []).add(item);
    }
    return [
      Provenance.official('Publicado oficialmente por ${agency.name}'),
      const SizedBox(height: 8),
      if (groups.isEmpty)
        const SoftEmpty(
          title: 'Nenhuma atualização publicada',
          message: 'Quando o órgão confirmar o recebimento, agendar ou executar um serviço, a atualização aparece aqui.',
        )
      else
        for (final entry in groups.entries) ...[
          _OccurrenceTimeline(items: entry.value.reversed.toList()),
          const SizedBox(height: 10),
        ],
      const RuleNote('Informar conclusão não resolve: os vizinhos confirmam ou rejeitam.'),
    ];
  }
}

/// Uma ocorrência e as atualizações oficiais dela, da mais antiga à mais
/// recente. O último passo é sempre a confirmação dos vizinhos.
class _OccurrenceTimeline extends StatelessWidget {
  const _OccurrenceTimeline({required this.items});

  final List<InstitutionalActivity> items;

  @override
  Widget build(BuildContext context) {
    final occurrence = items.first.occurrence;
    final resolved = occurrence?.status == OccurrenceStatus.resolved;
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => openOccurrence(context, occurrenceId: items.first.occurrenceId, initial: occurrence),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  _Thumb(url: occurrence?.primaryImageUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          occurrence?.title ?? 'Ocorrência #${items.first.occurrenceId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, height: 1.28),
                        ),
                        if (occurrence != null)
                          Text(
                            '${occurrence.categoryName} · ${occurrence.locationLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tileSubtitleStyle(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: UrbColors.divider),
          const SizedBox(height: 14),
          for (var index = 0; index < items.length; index++)
            _Step(
              title: officialActionShortLabels[items[index].actionType] ?? 'Atualização oficial',
              detail: [
                dayMonth(items[index].createdAt),
                if (index == items.length - 1 && !resolved) 'atualização mais recente',
              ].join(' · '),
              note: items[index].description.trim(),
              state: index == items.length - 1 && !resolved ? _StepState.current : _StepState.done,
              connector: true,
              dashedConnector: index == items.length - 1,
            ),
          _Step(
            title: resolved ? 'Confirmada pelos vizinhos' : 'Confirmação dos vizinhos',
            detail: resolved ? 'Ocorrência resolvida' : 'Só ela marca a ocorrência como resolvida',
            state: resolved ? _StepState.done : _StepState.next,
            connector: false,
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF5B7088), Color(0xFF2C3E55)]),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? fallback
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

enum _StepState { done, current, next }

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.detail,
    required this.state,
    required this.connector,
    this.note = '',
    this.dashedConnector = false,
  });

  final String title;
  final String detail;
  final String note;
  final _StepState state;
  final bool connector;
  final bool dashedConnector;

  @override
  Widget build(BuildContext context) {
    final dot = switch (state) {
      _StepState.done => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: UrbColors.navy, shape: BoxShape.circle),
          child: const UrbIcon(UrbIcons.check, size: 12, color: UrbColors.lime, strokeWidth: 3.6),
        ),
      _StepState.current => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: UrbColors.lime,
            shape: BoxShape.circle,
            border: Border.all(color: UrbColors.navy, width: 2),
          ),
        ),
      _StepState.next => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: kFaint, width: 2),
          ),
        ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                dot,
                if (connector)
                  Expanded(
                    child: dashedConnector
                        ? const _DashedLine()
                        : Container(width: 2, color: UrbColors.navy),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: connector ? 14 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: UrbText.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.55,
                      color: state == _StepState.next ? UrbColors.muted : UrbColors.ink,
                    ),
                  ),
                  Text(detail, style: tileSubtitleStyle()),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(note, style: tileSubtitleStyle(UrbColors.textBody)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxHeight / 8).floor().clamp(1, 40);
        return Column(
          children: [
            for (var index = 0; index < count; index++)
              Container(width: 2, height: 4, margin: const EdgeInsets.only(top: 4), color: kFaint),
          ],
        );
      },
    );
  }
}
