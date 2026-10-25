import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/notifications_service.dart';
import '../../services/ranking_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../../domain/occurrence_status.dart';
import '../../utils/date_formatter.dart';
import '../home/all_occurrences_screen.dart';
import 'entity_list_screens.dart';
import 'transparency_widgets.dart';

/// Transparência é a visão pública e contínua da cidade (spec §33, §44.5–44.6):
/// a cidade (panorama e indicadores) → quem responde por ela (Gestão vigente e
/// órgãos) → vereadores → comparação entre cidades e participação.
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
  ParticipationStanding? _standing;
  bool _loading = true;
  String? _error;
  bool _detailsOpen = false;
  bool _loadingDetails = false;
  CityPanorama? _details;
  int _loadRequest = 0;

  bool get _isTab => widget.cityId == null;
  int? get _cityId => widget.cityId ?? _session.city.value?.id;

  @override
  void initState() {
    super.initState();
    if (_isTab) _session.city.addListener(_onCityChanged);
    _load();
  }

  @override
  void dispose() {
    if (_isTab) _session.city.removeListener(_onCityChanged);
    super.dispose();
  }

  void _onCityChanged() {
    setState(() {
      _details = null;
      _detailsOpen = false;
    });
    _load();
  }

  /// Evolução, categorias e regiões só são carregadas quando abertas.
  Future<void> _toggleDetails() async {
    final cityId = _cityId;
    if (_detailsOpen) {
      setState(() => _detailsOpen = false);
      return;
    }
    setState(() => _detailsOpen = true);
    if (_details != null || cityId == null) return;
    setState(() => _loadingDetails = true);
    try {
      final details = await _service.fetchCityPanorama(cityId, detailed: true);
      if (mounted) setState(() => _details = details);
    } catch (error) {
      if (mounted) {
        setState(() => _detailsOpen = false);
        showUrbToast(context, friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  /// Posição do usuário para a seção Rankings; falhas não bloqueiam a tela.
  Future<void> _loadRankings(int cityId) async {
    try {
      final standing = await RankingService().fetchStanding(cityId);
      if (mounted) setState(() => _standing = standing);
    } catch (_) {
      // A seção Rankings é complementar na Transparência.
    }
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    var cityId = _cityId;
    setState(() {
      _loading = _panorama == null;
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
      _loadRankings(cityId);
    } catch (error) {
      if (mounted && request == _loadRequest) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted && request == _loadRequest) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const UrbLoadingView()
        : _error != null
        ? UrbErrorState(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                _panoramaSection(),
                if (_detailsOpen) _detailsSection(),
                _institutionsSection(),
                _councilorsSection(),
                _rankingsSection(),
              ],
            ),
          );
    if (!_isTab) {
      return Scaffold(
        backgroundColor: UrbColors.canvas,
        appBar: const UrbSubscreenHeader(title: 'Transparência'),
        body: content,
      );
    }
    final city = _session.city.value;
    return Column(
      children: [
        UrbScreenHeader(
          title: 'Transparência',
          actions: [
            UrbSquareButton(
              icon: UrbIcons.location,
              tooltip: 'Trocar cidade',
              onPressed: () async {
                final picked = await showCityPicker(context, cities: _session.cities, selected: city);
                if (picked != null) _session.city.value = picked;
              },
            ),
            ValueListenableBuilder<int>(
              valueListenable: NotificationsService.unreadCount,
              builder: (context, count, _) => UrbBellButton(unreadCount: count, onPressed: () => openAlerts(context)),
            ),
          ],
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _detailsSection() {
    final details = _details;
    if (_loadingDetails || details == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: UrbLoadingView());
    }
    return _CityDetails(panorama: details);
  }

  // ---------------------------------------------------------------------------
  // 1. Panorama: um número editorial e a proporção dos estados da cidade.
  // ---------------------------------------------------------------------------

  Widget _panoramaSection() {
    final panorama = _panorama!;
    final segments = [
      ProportionSegment(panorama.resolved, pluralWord(panorama.resolved, 'resolvida', 'resolvidas'), UrbColors.navy),
      ProportionSegment(panorama.inProgress, 'em andamento', UrbColors.blue),
      ProportionSegment(panorama.awaitingValidation, 'aguardando validação', UrbColors.blue.withValues(alpha: 0.35)),
      ProportionSegment(panorama.open, pluralWord(panorama.open, 'aberta', 'abertas'), const Color(0xFFCBD3DC)),
    ];
    final facts = [
      'de ${plural(panorama.total, 'ocorrência registrada', 'ocorrências registradas')}',
      'taxa de ${formatDecimal(panorama.resolutionRate)}%',
      if (panorama.medianResolutionSeconds != null) 'mediana de ${_daysLabel(panorama.medianResolutionSeconds)}',
    ];
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        const Positioned(top: -70, right: -95, child: UrbBrandGeometry(large: false)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${panorama.cityName.toUpperCase()} · HISTÓRICO DA CIDADE',
                style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4),
              ),
              const SizedBox(height: 18),
              Text(formatCount(panorama.resolved), style: UrbText.hero.copyWith(fontSize: 76, height: 0.84)),
              const SizedBox(height: 10),
              Text(
                panorama.resolved == 1
                    ? 'ocorrência resolvida e confirmada pela comunidade'
                    : 'ocorrências resolvidas e confirmadas pela comunidade',
                style: UrbText.h3.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2),
              ),
              const SizedBox(height: 8),
              Text(facts.join(' · '), style: UrbText.meta.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 22),
              ProportionBar(segments: segments, total: panorama.total),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [for (final segment in segments) ProportionLegend(segment: segment)],
              ),
              if (panorama.outsideMunicipal > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '${plural(panorama.outsideMunicipal, 'ocorrência', 'ocorrências')} fora da competência municipal, '
                  'sem efeito nos indicadores da cidade.',
                  style: UrbText.caption,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 4,
                children: [
                  UrbTextButton(
                    _detailsOpen ? 'Ocultar indicadores detalhados' : 'Ver indicadores detalhados',
                    onPressed: _toggleDetails,
                  ),
                  UrbTextButton(
                    'Ver ocorrências',
                    onPressed: () => Navigator.of(
                      context,
                    ).push(urbRoute(AllOccurrencesScreen(cityId: panorama.cityId, cityName: panorama.cityName))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Quem responde pela cidade: Gestão Municipal à frente, órgãos abaixo.
  // ---------------------------------------------------------------------------

  Widget _institutionsSection() {
    final administration = _administration;
    final cityName = _panorama?.cityName ?? '';
    const previewCount = 5;
    final preview = _agencies.take(previewCount).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: UrbColors.line),
          bottom: BorderSide(color: UrbColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUEM RESPONDE PELA CIDADE',
            style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: administration != null,
            label: 'Gestão municipal: Prefeitura de $cityName',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: administration == null
                  ? null
                  : () => openAdministration(context, administrationId: administration.id),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: UrbColors.navy, borderRadius: BorderRadius.circular(13)),
                    alignment: Alignment.center,
                    child: const UrbIcon(UrbIcons.transparency, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gestão municipal', style: UrbText.caption.copyWith(fontWeight: FontWeight.w700)),
                        Text('Prefeitura de $cityName', style: UrbText.h3.copyWith(fontSize: 17)),
                        Text(
                          [
                            administration?.periodLabel ?? 'Gestão vigente',
                            if (administration?.mayorName != null) 'Prefeito(a) ${administration!.mayorName}',
                          ].join(' · '),
                          style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w700),
                        ),
                        if (administration != null && !administration.isVerified)
                          Text(
                            'Perfil institucional ainda não reivindicado',
                            style: UrbText.caption.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const UrbIcon(UrbIcons.chevron, size: 17, color: UrbColors.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Órgãos públicos',
                style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Text('${_agencies.length}', style: UrbText.caption.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_agencies.length > previewCount)
                UrbSeeAll(
                  label: 'Ver todos',
                  onPressed: () => Navigator.of(context).push(urbRoute(AgenciesListScreen(agencies: _agencies))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Nenhum órgão cadastrado.', style: UrbText.caption),
            )
          else
            for (var index = 0; index < preview.length; index++)
              AgencyListRow(agency: preview[index], index: index, last: index == preview.length - 1),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Vereadores: pessoas, sem notas nem classificação.
  // ---------------------------------------------------------------------------

  Widget _councilorsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VEREADORES', style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
                    const SizedBox(height: 4),
                    Text(
                      _councilors.isEmpty
                          ? 'Nenhum vereador verificado no UrbApp'
                          : plural(_councilors.length, 'representante verificado', 'representantes verificados'),
                      style: UrbText.caption.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (_councilors.isNotEmpty)
                UrbSeeAll(
                  label: 'Ver todos',
                  onPressed: () => Navigator.of(context).push(urbRoute(CouncilorsListScreen(councilors: _councilors))),
                ),
            ],
          ),
          if (_councilors.isNotEmpty) ...[const SizedBox(height: 16), CouncilorStrip(councilors: _councilors)],
          const SizedBox(height: 10),
          Text(
            'Atividade registrada na plataforma, sem notas ou classificação de desempenho político.',
            style: UrbText.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Rankings: faixa própria, com a taxa da cidade e a posição do usuário
  // como âncoras visuais e uma única ação.
  // ---------------------------------------------------------------------------

  Widget _rankingsSection() {
    final panorama = _panorama!;
    final standing = _standing;
    final position = standing?.eligible == true ? standing?.position : null;
    final rate = '${formatDecimal(panorama.resolutionRate)}%';
    final positionLabel = position != null
        ? 'sua posição entre ${plural(standing!.participants, 'cidadão', 'cidadãos')}'
        : (standing?.reason == 'institutional'
              ? 'perfis institucionais não entram no ranking de cidadãos'
              : 'você ainda não aparece no ranking de cidadãos');
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Semantics(
        button: true,
        label:
            'Rankings. $rate de taxa de resolução em ${panorama.cityName}. '
            '${position != null ? 'Você está em $positionº.' : positionLabel}. Ver rankings',
        excludeSemantics: true,
        onTap: () => openRankings(context),
        child: Material(
          color: UrbColors.blueSoft,
          child: InkWell(
            onTap: () => openRankings(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: UrbColors.line),
                  bottom: BorderSide(color: UrbColors.line),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rankings', style: UrbText.h3.copyWith(fontSize: 19)),
                  const SizedBox(height: 2),
                  Text('Como ${panorama.cityName} e você aparecem nas comparações', style: UrbText.caption),
                  const SizedBox(height: 18),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _rankingFigure(
                            value: rate,
                            label: 'taxa de resolução de ${panorama.cityName}',
                            color: UrbColors.navy,
                          ),
                        ),
                        Container(width: 1, color: UrbColors.blue.withValues(alpha: 0.18)),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _rankingFigure(
                            value: position != null ? '$positionº' : '—',
                            label: positionLabel,
                            color: UrbColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Ver rankings',
                        style: UrbText.label.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
                      ),
                      const UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankingFigure({required String value, required String label, required Color color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: UrbText.hero.copyWith(fontSize: 40, letterSpacing: -2, height: 1, color: color)),
      const SizedBox(height: 6),
      Text(label, style: UrbText.caption.copyWith(color: UrbColors.textSecondary, height: 1.3)),
    ],
  );
}

const _monthAbbreviations = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/// Indicadores detalhados da cidade, abertos sob demanda dentro da
/// Transparência: estados, tempos, evolução, categorias e regiões.
class _CityDetails extends StatelessWidget {
  const _CityDetails({required this.panorama});

  final CityPanorama panorama;

  // Mesma leitura da barra do panorama: resolvidas em navy, andamento em azul,
  // aguardando em azul claro, abertas em cinza; reabertas e análise à parte.
  static Color _colorOf(OccurrenceStatus status) => switch (status) {
    OccurrenceStatus.resolved => UrbColors.navy,
    OccurrenceStatus.inProgress => UrbColors.blue,
    OccurrenceStatus.awaitingValidation => UrbColors.blue.withValues(alpha: 0.35),
    OccurrenceStatus.inAnalysis => UrbColors.amber,
    OccurrenceStatus.reopened => UrbColors.warning,
    OccurrenceStatus.closed => UrbColors.muted,
    _ => const Color(0xFFCBD3DC),
  };

  @override
  Widget build(BuildContext context) {
    final rows = [
      (OccurrenceStatus.open, panorama.open),
      (OccurrenceStatus.inAnalysis, panorama.inAnalysis),
      (OccurrenceStatus.inProgress, panorama.inProgressOnly),
      (OccurrenceStatus.awaitingValidation, panorama.awaitingValidation),
      (OccurrenceStatus.reopened, panorama.reopened),
      (OccurrenceStatus.resolved, panorama.resolved),
      if (panorama.closed > 0) (OccurrenceStatus.closed, panorama.closed),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SITUAÇÃO ATUAL', style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          for (var index = 0; index < rows.length; index++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: index == rows.length - 1 ? null : const Border(bottom: BorderSide(color: UrbColors.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: _colorOf(rows[index].$1), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[index].$1 == OccurrenceStatus.closed ? 'Encerradas sem resolução' : rows[index].$1.label,
                      style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    formatCount(rows[index].$2),
                    style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_daysLabel(panorama.medianResolutionSeconds), style: UrbText.stat.copyWith(fontSize: 20)),
                    const SizedBox(height: 2),
                    Text('tempo mediano até a resolução', style: UrbText.caption),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _daysLabel(panorama.averageResolutionSeconds),
                      style: UrbText.title.copyWith(color: UrbColors.textSecondary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text('tempo médio, complementar', style: UrbText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text('EVOLUÇÃO', style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
          const SizedBox(height: 4),
          Text('Registradas por mês de criação e quantas já foram resolvidas', style: UrbText.caption),
          const SizedBox(height: 14),
          if (panorama.monthly.isEmpty)
            Text('Sem dados no período.', style: UrbText.caption)
          else ...[
            _MonthlyChart(points: panorama.monthly),
            const SizedBox(height: 10),
            Row(
              children: [
                _legend(UrbColors.blue.withValues(alpha: 0.35), 'Registradas'),
                const SizedBox(width: 14),
                _legend(UrbColors.navy, 'Resolvidas'),
              ],
            ),
          ],
          const SizedBox(height: 26),
          _breakdown('Categorias', panorama.categories),
          const SizedBox(height: 22),
          _breakdown('Regiões', panorama.neighborhoods),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(label, style: UrbText.caption),
    ],
  );

  Widget _breakdown(String title, List<Breakdown> items) {
    final maxValue = items.fold<int>(1, (max, item) => item.total > max ? item.total : max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Text('Sem dados suficientes.', style: UrbText.caption)
        else
          for (final item in items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.label, style: UrbText.label.copyWith(color: UrbColors.navy)),
                      ),
                      Text(
                        '${formatCount(item.total)} · ${item.resolved} ${pluralWord(item.resolved, 'resolvida', 'resolvidas')}',
                        style: UrbText.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(height: 5, color: UrbColors.line),
                        FractionallySizedBox(
                          widthFactor: item.total / maxValue,
                          child: Container(height: 5, color: UrbColors.blue.withValues(alpha: 0.35)),
                        ),
                        FractionallySizedBox(
                          widthFactor: item.resolved / maxValue,
                          child: Container(height: 5, color: UrbColors.navy),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.points});

  final List<MonthlyPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<int>(1, (max, point) => point.registered > max ? point.registered : max);
    return Semantics(
      label: 'Ocorrências registradas e resolvidas por mês de criação',
      child: SizedBox(
        height: 130,
        // Barras com largura limitada: o gráfico fica legível com 1 ou 12 meses.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = (constraints.maxWidth / 12).clamp(18.0, 30.0) - 6;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  SizedBox(
                    width: barWidth + 6,
                    child: Tooltip(
                      message:
                          '${formatMonthYear(point.month)}: ${point.registered} registradas, ${point.resolved} resolvidas',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                Container(
                                  height: 96 * point.registered / maxValue + 2,
                                  decoration: BoxDecoration(
                                    color: UrbColors.blue.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Container(
                                  height: 96 * point.resolved / maxValue + (point.resolved > 0 ? 2 : 0),
                                  decoration: BoxDecoration(
                                    color: UrbColors.navy,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _monthAbbreviations[point.month.month - 1],
                              style: UrbText.caption.copyWith(fontSize: 9.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _daysLabel(double? seconds) {
  if (seconds == null) return '—';
  final days = seconds / 86400;
  if (days < 1) return 'menos de 1 dia';
  final value = days >= 10 ? days.round().toString() : formatDecimal(days);
  return '$value ${days < 2 ? 'dia' : 'dias'}';
}
