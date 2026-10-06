import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import 'activity_list.dart';
import 'transparency_widgets.dart';

/// Perfil público de vereador: atividade factual, sem nota, score ou ranking.
/// Usa "demandas acompanhadas que chegaram à resolução" (spec §3.4, §35).
class CouncilorProfileScreen extends StatefulWidget {
  const CouncilorProfileScreen({super.key, required this.councilorProfileId});

  final int councilorProfileId;

  @override
  State<CouncilorProfileScreen> createState() => _CouncilorProfileScreenState();
}

class _CouncilorProfileScreenState extends State<CouncilorProfileScreen> {
  final _service = TransparencyService();

  CouncilorProfile? _profile;
  String _cityName = '';
  List<(CouncilorFollowingItem, Occurrence)> _followings = const [];
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
      final profile = await _service.fetchCouncilor(widget.councilorProfileId);
      if (profile == null) {
        if (mounted) setState(() => _error = 'Perfil de vereador não encontrado.');
        return;
      }
      final results = await Future.wait<dynamic>([
        InstitutionalService().fetchCouncilorFollowings(profile.id, activeOnly: true),
        _service.fetchCouncilorActivity(profile.id),
        OccurrenceService().fetchCities(),
      ]);
      final followings = results[0] as List<CouncilorFollowingItem>;
      final occurrences = await OccurrenceService().fetchByIds(followings.map((item) => item.occurrenceId));
      final byId = {for (final occurrence in occurrences) occurrence.id: occurrence};
      final activity = await attachOccurrences(results[1] as List<InstitutionalActivity>);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _cityName = (results[2] as List<CityOption>).where((city) => city.id == profile.cityId).firstOrNull?.name ?? '';
        _followings = [
          for (final item in followings)
            if (byId[item.occurrenceId] != null) (item, byId[item.occurrenceId]!),
        ];
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
                    mark: PersonAvatar(name: profile.publicName, seed: profile.id, size: 80),
                    title: profile.publicName,
                    lines: [
                      'Vereador(a) de $_cityName',
                      [profile.mandateLabel, if (profile.party != null) profile.party!].where((part) => part.isNotEmpty).join(' · '),
                    ],
                    verificationLabel: 'Perfil verificado no UrbApp',
                    verified: profile.status.isVerified,
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DataSourceNote('Atividade registrada na plataforma'),
                        UrbStatRow(
                          big: true,
                          items: [
                            UrbStatItem(formatCount(profile.followedOpen), pluralWord(profile.followedOpen, 'demanda em acompanhamento', 'demandas em acompanhamento')),
                            UrbStatItem(formatCount(profile.registeredActions), pluralWord(profile.registeredActions, 'ação registrada', 'ações registradas')),
                            UrbStatItem(formatCount(profile.awaitingResponse), 'aguardando retorno'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: UrbColors.line),
                          ),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${profile.reachedResolution} ',
                                style: const TextStyle(color: UrbColors.navy, fontWeight: FontWeight.w800),
                              ),
                              const TextSpan(text: 'demandas acompanhadas que chegaram à resolução'),
                            ]),
                            style: UrbText.meta.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Conta apenas acompanhamentos com ação concreta registrada antes da resolução confirmada pela comunidade. '
                          'O indicador não atribui a solução ao vereador. '
                          '${plural(profile.followed, 'demanda acompanhada', 'demandas acompanhadas')} no total · ${plural(profile.endedWithoutResolution, 'encerrada', 'encerradas')} sem resolução.',
                          style: UrbText.caption,
                        ),
                      ],
                    ),
                  ),
                  TransSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TransEyebrow('Demandas em acompanhamento'),
                        if (_followings.isEmpty)
                          Text('Nenhuma demanda em acompanhamento no momento.', style: UrbText.caption)
                        else
                          for (var index = 0; index < _followings.length; index++)
                            RelatedOccurrenceRow(
                              occurrence: _followings[index].$2,
                              note: '↳ ${_followings[index].$1.lastActionType != null ? councilorActionLabels[_followings[index].$1.lastActionType] : councilorFollowingStatusLabels[_followings[index].$1.status]}',
                              last: index == _followings.length - 1,
                            ),
                      ],
                    ),
                  ),
                  TransSection(
                    last: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TransEyebrow('Atuação recente'),
                        ActivityList(items: _activity, labels: councilorActionLabels),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
