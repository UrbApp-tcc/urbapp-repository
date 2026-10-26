import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/notifications_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../home/all_occurrences_screen.dart';
import 'city_indicators_screen.dart';
import 'entity_list_screens.dart';
import 'transparency_kit.dart';

/// Transparência é a visão pública e contínua da cidade (spec §33, §44.5–44.6),
/// a mesma para todos os papéis (§44.7). O hub é feito de blocos, cada um uma
/// única porta: o panorama leva aos indicadores, a Prefeitura à Gestão (e dela
/// aos órgãos), e há blocos para vereadores, ocorrências e rankings.
///
/// Sem [cityId], é a aba principal e acompanha a cidade selecionada. Com
/// [cityId], abre como página (com voltar) para qualquer cidade, por exemplo a
/// partir do comparativo de cidades.
class TransparencyScreen extends StatefulWidget {
  const TransparencyScreen({super.key, this.cityId});

  final int? cityId;

  @override
  State<TransparencyScreen> createState() => _TransparencyScreenState();
}

class _TransparencyScreenState extends State<TransparencyScreen> {
  final _service = TransparencyService();
  final _session = AppSession.instance;

  CityPanorama? _panorama;
  AdministrationProfile? _administration;
  List<AgencyProfile> _agencies = const [];
  List<CouncilorProfile> _councilors = const [];
  bool _loading = true;
  String? _error;
  int _loadRequest = 0;

  bool get _isTab => widget.cityId == null;
  int? get _cityId => widget.cityId ?? _session.city.value?.id;

