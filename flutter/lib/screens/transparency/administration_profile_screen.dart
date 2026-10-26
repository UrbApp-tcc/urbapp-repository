import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'activity_list.dart';
import 'entity_list_screens.dart';
import 'transparency_kit.dart';

/// Perfil público "Prefeitura de `cidade` · Gestão `início–fim`" (spec §11,
/// §33, §44.6). O prefeito é contexto; a gestão nunca "resolve" ocorrências.
/// Três abas curtas separam o que o UrbApp calcula para o período (Resumo), o
/// que a gestão publicou (Atuação oficial) e os órgãos vinculados.
class AdministrationProfileScreen extends StatefulWidget {
  const AdministrationProfileScreen({super.key, this.administrationId, this.cityId})
      : assert(administrationId != null || cityId != null);

  final int? administrationId;
  final int? cityId;

  @override
  State<AdministrationProfileScreen> createState() => _AdministrationProfileScreenState();
}

class _AdministrationProfileScreenState extends State<AdministrationProfileScreen> {
  final _service = TransparencyService();

  AdministrationProfile? _profile;
  List<AdministrationProfile> _history = const [];
  List<AgencyProfile> _agencies = const [];
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
      final profile = widget.administrationId != null
          ? await _service.fetchAdministration(widget.administrationId!)
          : await _service.fetchCurrentAdministration(widget.cityId!);
      if (profile == null) {
        if (mounted) setState(() => _error = 'Gestão municipal não encontrada.');
        return;
      }
      final results = await Future.wait<dynamic>([
        _service.fetchAgencies(profile.cityId),
        _service.fetchAdministrationActivity(profile.id, limit: 20),
        _service.fetchAdministrationHistory(profile.cityId),
      ]);
      final activity = await attachOccurrences(results[1] as List<InstitutionalActivity>);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _agencies = results[0] as List<AgencyProfile>;
        _activity = activity;
        _history = (results[2] as List<AdministrationProfile>)
            .where((item) => item.id != profile.id && !item.isPlaceholder)
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Gestão municipal'),
      body: _error != null
          ? UrbErrorState(message: _error!, onRetry: _load)
          : _loading || profile == null
          ? const UrbLoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                children: [
                  _hero(profile),
                  const SizedBox(height: 18),
                  BentoSegments(
                    labels: const ['Resumo', 'Atuação oficial', 'Órgãos'],
                    flex: const [10, 13, 10],
                    selected: _tab,
                    onChanged: (index) => setState(() => _tab = index),
                  ),
                  const SizedBox(height: 16),
                  ...switch (_tab) {
                    0 => _summary(profile),
                    1 => _official(profile),
                    _ => _agencyTab(),
                  },
                ],
              ),
            ),
    );
  }

  Widget _hero(AdministrationProfile profile) {
    final mayor = profile.mayorName;
    return IdentityHero(
      tone: TileTone.navy,
      leading: const BuildingGlyph(),
      badge: profile.isVerified
          ? const TilePill('Verificada', tone: PillTone.dark, check: true)
          : const TilePill('Não reivindicada', tone: PillTone.dark),
      name: profile.title,
      line2: profile.periodLabel,
      line3: mayor == null ? null : 'Prefeito no período: $mayor',
    );
  }

  // ---------------------------------------------------------------------------
  // Resumo: indicadores do período calculados pelo UrbApp.
  // ---------------------------------------------------------------------------

  List<Widget> _summary(AdministrationProfile profile) {
    final ended = profile.endsOn != null && profile.endsOn!.isBefore(DateTime.now());
    final pending = ended ? profile.leftPending : profile.active;
    final resolved = profile.resolvedDuringPeriod;
    final firstResponse = profile.averageFirstManifestationSeconds;
    return [
      const Provenance.calculated('Calculado pelo UrbApp para o período da gestão'),
      const SizedBox(height: 8),
      TilePair(
        left: StatTile(
          glyph: const RoundGlyph(UrbIcons.check),
          stat: TileStat(
            value: formatCount(resolved),
            faintValue: resolved == 0,
            title: pluralWord(resolved, 'resolução no período', 'resoluções no período'),
            subtitle: pluralWord(resolved, 'confirmada por vizinhos', 'confirmadas por vizinhos'),
          ),
        ),
        right: StatTile(
          glyph: DotsGlyph(colors: _dots(pending)),
          stat: TileStat(
            value: formatCount(pending),
            faintValue: pending == 0,
            title: ended ? pluralWord(pending, 'deixada pendente', 'deixadas pendentes') : 'sem resolução',
            subtitle: ended ? 'ao fim do período' : 'abertas ou em andamento',
          ),
        ),
      ),
      const SizedBox(height: 10),
      WideStat(
        value: formatCount(profile.registered),
        title: pluralWord(profile.registered, 'registrada nesta gestão', 'registradas nesta gestão'),
        subtitle: profile.inherited == 0
            ? 'Nenhuma herdada da gestão anterior'
            : '+ ${plural(profile.inherited, 'herdada', 'herdadas')} da gestão anterior',
      ),
      if (firstResponse != null) ...[
        const SizedBox(height: 10),
        WideStat(
          value: shortDays(firstResponse),
          valueSize: 22,
          title: 'até a primeira manifestação',
          subtitle: 'Média desde o registro',
        ),
      ],
      if (_history.isNotEmpty) ...[
        const SectionTitle('Gestões anteriores'),
        const SizedBox(height: 6),
        BentoCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var index = 0; index < _history.length; index++)
                _HistoryRow(item: _history[index], last: index == _history.length - 1),
            ],
          ),
        ),
      ],
    ];
  }

  List<Color> _dots(int count) =>
      [for (var index = 0; index < count.clamp(1, 6); index++) index == 0 && count > 0 ? UrbColors.blue : UrbColors.line];

  // ---------------------------------------------------------------------------
  // Atuação oficial: o que a gestão publicou no UrbApp.
  // ---------------------------------------------------------------------------

  List<Widget> _official(AdministrationProfile profile) {
    return [
      const Provenance.official('Publicado oficialmente pela Gestão no UrbApp'),
      const SizedBox(height: 8),
      BentoCard(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _Count(profile.manifested, 'com manifestação', 'com manifestação'),
              const VerticalDivider(width: 1, color: UrbColors.line),
              _Count(profile.prioritized, 'priorizada', 'priorizadas'),
              const VerticalDivider(width: 1, color: UrbColors.line),
              _Count(profile.conclusionsInformed, 'conclusão', 'conclusões'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (_activity.isEmpty)
        const SoftEmpty(
          title: 'Nenhuma publicação ainda',
          message: 'Quando a Gestão reconhecer, priorizar ou encaminhar uma ocorrência, a publicação aparece aqui.',
        )
      else
        BentoCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var index = 0; index < _activity.length; index++)
                OfficialActivityRow(item: _activity[index], last: index == _activity.length - 1),
            ],
          ),
        ),
      const SizedBox(height: 10),
      const RuleNote('Informar conclusão não resolve: os vizinhos confirmam ou rejeitam.'),
    ];
  }

  // ---------------------------------------------------------------------------
  // Órgãos vinculados: a única porta do hub até um órgão.
  // ---------------------------------------------------------------------------

  List<Widget> _agencyTab() {
    if (_agencies.isEmpty) {
      return const [
        SoftEmpty(
          title: 'Nenhum órgão cadastrado',
          message: 'As ocorrências seguem vinculadas à Prefeitura até que os órgãos da cidade sejam cadastrados.',
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
        child: Text(
          '${plural(_agencies.length, 'órgão responde', 'órgãos respondem')} pelas categorias de problema',
          style: UrbText.label.copyWith(fontWeight: FontWeight.w700, color: UrbColors.muted),
        ),
      ),
      AgencyGrid(agencies: _agencies),
    ];
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.singular, this.pluralForm);

  final int value;
  final String singular;
  final String pluralForm;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(formatCount(value), style: bigNumberStyle(28, color: value == 0 ? kFaint : UrbColors.ink)),
          const SizedBox(height: 2),
          Text(
            pluralWord(value, singular, pluralForm),
            textAlign: TextAlign.center,
            style: tileSubtitleStyle(value == 0 ? kFaint : UrbColors.muted),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.last});

  final AdministrationProfile item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openAdministration(context, administrationId: item.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.periodLabel, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                  if (item.mayorName != null) Text(item.mayorName!, style: tileSubtitleStyle()),
                ],
              ),
            ),
            const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Publicação oficial: ícone navy, rótulo curto, ocorrência e data.
class OfficialActivityRow extends StatelessWidget {
  const OfficialActivityRow({super.key, required this.item, required this.last});

  final InstitutionalActivity item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final occurrence = item.occurrence;
    final title = officialActionShortLabels[item.actionType] ?? 'Atualização oficial';
    final detail = item.description.trim();
    return InkWell(
      onTap: () => openOccurrence(context, occurrenceId: item.occurrenceId, initial: occurrence),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActionGlyph(officialActionIcon(item.actionType)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, height: 1.28)),
                  if (occurrence != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      occurrence.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tileSubtitleStyle(UrbColors.blue).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: tileSubtitleStyle()),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(dayMonth(item.createdAt), style: tileSubtitleStyle().copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
