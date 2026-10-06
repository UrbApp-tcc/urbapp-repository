import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import 'activity_list.dart';
import 'transparency_widgets.dart';

/// Perfil público de órgão: indicadores calculados pelo UrbApp separados das
/// atualizações oficiais publicadas pelo órgão (spec §12, §44.6).
class AgencyProfileScreen extends StatefulWidget {
  const AgencyProfileScreen({super.key, required this.agencyId});

  final int agencyId;

  @override
  State<AgencyProfileScreen> createState() => _AgencyProfileScreenState();
}

class _AgencyProfileScreenState extends State<AgencyProfileScreen> {
  final _service = TransparencyService();
  final _occurrences = OccurrenceService();

  AgencyProfile? _agency;
  List<Occurrence> _related = const [];
  List<InstitutionalActivity> _activity = const [];
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
      final agency = await _service.fetchAgency(widget.agencyId);
      if (agency == null) {
        if (mounted) setState(() => _error = 'Órgão não encontrado.');
        return;
      }
      final results = await Future.wait<dynamic>([
        _occurrences.fetchByAgency(agency.id, activeOnly: true, limit: 5),
        _service.fetchAgencyActivity(agency.id),
      ]);
      final activity = await attachOccurrences(results[1] as List<InstitutionalActivity>);
      if (!mounted) return;
      setState(() {
        _agency = agency;
        _related = results[0] as List<Occurrence>;
        _activity = activity;
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
    return PublicProfileScaffold(
      body: agency == null
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
                        color: const Color(0xFFEEF0FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: UrbColors.blue.withValues(alpha: 0.25), width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        agency.abbreviation,
                        style: UrbText.label.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                      ),
                    ),
                    title: agency.name,
                    lines: const ['Órgão municipal'],
                    chips: agency.categories,
                    verificationLabel: switch (agency.status) {
                      InstitutionalProfileStatus.participant => 'Perfil institucional verificado e participante',
                      InstitutionalProfileStatus.verified => 'Perfil institucional verificado',
                      InstitutionalProfileStatus.unclaimed => 'Perfil institucional ainda não reivindicado',
                    },
                    verified: agency.status.isVerified,
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DataSourceNote('Indicadores calculados pelo UrbApp'),
                        UrbStatRow(
                          big: true,
                          items: [
                            UrbStatItem(formatCount(agency.assigned), pluralWord(agency.assigned, 'ocorrência associada', 'ocorrências associadas')),
                            UrbStatItem(formatCount(agency.resolved), pluralWord(agency.resolved, 'resolvida', 'resolvidas')),
                            UrbStatItem(formatDays(agency.medianResponsibilitySeconds), 'dias de responsabilidade mediana'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${agency.open} abertas · ${agency.inProgress} em andamento · ${agency.awaitingValidation} aguardando validação',
                          style: UrbText.meta.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        RateNote(
                          value: '${agency.officialResponsePercentage.round()}%',
                          label: 'das ocorrências com resposta oficial publicada',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Resoluções contam para o órgão responsável no momento em que a comunidade confirmou. '
                          'Reencaminhamentos preservam o período de cada órgão.',
                          style: UrbText.caption,
                        ),
                      ],
                    ),
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TransEyebrow(
                          'Ocorrências relacionadas',
                          subtitle: 'Em aberto sob responsabilidade do órgão',
                          trailing: agency.current > _related.length
                              ? UrbSeeAll(
                                  onPressed: () => Navigator.of(context).push(urbRoute(_AgencyOccurrencesScreen(agency: agency))),
                                )
                              : null,
                        ),
                        if (_related.isEmpty)
                          Text('Nenhuma ocorrência em aberto.', style: UrbText.caption)
                        else
                          for (var index = 0; index < _related.length; index++)
                            RelatedOccurrenceRow(occurrence: _related[index], last: index == _related.length - 1),
                      ],
                    ),
                  ),
                  TransSection(
                    last: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TransEyebrow('Atualizações oficiais', subtitle: 'Publicadas pelo órgão no UrbApp'),
                        ActivityList(
                          items: _activity,
                          labels: institutionalActionLabels,
                          emptyMessage: agency.status.isVerified
                              ? 'O órgão ainda não publicou atualizações.'
                              : 'Sem atualizações oficiais: o perfil ainda não foi reivindicado pelo órgão.',
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

class _AgencyOccurrencesScreen extends StatefulWidget {
  const _AgencyOccurrencesScreen({required this.agency});

  final AgencyProfile agency;

  @override
  State<_AgencyOccurrencesScreen> createState() => _AgencyOccurrencesScreenState();
}

class _AgencyOccurrencesScreenState extends State<_AgencyOccurrencesScreen> {
  List<Occurrence>? _items;

  @override
  void initState() {
    super.initState();
    OccurrenceService().fetchByAgency(widget.agency.id, limit: 100).then((value) {
      if (mounted) setState(() => _items = value);
    }).catchError((Object error) {
      if (mounted) setState(() => _items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(title: widget.agency.name),
      body: items == null
          ? const UrbLoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                for (var index = 0; index < items.length; index++)
                  RelatedOccurrenceRow(occurrence: items[index], last: index == items.length - 1),
              ],
            ),
    );
  }
}
