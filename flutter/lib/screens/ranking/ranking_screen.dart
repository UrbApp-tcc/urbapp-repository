import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../logic/app_rules.dart';
import '../../services/ranking_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Rankings (spec §22): comparativo de cidades e participação de cidadãos,
/// apresentados juntos e com o mesmo peso. Cada prévia leva à lista completa.
/// Não classifica agentes políticos.
class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final _service = RankingService();
  final _city = AppSession.instance.city.value;

  List<CityRankingRow>? _cities;
  List<CitizenRankingEntry>? _citizens;
  ParticipationStanding? _standing;
  bool _citiesFailed = false;
  bool _citizensFailed = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Cada prévia carrega e falha de forma independente.
    await Future.wait([_loadCities(), _loadCitizens()]);
  }

  Future<void> _loadCities() async {
    try {
      final rows = await _service.fetchCities(indicator: CityIndicator.resolutionRate, limit: 100);
      if (mounted) setState(() => _cities = rows);
    } catch (_) {
      if (mounted) setState(() => _citiesFailed = true);
    }
  }

  Future<void> _loadCitizens() async {
    final city = _city;
    if (city == null) return;
    try {
      final responses = await Future.wait<dynamic>([
        _service.fetchCitizens(city.id, limit: 3),
        _service.fetchStanding(city.id),
      ]);
      if (!mounted) return;
      setState(() {
        _citizens = responses[0] as List<CitizenRankingEntry>;
        _standing = responses[1] as ParticipationStanding?;
      });
    } catch (_) {
      if (mounted) setState(() => _citizensFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cityName = _city?.name ?? 'sua cidade';
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Rankings'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              'Como as cidades resolvem suas ocorrências e quem mais participa em $cityName.',
              style: UrbText.bodySmall,
            ),
            const SizedBox(height: 18),
            _RankingCard(
              title: 'Cidades',
              criterion: 'Taxa de resolução',
              period: RankingPeriod.all,
              action: 'Ver ranking de cidades',
              onAction: () => openCityRanking(context),
              child: _citiesPreview(),
            ),
            const SizedBox(height: 16),
            _RankingCard(
              title: 'Cidadãos em $cityName',
              criterion: 'Pontos de participação',
              period: RankingPeriod.all,
              action: 'Ver ranking de cidadãos',
              onAction: () => openCitizenRanking(context),
              child: _citizensPreview(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _citiesPreview() {
    final rows = _cities;
    if (_citiesFailed) return _note('Não foi possível carregar o comparativo agora.');
    if (rows == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: UrbLoadingView());
    final top = rows.where((row) => row.qualified).take(3).toList();
    final mine = rows.where((row) => row.cityId == _city?.id).firstOrNull;
    final mineInTop = mine != null && top.any((row) => row.cityId == mine.cityId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (top.isEmpty) _note('Ainda não há cidades com amostra suficiente para classificação.'),
        for (var index = 0; index < top.length; index++)
          _CityRow(
            row: top[index],
            byTime: false,
            mine: top[index].cityId == _city?.id,
            last: index == top.length - 1,
            fraction: top[index].resolutionRate / 100,
          ),
        if (mine != null && !mineInTop)
          _MineStrip(
            title: 'Sua cidade · ${mine.cityName}',
            detail: mine.qualified
                ? '${mine.position}º lugar em taxa de resolução'
                : 'Sem posição: ${mine.eligible} de ${mine.minimumRequired} ocorrências mínimas',
            value: '${formatDecimal(mine.resolutionRate)}%',
          ),
      ],
    );
  }

  Widget _citizensPreview() {
    if (_city == null) return _note('Escolha uma cidade para ver a participação.');
    final entries = _citizens;
    if (_citizensFailed) return _note('Não foi possível carregar a participação agora.');
    if (entries == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: UrbLoadingView());
    final standing = _standing;
    final position = standing?.eligible == true ? standing?.position : null;
    final mineInTop = entries.any((entry) => entry.profileId == _userId);
    final leader = entries.isEmpty ? 0 : entries.first.points;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty) _note('Os primeiros moradores a participar aparecerão aqui.'),
        for (var index = 0; index < entries.length; index++)
          _RankingRow(
            entry: entries[index],
            mine: entries[index].profileId == _userId,
            last: index == entries.length - 1,
            fraction: leader == 0 ? 0 : entries[index].points / leader,
          ),
        if (!mineInTop && position != null)
          _MineStrip(
            title: 'Você',
            detail: '$positionº de ${plural(standing!.participants, 'cidadão', 'cidadãos')}',
            value: '${formatCount(standing.points)} pts',
          )
        else if (!mineInTop && standing != null && standing.eligible && position == null && entries.isNotEmpty)
          _note('Você ainda não aparece neste ranking.'),
      ],
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Text(text, style: UrbText.caption.copyWith(color: UrbColors.textSecondary)),
  );
}