  @override
  void initState() {
    super.initState();
    if (_isTab) _session.city.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    if (_isTab) _session.city.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    var cityId = _cityId;
    setState(() {
      _loading = _panorama == null || _panorama!.cityId != cityId;
      _error = null;
    });
    try {
      if (cityId == null) {
        await _session.init();
        cityId = _cityId;
      }
      if (cityId == null) {
        throw Exception(_session.initializationError ?? 'Não foi possível carregar as cidades. Tente novamente.');
      }
      final results = await Future.wait<dynamic>([
        _service.fetchCityPanorama(cityId),
        _service.fetchCurrentAdministration(cityId),
        _service.fetchAgencies(cityId),
        _service.fetchCouncilors(cityId),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _panorama = results[0] as CityPanorama;
        _administration = results[1] as AdministrationProfile?;
        _agencies = results[2] as List<AgencyProfile>;
        _councilors = results[3] as List<CouncilorProfile>;
      });
    } catch (error) {
      if (mounted && request == _loadRequest) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted && request == _loadRequest) setState(() => _loading = false);
    }
  }

  Future<void> _pickCity() async {
    final picked = await showCityPicker(context, cities: _session.cities, selected: _session.city.value);
    if (picked != null) _session.city.value = picked;
  }

  @override
  Widget build(BuildContext context) {
    final panorama = _panorama;
    final Widget body;
    if (_error != null) {
      body = UrbErrorState(message: _error!, onRetry: _load);
    } else if (_loading || panorama == null) {
      body = const UrbLoadingView();
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
          children: [
            if (_isTab) _cityLine(panorama),
            _panoramaTile(panorama),
            const SizedBox(height: 10),
            TilePair(left: _administrationTile(), right: _councilorsTile(panorama)),
            const SizedBox(height: 10),
            TilePair(left: _occurrencesTile(panorama), right: _rankingsTile()),
            if (panorama.outsideMunicipal > 0) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${plural(panorama.outsideMunicipal, 'ocorrência está', 'ocorrências estão')} fora da competência '
                  'municipal e não entra${panorama.outsideMunicipal == 1 ? '' : 'm'} nos indicadores.',
                  style: tileSubtitleStyle(),
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (!_isTab) {
      return Scaffold(
        backgroundColor: UrbColors.canvas,
        appBar: UrbSubscreenHeader(title: panorama == null ? 'Transparência' : 'Transparência · ${panorama.cityName}'),
        body: body,
      );
    }
    return Column(
      children: [
        UrbScreenHeader(
          title: 'Transparência',
          actions: [
            ValueListenableBuilder<int>(
              valueListenable: NotificationsService.unreadCount,
              builder: (context, count, _) => UrbBellButton(unreadCount: count, onPressed: () => openAlerts(context)),
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }

  /// Cidade da aba, com troca rápida.
  Widget _cityLine(CityPanorama panorama) {
    final label = [panorama.cityName, if (panorama.stateCode.isNotEmpty) panorama.stateCode].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: 'Cidade: $label. Trocar cidade',
          excludeSemantics: true,
          onTap: _pickCity,
          child: InkWell(
            onTap: _pickCity,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: UrbText.title.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  const UrbIcon(UrbIcons.chevronDown, size: 16, color: UrbColors.blue, strokeWidth: 2.4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panoramaTile(CityPanorama panorama) {
    return BentoTile(
      height: 182,
      padding: const EdgeInsets.all(18),
      semanticsLabel: 'Panorama da cidade. ${panorama.resolved} de ${panorama.total} ocorrências resolvidas e '
          'confirmadas por vizinhos. Ver indicadores',
      onTap: () => Navigator.of(context).push(
        urbRoute(CityIndicatorsScreen(cityId: panorama.cityId, cityName: panorama.cityName)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(
                  TextSpan(
                    text: formatCount(panorama.resolved),
                    children: [
                      TextSpan(text: ' de ${formatCount(panorama.total)}', style: const TextStyle(color: kFaint)),
                    ],
                  ),
                  maxLines: 1,
                  style: bigNumberStyle(44),
                ),
                const TileStat(
                  title: 'Panorama da cidade',
                  subtitle: 'Ocorrências resolvidas e confirmadas por vizinhos',
                  titleSize: 15,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ResolutionRing(total: panorama.total, resolved: panorama.resolved, active: panorama.inProgress, size: 92),
        ],
      ),
    );
  }

  Widget _administrationTile() {
    final administration = _administration;
    final agencies = plural(_agencies.length, 'órgão', 'órgãos');
    return StatTile(
      tone: TileTone.navy,
      height: 188,
      glyph: const BuildingGlyph(width: 40),
      stat: TileStat(
        tone: TileTone.navy,
        title: 'Prefeitura',
        subtitle: administration == null ? agencies : '${administration.periodLabel}\n$agencies',
        titleSize: 15,
      ),
      semanticsLabel: 'Prefeitura. ${administration?.periodLabel ?? ''}. $agencies',
      onTap: administration != null
          ? () => openAdministration(context, administrationId: administration.id)
          // Sem gestão cadastrada, os órgãos continuam alcançáveis.
          : _agencies.isEmpty
          ? null
          : () => Navigator.of(context).push(urbRoute(AgenciesListScreen(agencies: _agencies))),
    );
  }

  Widget _councilorsTile(CityPanorama panorama) {
    final count = _councilors.length;
    final subtitle = count == 0
        ? 'Nenhum perfil verificado ainda'
        : '${plural(count, 'perfil verificado', 'perfis verificados')}\nAcompanhar é opcional';
    return StatTile(
      height: 188,
      glyph: const PeopleGlyph(),
      stat: TileStat(title: 'Vereadores', subtitle: subtitle, titleSize: 15),
      semanticsLabel: 'Vereadores. $subtitle',
      onTap: () => Navigator.of(context).push(
        urbRoute(CouncilorsListScreen(councilors: _councilors, cityName: panorama.cityName)),
      ),
    );
  }

  Widget _occurrencesTile(CityPanorama panorama) {
    return StatTile(
      height: 188,
      glyph: const ScatterGlyph(),
      stat: TileStat(
        value: formatCount(panorama.total),
        title: 'Ocorrências',
        subtitle: 'Lista e mapa, com filtros',
        titleSize: 15,
      ),
      semanticsLabel: 'Ocorrências da cidade, ${panorama.total}. Lista e mapa, com filtros',
      onTap: () => Navigator.of(context).push(
        urbRoute(AllOccurrencesScreen(cityId: panorama.cityId, cityName: panorama.cityName)),
      ),
    );
  }

  Widget _rankingsTile() {
    return StatTile(
      tone: TileTone.lime,
      height: 188,
      glyph: const BarsGlyph(),
      stat: const TileStat(
        tone: TileTone.lime,
        title: 'Rankings',
        subtitle: 'Cidades e cidadãos. Políticos não entram.',
        titleSize: 15,
      ),
      semanticsLabel: 'Rankings. Cidades e cidadãos. Políticos não entram.',
      onTap: () => openRankings(context),
    );
  }
}
