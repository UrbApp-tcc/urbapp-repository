import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'activity_list.dart';
import 'transparency_kit.dart';

/// Perfil público de vereador (spec §3.4, §13, §35, §44.6): só fatos, sem
/// notas nem classificação. Acompanhar ou cobrar não resolve; a métrica de
/// resolução usa a frase da especificação e exige ação anterior à resolução.
class CouncilorProfileScreen extends StatefulWidget {
  const CouncilorProfileScreen({super.key, required this.councilorProfileId});

  final int councilorProfileId;

  @override
  State<CouncilorProfileScreen> createState() => _CouncilorProfileScreenState();
}

class _CouncilorProfileScreenState extends State<CouncilorProfileScreen> {
  final _service = TransparencyService();

  CouncilorProfile? _profile;
  List<InstitutionalActivity> _activity = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchCouncilor(widget.councilorProfileId),
        _service.fetchCouncilorActivity(widget.councilorProfileId, limit: 20).then(attachOccurrences),
      ]);
      if (!mounted) return;
      final profile = results[0] as CouncilorProfile?;
      setState(() {
        _profile = profile;
        _activity = results[1] as List<InstitutionalActivity>;
        if (profile == null) _error = 'Perfil não encontrado.';
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
      appBar: const UrbSubscreenHeader(title: 'Vereador'),
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
                  const SizedBox(height: 16),
                  const Provenance.calculated('Calculado pelo UrbApp a partir das ações registradas'),
                  const SizedBox(height: 8),
                  _stats(profile),
                  SectionTitle('Ações registradas', trailing: _activity.isEmpty ? null : '${_activity.length}'),
                  const SizedBox(height: 6),
                  if (_activity.isEmpty)
                    const SoftEmpty(
                      title: 'Nenhuma ação registrada',
                      message: 'Cobranças, ofícios e encaminhamentos registrados aparecem aqui, ligados à ocorrência.',
                    )
                  else
                    BentoCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        children: [
                          for (var index = 0; index < _activity.length; index++)
                            _ActionRow(item: _activity[index], last: index == _activity.length - 1),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  const RuleNote(
                    'Sem nota ou classificação. Acompanhar e cobrar não resolvem: quem confirma a resolução são os vizinhos.',
                  ),
                ],
              ),
            ),
    );
  }

  Widget _hero(CouncilorProfile profile) {
    final city = AppSession.instance.cities.where((item) => item.id == profile.cityId).firstOrNull;
    final line2 = [?profile.party, if (profile.mandateLabel.isNotEmpty) profile.mandateLabel].join(' · ');
    return IdentityHero(
      tone: TileTone.navy,
      leading: InitialsAvatar(name: profile.publicName, background: UrbColors.lime, foreground: UrbColors.navy),
      badge: profile.status.isVerified
          ? const TilePill('Perfil verificado', tone: PillTone.dark, check: true)
          : const TilePill('Não reivindicado', tone: PillTone.dark),
      name: profile.publicName,
      line2: line2.isEmpty ? null : line2,
      line3: city == null ? null : 'Câmara Municipal de ${city.name}',
    );
  }

  Widget _stats(CouncilorProfile profile) {
    final actionParts = [
      if (profile.chargeActions > 0) plural(profile.chargeActions, 'cobrança', 'cobranças'),
      if (profile.officialLetters > 0) plural(profile.officialLetters, 'ofício', 'ofícios'),
      if (profile.forwardingActions > 0) plural(profile.forwardingActions, 'encaminhamento', 'encaminhamentos'),
    ];
    return Column(
      children: [
        TilePair(
          left: StatTile(
            height: 176,
            glyph: DotsGlyph(
              colors: [
                for (var index = 0; index < profile.followed.clamp(1, 6); index++)
                  profile.followed == 0 ? UrbColors.line : UrbColors.navy,
              ],
            ),
            stat: TileStat(
              value: formatCount(profile.followed),
              faintValue: profile.followed == 0,
              title: pluralWord(profile.followed, 'demanda acompanhada', 'demandas acompanhadas'),
              subtitle: profile.awaitingResponse == 0 ? null : '${profile.awaitingResponse} aguardando resposta',
            ),
          ),
          right: StatTile(
            height: 176,
            glyph: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: UrbColors.blue, borderRadius: BorderRadius.circular(11)),
              child: const UrbIcon(UrbIcons.list, size: 18, color: Colors.white, strokeWidth: 2.6),
            ),
            stat: TileStat(
              value: formatCount(profile.registeredActions),
              faintValue: profile.registeredActions == 0,
              title: pluralWord(profile.registeredActions, 'ação registrada', 'ações registradas'),
              subtitle: actionParts.isEmpty ? null : actionParts.join(' · '),
            ),
          ),
        ),
        const SizedBox(height: 10),
        WideStat(
          value: formatCount(profile.reachedResolution),
          faintValue: profile.reachedResolution == 0,
          title: 'Demandas acompanhadas que chegaram à resolução',
          subtitle: 'Com ação registrada antes da confirmação',
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.item, required this.last});

  final InstitutionalActivity item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final occurrence = item.occurrence;
    final description = item.description.trim();
    return InkWell(
      onTap: () => openOccurrence(context, occurrenceId: item.occurrenceId, initial: occurrence),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActionGlyph(councilorActionIcon(item.actionType)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    councilorActionLabels[item.actionType] ?? 'Ação registrada',
                    style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, height: 1.28),
                  ),
                  if (occurrence != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      occurrence.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tileSubtitleStyle(UrbColors.blue).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: tileSubtitleStyle()),
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