// -----------------------------------------------------------------------------
// Peças visuais compartilhadas
// -----------------------------------------------------------------------------

/// Card de prévia da página Rankings: mesma superfície dos cards de ocorrência,
/// cabeçalho com critério e período, e a ação como rodapé.
class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.criterion,
    required this.period,
    required this.action,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String criterion;
  final RankingPeriod period;
  final String action;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: UrbText.h3),
                      const SizedBox(height: 2),
                      Text(criterion, style: UrbText.caption.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(7)),
                  child: Text(
                    period.label,
                    style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          child,
          const SizedBox(height: 4),
          Semantics(
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: onAction,
            child: InkWell(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: UrbColors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        action,
                        style: UrbText.label.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.blue),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Superfície branca dos cards do UrbApp (borda e sombra dos cards de ocorrência).
class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UrbRadius.lg),
        border: Border.all(color: const Color(0xFFDFE4E5)),
        boxShadow: const [BoxShadow(color: Color(0x0A122234), blurRadius: 30, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Situação do usuário (ou da cidade dele) quando ela fica fora da prévia.
class _MineStrip extends StatelessWidget {
  const _MineStrip({required this.title, required this.detail, required this.value});

  final String title;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: UrbColors.blueSoft,
        borderRadius: BorderRadius.circular(UrbRadius.sm),
        border: Border.all(color: UrbColors.blueSoftBorder),
      ),
      child: Row(
        children: [
          const _LimeDot(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(detail, style: UrbText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: UrbText.title.copyWith(color: UrbColors.blue)),
        ],
      ),
    );
  }
}

/// Ponto lime com halo, o mesmo marcador de "agora" usado na Home.
class _LimeDot extends StatelessWidget {
  const _LimeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: UrbColors.lime,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: UrbColors.lime.withValues(alpha: 0.35), spreadRadius: 3)],
      ),
    );
  }
}

/// Barra proporcional ao valor da linha (taxa, tempo ou pontos).
class _ValueBar extends StatelessWidget {
  const _ValueBar({required this.fraction, this.color = UrbColors.blue, this.track = const Color(0x174657EF)});

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final value = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value == 0 ? 0 : value.clamp(0.03, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Posição: as três primeiras ganham selo (lime no 1º, azul no 2º e 3º).
class _PositionMark extends StatelessWidget {
  const _PositionMark(this.position);

  final int? position;

  @override
  Widget build(BuildContext context) {
    final value = position;
    if (value == null || value > 3) {
      return SizedBox(
        width: 30,
        child: Text(
          value == null ? '–' : '$value',
          textAlign: TextAlign.center,
          style: UrbText.label.copyWith(fontWeight: FontWeight.w800, color: UrbColors.muted),
        ),
      );
    }
    final first = value == 1;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: first ? UrbColors.lime : UrbColors.blueSoft,
        borderRadius: BorderRadius.circular(9),
        border: first ? null : Border.all(color: UrbColors.blueSoftBorder),
      ),
      child: Text(
        '$value',
        style: UrbText.label.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: first ? UrbColors.navy : UrbColors.blue,
        ),
      ),
    );
  }
}

