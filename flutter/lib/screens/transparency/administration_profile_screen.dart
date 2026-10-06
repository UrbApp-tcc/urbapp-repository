import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'activity_list.dart';
import 'entity_list_screens.dart';
import 'transparency_widgets.dart';

/// Perfil público "Prefeitura de `cidade` · Gestão `início–fim`" (spec §11, §44.6).
/// O prefeito é informação contextual; a gestão nunca "resolve" ocorrências.
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
        _service.fetchAdministrationActivity(profile.id),
        _service.fetchAdministrationHistory(profile.cityId),
      ]);
      final activity = await attachOccurrences(results[1] as List<InstitutionalActivity>);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _agencies = results[0] as List<AgencyProfile>;
        _activity = activity;
        _history = results[2] as List<AdministrationProfile>;
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
    return PublicProfileScaffold(
      body: profile == null
          ? (_loading ? const UrbLoadingView() : UrbErrorState(message: _error ?? '', onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  PublicIdentity(
                    mark: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [UrbColors.navy, Color(0xFF1E3A5F)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const UrbIcon(UrbIcons.transparency, size: 28, color: Colors.white),
                    ),
                    overline: profile.title,
                    title: profile.periodLabel,
                    lines: [
                      if (profile.mayorName != null) 'Prefeito(a): ${profile.mayorName}',
                      if (!profile.isPlaceholder) 'Período ${formatDate(profile.startsOn)}${profile.endsOn == null ? '' : ' a ${formatDate(profile.endsOn!)}'}',
                    ],
                    verificationLabel: profile.isVerified
                        ? 'Perfil da administração municipal verificado'
                        : 'Perfil institucional ainda não reivindicado',
                    verified: profile.isVerified,
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DataSourceNote('Indicadores calculados pelo UrbApp · ${profile.periodLabel}'),
                        Text(formatCount(profile.registered), style: UrbText.hero),
                        const SizedBox(height: 7),
                        Text('ocorrências registradas durante a gestão', style: UrbText.title.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          '+ ${formatCount(profile.inherited)} herdadas da gestão anterior',
                          style: UrbText.meta.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.only(top: 16),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: UrbColors.line))),
                          child: UrbStatRow(
                            items: [
                              UrbStatItem(formatCount(profile.resolvedDuringPeriod), pluralWord(profile.resolvedDuringPeriod, 'resolução confirmada no período', 'resoluções confirmadas no período')),
                              UrbStatItem(formatCount(profile.active), pluralWord(profile.active, 'pendente', 'pendentes')),
                              UrbStatItem(formatDays(profile.averageFirstManifestationSeconds), 'dias até 1ª manifestação'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        RateNote(
                          value: '${profile.manifestationRate.round()}%',
                          label: 'das ocorrências com manifestação oficial publicada',
                        ),
                        if (profile.leftPending > 0) ...[
                          const SizedBox(height: 10),
                          Text('${plural(profile.leftPending, 'ocorrência deixada pendente', 'ocorrências deixadas pendentes')} na transição de gestão.', style: UrbText.caption),
                        ],
                      ],
                    ),
                  ),
                  TransSection(
                    white: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DataSourceNote('Ações oficiais registradas no UrbApp', official: true),
                        UrbStatRow(
                          items: [
                            UrbStatItem(formatCount(profile.prioritized), pluralWord(profile.prioritized, 'priorizada', 'priorizadas')),
                            UrbStatItem(formatCount(profile.forwarded), pluralWord(profile.forwarded, 'encaminhada', 'encaminhadas')),
                            UrbStatItem(formatCount(profile.forecasted), 'com previsão'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        UrbStatRow(
                          items: [
                            UrbStatItem(formatCount(profile.conclusionsInformed), pluralWord(profile.conclusionsInformed, 'conclusão informada', 'conclusões informadas')),
                            UrbStatItem(formatCount(profile.confirmedConclusions), pluralWord(profile.confirmedConclusions, 'confirmada pela comunidade', 'confirmadas pela comunidade')),
                            UrbStatItem(formatCount(profile.rejectedConclusions), pluralWord(profile.rejectedConclusions, 'rejeitada pela comunidade', 'rejeitadas pela comunidade')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Conclusões informadas pela gestão só viram resolução após validação comunitária.',
                          style: UrbText.caption,
                        ),
                      ],
                    ),
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TransEyebrow('Órgãos da gestão'),
                        for (var index = 0; index < _agencies.length; index++)
                          AgencyListRow(agency: _agencies[index], index: index, last: index == _agencies.length - 1),
                        if (_agencies.isEmpty) Text('Nenhum órgão cadastrado.', style: UrbText.caption),
                      ],
                    ),
                  ),
                  TransSection(
                    last: _history.length < 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TransEyebrow('Atuação da gestão', subtitle: 'Ações oficiais registradas no UrbApp'),
                        ActivityList(
                          items: _activity,
                          labels: institutionalActionLabels,
                          emptyMessage: 'A gestão ainda não registrou ações oficiais no UrbApp. As ocorrências continuam vinculadas a ela.',
                        ),
                      ],
                    ),
                  ),
                  if (_history.length > 1)
                    TransSection(
                      last: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const TransEyebrow('Histórico de gestões', subtitle: 'Cada gestão mantém seus próprios indicadores'),
                          for (var index = 0; index < _history.length; index++)
                            UrbDotRow(
                              title: _history[index].periodLabel,
                              subtitle: [
                                if (_history[index].mayorName != null) _history[index].mayorName!,
                                '${_history[index].registered} registradas · ${_history[index].resolvedDuringPeriod} resoluções no período',
                              ].join(' · '),
                              dotColor: _history[index].id == profile.id ? UrbColors.blue : UrbColors.slate,
                              last: index == _history.length - 1,
                              onTap: _history[index].id == profile.id
                                  ? null
                                  : () => openAdministration(context, administrationId: _history[index].id),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