/// Destaque azul do topo das listas completas: a situação da sua cidade ou a
/// sua posição. É o único bloco de cor forte da tela.
class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.label,
    required this.value,
    required this.valueCaption,
    required this.side,
    required this.sideCaption,
    required this.semanticsLabel,
    this.progress,
    this.footnote,
  });

  final String label;
  final String value;
  final String valueCaption;
  final String side;
  final String sideCaption;
  final String semanticsLabel;
  final double? progress;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.78);
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(color: UrbColors.blue, borderRadius: BorderRadius.circular(UrbRadius.lg)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _LimeDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: UrbText.hero.copyWith(fontSize: 50, letterSpacing: -2.6, height: 1, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(valueCaption, style: UrbText.caption.copyWith(fontSize: 12, color: soft)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(side, style: UrbText.h1.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(sideCaption, style: UrbText.caption.copyWith(fontSize: 12, color: soft)),
                  ],
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 16),
              _ValueBar(fraction: progress!, color: UrbColors.lime, track: Colors.white.withValues(alpha: 0.22)),
            ],
            if (footnote != null) ...[
              SizedBox(height: progress != null ? 8 : 14),
              Text(footnote!, style: UrbText.caption.copyWith(fontSize: 12, color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Linha base das listas: posição, conteúdo com barra proporcional e valor.
class _RankLine extends StatelessWidget {
  const _RankLine({
    required this.position,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.mine,
    required this.last,
    required this.semanticsLabel,
    required this.onTap,
    this.valueSuffix,
    this.valueMuted = false,
    this.leading,
    this.fraction,
    this.barColor = UrbColors.blue,
  });

  final int? position;
  final String title;
  final InlineSpan subtitle;
  final String value;
  final String? valueSuffix;
  final bool valueMuted;
  final Widget? leading;
  final double? fraction;
  final Color barColor;
  final bool mine;
  final bool last;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: mine ? UrbColors.blueSoft : null,
            border: last ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: mine ? UrbColors.lime : Colors.transparent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 12, 16, 13),
                    child: Row(
                      children: [
                        _PositionMark(position),
                        const SizedBox(width: 12),
                        if (leading != null) ...[leading!, const SizedBox(width: 10)],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value,
                                    style: UrbText.title.copyWith(color: valueMuted ? UrbColors.muted : UrbColors.navy),
                                  ),
                                  if (valueSuffix != null) Text(valueSuffix!, style: UrbText.caption),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text.rich(subtitle, style: UrbText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (fraction != null) ...[
                                const SizedBox(height: 8),
                                _ValueBar(fraction: fraction!, color: barColor),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cidades: taxa de resolução e mediana do tempo de resolução
// -----------------------------------------------------------------------------

String _cityDays(double? seconds) {
  if (seconds == null) return '—';
  final days = seconds / 86400;
  if (days < 1) return '< 1 dia';
  final value = days >= 10 ? days.round().toString() : formatDecimal(days);
  return '$value ${days < 2 ? 'dia' : 'dias'}';
}

/// Comparativo completo de cidades: taxa e tempo de resolução (regras no backend).
class CityRankingScreen extends StatefulWidget {
  const CityRankingScreen({super.key});

  @override
  State<CityRankingScreen> createState() => _CityRankingScreenState();
}

class _CityRankingScreenState extends State<CityRankingScreen> {
  static const _pageSize = 50;

  final _service = RankingService();
  CityIndicator _indicator = CityIndicator.resolutionRate;
  RankingPeriod _period = RankingPeriod.all;
  List<CityRankingRow>? _rows;
  CityRankingSettings? _settings;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _service
        .fetchCitySettings()
        .then((value) {
          if (mounted) setState(() => _settings = value);
        })
        .catchError((_) {});
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final rows = await _service.fetchCities(indicator: _indicator, period: _period, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _hasMore = rows.length == _pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _loadMore() async {
    final current = _rows;
    if (current == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _service.fetchCities(
        indicator: _indicator,
        period: _period,
        limit: _pageSize,
        offset: current.length,
      );
      if (!mounted) return;
      setState(() {
        _rows = [...current, ...next];
        _hasMore = next.length == _pageSize;
      });
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showInfo() {
    final settings = _settings;
    showUrbSheet<void>(
      context: context,
      eyebrow: 'Ranking de cidades',
      title: 'Como este indicador é calculado?',
      intro:
          'Os indicadores usam só ocorrências únicas de competência municipal. Relatos adicionais, '
          'duplicatas absorvidas e ocorrências invalidadas pela moderação não contam.',
      builder: (_) => _CityRankingInfo(settings: settings),
    );
  }

  /// Fração da barra de cada linha. No tempo, proporcional à maior mediana.
  double? _fraction(CityRankingRow row, double maxSeconds) {
    if (!row.qualified) {
      // Sem posição: progresso até a amostra mínima.
      final sample = _indicator == CityIndicator.resolutionTime ? row.resolved : row.eligible;
      return row.minimumRequired == 0 ? null : sample / row.minimumRequired;
    }
    if (_indicator == CityIndicator.resolutionRate) return row.resolutionRate / 100;
    final seconds = row.medianResolutionSeconds;
    return seconds == null || maxSeconds == 0 ? null : seconds / maxSeconds;
  }

  Widget _mySpotlight(CityRankingRow row, int rankedCount) {
    final byTime = _indicator == CityIndicator.resolutionTime;
    final value = byTime ? _cityDays(row.medianResolutionSeconds) : '${formatDecimal(row.resolutionRate)}%';
    final sample = byTime ? row.resolved : row.eligible;
    final sampleNoun = byTime ? 'resoluções' : 'ocorrências';
    final position = row.qualified ? '${row.position}º' : '—';
    final sideCaption = !row.qualified
        ? 'sem posição'
        : (_hasMore ? 'na classificação' : 'de ${plural(rankedCount, 'cidade', 'cidades')}');
    final footnote = row.qualified
        ? (byTime
              ? 'Mediana de ${plural(row.resolved, 'resolução confirmada', 'resoluções confirmadas')}.'
              : '${formatCount(row.resolved)} de ${plural(row.eligible, 'ocorrência resolvida', 'ocorrências resolvidas')}.')
        : '$sample de ${row.minimumRequired} $sampleNoun necessárias para entrar na classificação.';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _Spotlight(
        label: 'Sua cidade · ${row.cityName} · ${row.stateCode}',
        value: value,
        valueCaption: '${_indicator.label.toLowerCase()} · ${_period.label}',
        side: position,
        sideCaption: sideCaption,
        progress: row.qualified || row.minimumRequired == 0 ? null : sample / row.minimumRequired,
        footnote: footnote,
        semanticsLabel:
            'Sua cidade, ${row.cityName}: $value de ${_indicator.label.toLowerCase()}. '
            '${row.qualified ? 'Posição $position.' : 'Sem posição.'} $footnote',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final ranked = rows?.where((row) => row.qualified).toList() ?? const <CityRankingRow>[];
    final unranked = rows?.where((row) => !row.qualified).toList() ?? const <CityRankingRow>[];
    final myCityId = AppSession.instance.city.value?.id;
    final mine = rows?.where((row) => row.cityId == myCityId).firstOrNull;
    final byTime = _indicator == CityIndicator.resolutionTime;
    final maxSeconds = ranked.fold<double>(0, (max, row) {
      final seconds = row.medianResolutionSeconds ?? 0;
      return seconds > max ? seconds : max;
    });
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Ranking de cidades'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(_indicator.label, style: UrbText.h1),
            const SizedBox(height: 6),
            Text(
              'Indicadores objetivos das ocorrências municipais, sem score composto. '
              'Não avalia governos nem agentes políticos.',
              style: UrbText.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final indicator in CityIndicator.values)
                  UrbChip(
                    label: indicator.label,
                    selected: indicator == _indicator,
                    onTap: () {
                      if (indicator == _indicator) return;
                      setState(() => _indicator = indicator);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final period in const [RankingPeriod.all, RankingPeriod.month]) ...[
                  UrbChip(
                    label: period.label,
                    selected: period == _period,
                    onTap: () {
                      if (period == _period) return;
                      setState(() => _period = period);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                UrbTextButton('Como é calculado?', color: UrbColors.muted, onPressed: _showInfo),
              ],
            ),
            if (mine != null) _mySpotlight(mine, ranked.length),
            const SizedBox(height: 18),
            if (_error != null)
              UrbErrorState(message: _error!, onRetry: _load)
            else if (rows == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: UrbLoadingView())
            else if (rows.isEmpty)
              UrbEmptyState(
                title: 'Sem ocorrências no período',
                message: _period == RankingPeriod.month
                    ? 'Nenhuma cidade registrou ocorrências municipais neste mês ainda.'
                    : 'Ainda não há ocorrências municipais registradas.',
              )
            else ...[
              Text('Classificação', style: UrbText.h3),
              const SizedBox(height: 2),
              Text(
                byTime
                    ? 'Mediana do tempo entre o registro e a resolução confirmada. Menor é melhor.'
                    : (_period == RankingPeriod.month
                          ? 'Das ocorrências criadas este mês, quantas já foram resolvidas.'
                          : 'Das ocorrências criadas desde o início, quantas foram resolvidas.'),
                style: UrbText.caption.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (ranked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('Nenhuma cidade atingiu a amostra mínima neste período.', style: UrbText.caption),
                )
              else
                _CardSurface(
                  child: Column(
                    children: [
                      for (var index = 0; index < ranked.length; index++)
                        _CityRow(
                          row: ranked[index],
                          byTime: byTime,
                          mine: ranked[index].cityId == myCityId,
                          last: index == ranked.length - 1,
                          fraction: _fraction(ranked[index], maxSeconds),
                        ),
                    ],
                  ),
                ),
              if (unranked.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Ainda sem posição', style: UrbText.h3),
                const SizedBox(height: 2),
                Text(
                  'Cidades abaixo da amostra mínima. A barra mostra quanto falta para entrar.',
                  style: UrbText.caption.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 10),
                _CardSurface(
                  child: Column(
                    children: [
                      for (var index = 0; index < unranked.length; index++)
                        _CityRow(
                          row: unranked[index],
                          byTime: byTime,
                          mine: unranked[index].cityId == myCityId,
                          last: index == unranked.length - 1,
                          fraction: _fraction(unranked[index], maxSeconds),
                        ),
                    ],
                  ),
                ),
              ],
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: _loadingMore
                        ? const Padding(padding: EdgeInsets.all(8), child: UrbPulsingDots())
                        : UrbTextButton('Mostrar mais cidades', onPressed: _loadMore),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.row, required this.byTime, required this.mine, required this.last, this.fraction});

  final CityRankingRow row;
  final bool byTime;
  final bool mine;
  final bool last;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final value = !row.qualified
        ? '—'
        : (byTime ? _cityDays(row.medianResolutionSeconds) : '${formatDecimal(row.resolutionRate)}%');
    final detail = byTime
        ? (row.qualified
              ? 'mediana · ${plural(row.resolved, 'resolução', 'resoluções')}'
              : '${row.resolved} de ${row.minimumRequired} resoluções mínimas')
        : (row.qualified
              ? '${formatCount(row.resolved)} de ${plural(row.eligible, 'ocorrência resolvida', 'ocorrências resolvidas')}'
              : '${row.eligible} de ${row.minimumRequired} ocorrências mínimas');
    return _RankLine(
      position: row.position,
      title: '${row.cityName} · ${row.stateCode}',
      subtitle: TextSpan(
        children: [
          if (mine)
            TextSpan(
              text: 'Sua cidade · ',
              style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
            ),
          TextSpan(text: detail),
        ],
      ),
      value: value,
      valueMuted: !row.qualified,
      fraction: fraction,
      barColor: row.qualified ? UrbColors.blue : UrbColors.slate,
      mine: mine,
      last: last,
      semanticsLabel: [
        if (row.position != null) '${row.position}º',
        row.cityName,
        if (row.qualified) value else 'dados insuficientes para classificação',
      ].join(', '),
      onTap: () => openCityTransparency(context, row.cityId),
    );
  }
}

class _CityRankingInfo extends StatelessWidget {
  const _CityRankingInfo({required this.settings});

  final CityRankingSettings? settings;

  @override
  Widget build(BuildContext context) {
    Widget rule(String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(detail, style: UrbText.caption),
        ],
      ),
    );
    final minRate = settings?.minOccurrencesForRate;
    final minTime = settings?.minResolvedForTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rule(
          'Taxa de resolução',
          'Ocorrências resolvidas ÷ ocorrências registradas no período. Só conta como resolvida a ocorrência '
              'que está hoje em "Resolvido", após a validação da comunidade.',
        ),
        rule(
          'Tempo de resolução',
          'Mediana do tempo entre o registro e a última confirmação de resolução. Ocorrências reabertas '
              'ficam fora até serem resolvidas de novo.',
        ),
        rule(
          'Este mês e Geral',
          '"Este mês" considera as ocorrências criadas desde o início do mês, no fuso da cidade. '
              '"Geral" considera todas as ocorrências desde o primeiro registro.',
        ),
        rule(
          'Amostra mínima',
          minRate == null || minTime == null
              ? 'Cidades com poucas ocorrências aparecem sem posição até atingirem a amostra mínima.'
              : 'Para receber posição, a cidade precisa de pelo menos $minRate ocorrências no período (taxa) '
                    'ou $minTime resoluções (tempo).',
        ),
        Text(
          'Empates: na taxa, vence quem tem mais ocorrências; no tempo, quem tem mais resoluções na amostra.',
          style: UrbText.caption,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Cidadãos
// -----------------------------------------------------------------------------

/// Ranking completo de cidadãos por pontos atribuídos à cidade (spec §39);
/// regras no backend.
class CitizenRankingScreen extends StatefulWidget {
  const CitizenRankingScreen({super.key});

  @override
  State<CitizenRankingScreen> createState() => _CitizenRankingScreenState();
}

class _CitizenRankingScreenState extends State<CitizenRankingScreen> {
  final _service = RankingService();
  final _scroll = ScrollController();
  final _myRowKey = GlobalKey();
  final _spotlightKey = GlobalKey();

  /// Geral é o padrão e vem primeiro.
  static const _periods = [RankingPeriod.all, RankingPeriod.month];

  late CityOption? _city = AppSession.instance.city.value;
  RankingPeriod _period = RankingPeriod.all;
  static const _pageSize = 50;

  List<CitizenRankingEntry>? _entries;
  ParticipationStanding? _standing;
  String? _error;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _myPositionVisible = true;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkMyRow);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final city = _city;
    if (city == null) return;
    setState(() {
      _entries = null;
      _error = null;
    });
    try {
      final responses = await Future.wait<dynamic>([
        _service.fetchCitizens(city.id, period: _period, limit: _pageSize),
        _service.fetchStanding(city.id, period: _period),
      ]);
      if (!mounted) return;
      final entries = responses[0] as List<CitizenRankingEntry>;
      setState(() {
        _entries = entries;
        _hasMore = entries.length == _pageSize;
        _standing = responses[1] as ParticipationStanding?;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkMyRow());
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _loadMore() async {
    final city = _city;
    final current = _entries;
    if (city == null || current == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _service.fetchCitizens(city.id, period: _period, limit: _pageSize, offset: current.length);
      if (!mounted) return;
      setState(() {
        _entries = [...current, ...next];
        _hasMore = next.length == _pageSize;
      });
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Carrega as páginas até a linha do usuário e rola até ela.
  Future<void> _goToMyRow(int position) async {
    while (mounted && (_entries?.length ?? 0) < position && _hasMore) {
      await _loadMore();
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _myRowKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 0.5, duration: const Duration(milliseconds: 300));
      }
    });
  }

  bool _isOnScreen(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final viewBox = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || viewBox == null) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: viewBox).dy;
    return top + box.size.height > 0 && top < viewBox.size.height - 70;
  }

  /// A indicação compacta só aparece quando nem o destaque nem a própria linha
  /// estão na tela.
  void _checkMyRow() {
    if (!mounted) return;
    final visible = _isOnScreen(_myRowKey) || _isOnScreen(_spotlightKey);
    if (visible != _myPositionVisible) setState(() => _myPositionVisible = visible);
  }

  Future<void> _pickCity() async {
    final picked = await showCityPicker(context, cities: AppSession.instance.cities, selected: _city);
    if (picked == null || picked.id == _city?.id) return;
    setState(() => _city = picked);
    _load();
  }

  void _showPointsInfo() {
    showUrbSheet<void>(
      context: context,
      eyebrow: 'Ranking de cidadãos',
      title: 'Como funcionam os pontos?',
      intro: 'Os pontos reconhecem contribuições úteis para a cidade. Cada ação conta uma vez por ocorrência.',
      builder: (_) => const _PointsInfo(),
    );
  }

  Widget _mySpotlight(ParticipationStanding standing, int position) {
    final cityName = _city?.name ?? 'sua cidade';
    final toNext = standing.pointsToNext;
    final leads = position == 1;
    final footnote = leads
        ? 'Você lidera a participação em $cityName.'
        : (toNext != null ? 'Faltam ${plural(toNext, 'ponto', 'pontos')} para subir de posição.' : null);
    final participants = plural(standing.participants, 'cidadão', 'cidadãos');
    return Padding(
      key: _spotlightKey,
      padding: const EdgeInsets.only(top: 16),
      child: _Spotlight(
        label: 'Sua posição em $cityName',
        value: '$positionº',
        valueCaption: _period == RankingPeriod.month ? 'de $participants · este mês' : 'de $participants',
        side: formatCount(standing.points),
        sideCaption: 'pontos',
        progress: leads || toNext == null ? null : standing.points / (standing.points + toNext),
        footnote: footnote,
        semanticsLabel:
            'Sua posição em $cityName: $positionº de $participants, '
            '${plural(standing.points, 'ponto', 'pontos')}. ${footnote ?? ''}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final standing = _standing;
    final myPosition = standing?.eligible == true ? standing?.position : null;
    final showMyPosition = myPosition != null && entries != null && !_myPositionVisible;
    final leader = entries == null || entries.isEmpty ? 0 : entries.first.points;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Ranking de cidadãos'),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: 'Cidade: ${_city?.name ?? 'sua cidade'}. Trocar cidade',
                    excludeSemantics: true,
                    onTap: _pickCity,
                    child: InkWell(
                      onTap: _pickCity,
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(_city?.name ?? 'Sua cidade', style: UrbText.h1)),
                          const SizedBox(width: 6),
                          const UrbIcon(UrbIcons.chevronDown, size: 20, color: UrbColors.navy),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Cidadãos que mais participam da comunidade', style: UrbText.bodySmall),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final period in _periods) ...[
                      UrbChip(
                        label: period.label,
                        selected: period == _period,
                        onTap: () {
                          if (period == _period) return;
                          setState(() => _period = period);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                if (myPosition != null && entries != null) _mySpotlight(standing!, myPosition),
                if (standing != null && !standing.eligible) ...[
                  const SizedBox(height: 12),
                  Text(
                    standing.reason == 'institutional'
                        ? 'Perfis institucionais não participam do ranking de cidadãos.'
                        : 'Seu perfil está privado, por isso não aparece no ranking.',
                    style: UrbText.caption,
                  ),
                ],
                const SizedBox(height: 18),
                if (_error != null)
                  UrbErrorState(message: _error!, onRetry: _load)
                else if (entries == null)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: UrbLoadingView())
                else if (entries.isEmpty)
                  UrbEmptyState(
                    title: _period == RankingPeriod.month ? 'Ninguém pontuou este mês' : 'Ainda sem participação',
                    message: 'Quando os moradores participarem, eles aparecerão aqui.',
                  )
                else ...[
                  Text('Classificação', style: UrbText.h3),
                  const SizedBox(height: 2),
                  Text(
                    plural(standing?.participants ?? entries.length, 'cidadão no ranking', 'cidadãos no ranking'),
                    style: UrbText.caption.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  _CardSurface(
                    child: Column(
                      children: [
                        for (var index = 0; index < entries.length; index++)
                          _RankingRow(
                            key: entries[index].profileId == _userId ? _myRowKey : null,
                            entry: entries[index],
                            mine: entries[index].profileId == _userId,
                            last: index == entries.length - 1,
                            fraction: leader == 0 ? 0 : entries[index].points / leader,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: _loadingMore
                          ? const Padding(padding: EdgeInsets.all(8), child: UrbPulsingDots())
                          : UrbTextButton('Mostrar mais participantes', onPressed: _loadMore),
                    ),
                  ),
                if (entries != null &&
                    entries.isNotEmpty &&
                    standing != null &&
                    standing.eligible &&
                    myPosition == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _period == RankingPeriod.month
                          ? 'Você ainda não pontuou este mês.'
                          : 'Você ainda não aparece neste ranking.',
                      textAlign: TextAlign.center,
                      style: UrbText.caption,
                    ),
                  ),
                const SizedBox(height: 20),
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Como funcionam os pontos?',
                    excludeSemantics: true,
                    onTap: _showPointsInfo,
                    child: InkWell(
                      onTap: _showPointsInfo,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          'Como funcionam os pontos?',
                          style: UrbText.caption.copyWith(
                            decoration: TextDecoration.underline,
                            decorationColor: UrbColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showMyPosition)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: Center(
                child: _MyPositionPill(
                  position: myPosition,
                  points: standing!.points,
                  onTap: () => _goToMyRow(myPosition),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({super.key, required this.entry, required this.mine, required this.last, this.fraction});

  final CitizenRankingEntry entry;
  final bool mine;
  final bool last;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return _RankLine(
      position: entry.position,
      leading: UrbAvatar(
        name: entry.name,
        imageUrl: entry.avatarUrl,
        size: 36,
        rounded: false,
        gradientSeed: entry.position,
      ),
      title: entry.name,
      subtitle: TextSpan(
        children: [
          if (mine)
            TextSpan(
              text: 'Você · ',
              style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
            ),
          TextSpan(text: 'Nível ${entry.level}'),
        ],
      ),
      value: formatCount(entry.points),
      valueSuffix: ' pts',
      fraction: fraction,
      mine: mine,
      last: last,
      semanticsLabel: '${entry.position}º, ${entry.name}${mine ? ', você' : ''}, ${entry.points} pontos',
      onTap: () => openUserProfile(context, entry.profileId),
    );
  }
}

/// Indicação compacta da posição quando a linha do usuário está fora da tela.
class _MyPositionPill extends StatelessWidget {
  const _MyPositionPill({required this.position, required this.points, this.onTap});

  final int position;
  final int points;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: 'Você está em $positionº, ${plural(points, 'ponto', 'pontos')}',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: UrbColors.line)),
        elevation: 2,
        shadowColor: const Color(0x2211233D),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: UrbColors.lime, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  'Você está em #$position',
                  style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800),
                ),
                Text('  ·  ${formatCount(points)} pts', style: UrbText.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Regras vigentes no backend (spec §39); valores únicos em `app_rules.dart`.
class _PointsInfo extends StatelessWidget {
  const _PointsInfo();

  @override
  Widget build(BuildContext context) {
    Widget rule(String points, String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              points,
              style: UrbText.title.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                Text(detail, style: UrbText.caption),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rule(
          '+$pointsPerPost',
          'Relato válido',
          'Vale o mesmo ao iniciar uma ocorrência ou ao adicionar seu relato a uma ocorrência existente.',
        ),
        rule(
          '+$pointsPerResolvedPost',
          'Ocorrência resolvida',
          'Para todos que contribuíram com relatos, após a validação da comunidade.',
        ),
        rule('+$pointsPerSupportReceived', 'Apoio recebido', 'Na ocorrência que você iniciou, uma vez por cidadão.'),
        rule(
          '+$pointsPerCommentReceived',
          'Comentário recebido',
          'Na ocorrência que você iniciou, uma vez por cidadão.',
        ),
        Text('Pontos obtidos com conteúdo inválido podem ser revertidos pela moderação.', style: UrbText.caption),
      ],
    );
  }
}
