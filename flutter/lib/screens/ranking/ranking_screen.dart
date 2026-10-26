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
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
          children: [
            _citiesTile(),
            const SizedBox(height: 12),
            _citizensTile(cityName),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Gestões, órgãos e vereadores não entram em ranking.',
                style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: UrbColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloco lime: as três primeiras cidades e a sua, quando fica de fora.
  Widget _citiesTile() {
    final rows = _cities;
    final top = rows?.where((row) => row.qualified).take(3).toList() ?? const <CityRankingRow>[];
    final mine = rows?.where((row) => row.cityId == _city?.id).firstOrNull;
    final mineInTop = mine != null && top.any((row) => row.cityId == mine.cityId);
    final Widget content;
    if (_citiesFailed) {
      content = _note('Não foi possível carregar o comparativo agora.');
    } else if (rows == null) {
      content = const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: UrbLoadingView());
    } else {
      content = Column(
        children: [
          if (top.isEmpty) _note('Ainda não há cidades com amostra suficiente para classificação.'),
          for (final row in top) _CityPreviewLine(row: row, mine: row.cityId == _city?.id),
          if (mine != null && !mineInTop) _CityPreviewLine(row: mine, mine: true),
        ],
      );
    }
    return _BentoBlock(
      lime: true,
      title: 'Cidades',
      criterion: 'por taxa de resolução confirmada',
      glyph: const _Bars(),
      action: 'Ver ranking de cidades',
      onAction: () => openCityRanking(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: content,
      ),
    );
  }

  /// Bloco branco: a sua posição em destaque; sem posição, os três primeiros.
  Widget _citizensTile(String cityName) {
    final entries = _citizens;
    final standing = _standing;
    final position = standing?.eligible == true ? standing?.position : null;
    final Widget content;
    if (_city == null) {
      content = _note('Escolha uma cidade para ver a participação.');
    } else if (_citizensFailed) {
      content = _note('Não foi possível carregar a participação agora.');
    } else if (entries == null) {
      content = const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: UrbLoadingView());
    } else if (position != null) {
      content = Row(
        children: [
          Text('$positionº', style: _bigNumber(44)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('sua posição', style: UrbText.label.copyWith(fontWeight: FontWeight.w800, color: UrbColors.ink)),
                Text(
                  'entre ${plural(standing!.participants, 'cidadão', 'cidadãos')} · ${formatCount(standing.points)} pts',
                  style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: UrbColors.muted),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (entries.isEmpty) {
      content = _note('Os primeiros moradores a participar aparecerão aqui.');
    } else {
      content = Column(
        children: [
          for (final entry in entries) _CitizenPreviewLine(entry: entry, mine: entry.profileId == _userId),
        ],
      );
    }
    return _BentoBlock(
      lime: false,
      title: 'Cidadãos em $cityName',
      criterion: 'por pontos de participação: registros, validações e apoios',
      action: 'Ver ranking de cidadãos',
      onAction: () => openCitizenRanking(context),
      child: content,
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: UrbText.caption.copyWith(fontSize: 12, color: UrbColors.textSecondary)),
  );
}

TextStyle _bigNumber(double size, {Color color = UrbColors.ink}) => UrbText.display.copyWith(
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.05 * size,
  height: 1.05,
  color: color,
);

/// Bloco de prévia da página Rankings: título forte, critério, conteúdo e a
/// ação como botão no rodapé (navy sobre o lime, contornado sobre o branco).
class _BentoBlock extends StatelessWidget {
  const _BentoBlock({
    required this.lime,
    required this.title,
    required this.criterion,
    required this.action,
    required this.onAction,
    required this.child,
    this.glyph,
  });

  final bool lime;
  final String title;
  final String criterion;
  final String action;
  final VoidCallback onAction;
  final Widget child;
  final Widget? glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: lime ? UrbColors.lime : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: lime ? null : Border.all(color: UrbColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: UrbText.h2.copyWith(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -1, color: UrbColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      criterion,
                      style: UrbText.meta.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: lime ? const Color(0xFF3E4C2A) : UrbColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (glyph != null) ...[const SizedBox(width: 12), glyph!],
            ],
          ),
          const SizedBox(height: 16),
          child,
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: onAction,
            child: Material(
              color: lime ? UrbColors.navy : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: lime ? BorderSide.none : const BorderSide(color: UrbColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onAction,
                child: SizedBox(
                  height: 46,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action,
                            style: UrbText.button.copyWith(
                              fontWeight: FontWeight.w800,
                              color: lime ? Colors.white : UrbColors.navy,
                            ),
                          ),
                        ),
                        UrbIcon(UrbIcons.chevron, size: 16, color: lime ? UrbColors.lime : UrbColors.navy, strokeWidth: 2.6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Três barras sólidas navy (o mesmo glifo do bloco de Rankings no hub).
class _Bars extends StatelessWidget {
  const _Bars();

  @override
  Widget build(BuildContext context) {
    Widget bar(double height) => Container(
      width: 12,
      height: height,
      decoration: BoxDecoration(color: UrbColors.navy, borderRadius: BorderRadius.circular(4)),
    );
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [bar(22), const SizedBox(width: 4), bar(36), const SizedBox(width: 4), bar(14)],
      ),
    );
  }
}

class _CityPreviewLine extends StatelessWidget {
  const _CityPreviewLine({required this.row, required this.mine});

  final CityRankingRow row;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final position = row.qualified && row.position != null ? '${row.position}º' : '–';
    return InkWell(
      onTap: () => openCityTransparency(context, row.cityId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                position,
                style: UrbText.title.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: mine ? UrbColors.blue : UrbColors.muted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: row.cityName,
                      children: [
                        if (mine) const TextSpan(text: ' · sua cidade', style: TextStyle(color: UrbColors.blue)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, color: UrbColors.ink),
                  ),
                  Text(
                    row.qualified
                        ? plural(row.eligible, 'ocorrência', 'ocorrências')
                        : 'Sem posição: ${row.eligible} de ${row.minimumRequired} mínimas',
                    style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: UrbColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${formatDecimal(row.resolutionRate, digits: 0)}%', style: _bigNumber(16)),
          ],
        ),
      ),
    );
  }
}

class _CitizenPreviewLine extends StatelessWidget {
  const _CitizenPreviewLine({required this.entry, required this.mine});

  final CitizenRankingEntry entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openUserProfile(context, entry.profileId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${entry.position}º',
                style: UrbText.title.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: UrbColors.muted),
              ),
            ),
            UrbAvatar(name: entry.name, imageUrl: entry.avatarUrl, size: 30, rounded: false, gradientSeed: entry.position),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mine ? 'Você' : entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, color: UrbColors.ink),
              ),
            ),
            Text('${formatCount(entry.points)} pts', style: UrbText.label.copyWith(fontWeight: FontWeight.w800, color: UrbColors.navy)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Peças visuais compartilhadas
// -----------------------------------------------------------------------------

/// Situação do usuário (ou da cidade dele) quando ela fica fora da prévia.
class _MineStrip extends StatelessWidget {
  const _MineStrip({
    required this.title,
    required this.detail,
    required this.value,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 6),
  });

  final String title;
  final String detail;
  final String value;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
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
  const _ValueBar({required this.fraction, this.color = UrbColors.blue});

  final double fraction;
  final Color color;

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
            const ColoredBox(color: Color(0x174657EF)),
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

/// Grupo branco das listas completas: um só bloco, com fios finos entre as linhas.
class _ListGroup extends StatelessWidget {
  const _ListGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UrbRadius.lg),
        border: Border.all(color: UrbColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
                    padding: const EdgeInsets.fromLTRB(11, 11, 16, 11),
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
  bool _showUnranked = false;

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
          'São indicadores objetivos das ocorrências, sem score composto: não avaliam governos nem agentes '
          'políticos. Usam só ocorrências únicas de competência municipal; relatos adicionais, duplicatas '
          'absorvidas e ocorrências invalidadas pela moderação não contam.',
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

  Widget _myStrip(CityRankingRow row, int rankedCount) {
    final byTime = _indicator == CityIndicator.resolutionTime;
    final value = byTime ? _cityDays(row.medianResolutionSeconds) : '${formatDecimal(row.resolutionRate)}%';
    final sample = byTime ? row.resolved : row.eligible;
    final noun = byTime ? 'resoluções' : 'ocorrências';
    final detail = row.qualified
        ? '${row.position}º ${_hasMore ? 'na classificação' : 'de ${plural(rankedCount, 'cidade', 'cidades')}'}'
        : 'Sem posição · $sample de ${row.minimumRequired} $noun para entrar';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _MineStrip(
        margin: EdgeInsets.zero,
        title: 'Sua cidade · ${row.cityName}',
        detail: detail,
        value: value,
      ),
    );
  }

  Widget _unrankedToggle(int count) {
    final label = '${plural(count, 'cidade', 'cidades')} ainda sem amostra mínima';
    return Semantics(
      button: true,
      expanded: _showUnranked,
      label: label,
      excludeSemantics: true,
      onTap: () => setState(() => _showUnranked = !_showUnranked),
      child: InkWell(
        onTap: () => setState(() => _showUnranked = !_showUnranked),
        borderRadius: BorderRadius.circular(UrbRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: UrbText.label.copyWith(color: UrbColors.textSecondary))),
              AnimatedRotation(
                turns: _showUnranked ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const UrbIcon(UrbIcons.chevronDown, size: 18, color: UrbColors.muted),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
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
            const SizedBox(height: 8),
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
            if (mine != null) _myStrip(mine, ranked.length),
            const SizedBox(height: 16),
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
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  '${byTime ? 'Mediana do registro à resolução · menor é melhor' : 'Ocorrências resolvidas entre as criadas'}. '
                  'Indicador objetivo: não avalia governos nem agentes políticos.',
                  style: UrbText.caption.copyWith(fontSize: 12),
                ),
              ),
              if (ranked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('Nenhuma cidade atingiu a amostra mínima neste período.', style: UrbText.caption),
                )
              else
                _ListGroup(
                  children: [
                    for (var index = 0; index < ranked.length; index++)
                      _CityRow(
                        row: ranked[index],
                        byTime: byTime,
                        mine: ranked[index].cityId == myCityId,
                        last: index == ranked.length - 1,
                      ),
                  ],
                ),
              if (unranked.isNotEmpty) ...[
                const SizedBox(height: 10),
                _unrankedToggle(unranked.length),
                if (_showUnranked) ...[
                  const SizedBox(height: 4),
                  _ListGroup(
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
                ],
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

  Widget _myStrip(ParticipationStanding standing, int position) {
    final toNext = standing.pointsToNext;
    final participants = plural(standing.participants, 'cidadão', 'cidadãos');
    final extra = position == 1
        ? ' · você lidera'
        : (toNext != null ? ' · faltam ${plural(toNext, 'ponto', 'pontos')} para subir' : '');
    return Padding(
      key: _spotlightKey,
      padding: const EdgeInsets.only(top: 12),
      child: _MineStrip(
        margin: EdgeInsets.zero,
        title: 'Você · $positionº lugar',
        detail: 'de $participants$extra',
        value: '${formatCount(standing.points)} pts',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final standing = _standing;
    final myPosition = standing?.eligible == true ? standing?.position : null;
    final showMyPosition = myPosition != null && entries != null && !_myPositionVisible;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Ranking de cidadãos'),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
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
                          Flexible(child: Text(_city?.name ?? 'Sua cidade', style: UrbText.h3)),
                          const SizedBox(width: 6),
                          const UrbIcon(UrbIcons.chevronDown, size: 18, color: UrbColors.navy),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entries == null || entries.isEmpty
                      ? 'Pontos de participação'
                      : 'Pontos de participação · ${plural(standing?.participants ?? entries.length, 'cidadão', 'cidadãos')}',
                  style: UrbText.caption.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 12),
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
                    const Spacer(),
                    UrbTextButton('Como funcionam?', color: UrbColors.muted, onPressed: _showPointsInfo),
                  ],
                ),
                if (myPosition != null && entries != null) _myStrip(standing!, myPosition),
                if (standing != null && !standing.eligible) ...[
                  const SizedBox(height: 12),
                  Text(
                    standing.reason == 'institutional'
                        ? 'Perfis institucionais não participam do ranking de cidadãos.'
                        : 'Seu perfil está privado, por isso não aparece no ranking.',
                    style: UrbText.caption,
                  ),
                ],
                const SizedBox(height: 16),
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
                  // Pódio com os três primeiros; a lista segue a partir do 4º.
                  if (entries.length >= 3) ...[
                    _Podium(entries: entries.take(3).toList(), userId: _userId, myKey: _myRowKey),
                    const SizedBox(height: 14),
                  ],
                  if (entries.length != 3)
                    _ListGroup(
                      children: [
                        for (var index = entries.length >= 3 ? 3 : 0; index < entries.length; index++)
                          _RankingRow(
                            key: entries[index].profileId == _userId ? _myRowKey : null,
                            entry: entries[index],
                            mine: entries[index].profileId == _userId,
                            last: index == entries.length - 1,
                          ),
                      ],
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

/// Pódio dos três primeiros: o 1º ao centro, mais alto e em lime.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.userId, required this.myKey});

  final List<CitizenRankingEntry> entries;
  final String? userId;
  final GlobalKey myKey;

  @override
  Widget build(BuildContext context) {
    // Ordem visual: 2º, 1º, 3º.
    final order = [entries[1], entries[0], entries[2]];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < order.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _PodiumSpot(
              key: order[index].profileId == userId ? myKey : null,
              entry: order[index],
              mine: order[index].profileId == userId,
            ),
          ),
        ],
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({super.key, required this.entry, required this.mine});

  final CitizenRankingEntry entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final first = entry.position == 1;
    final height = switch (entry.position) {
      1 => 84.0,
      2 => 62.0,
      _ => 46.0,
    };
    return Semantics(
      button: true,
      label: '${entry.position}º, ${entry.name}${mine ? ', você' : ''}, ${entry.points} pontos',
      excludeSemantics: true,
      onTap: () => openUserProfile(context, entry.profileId),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openUserProfile(context, entry.profileId),
        child: Column(
          children: [
            UrbAvatar(
              name: entry.name,
              imageUrl: entry.avatarUrl,
              size: first ? 52 : 44,
              rounded: false,
              gradientSeed: entry.position,
            ),
            const SizedBox(height: 6),
            Text(
              mine ? 'Você' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: UrbColors.ink),
            ),
            Text(
              '${formatCount(entry.points)} pts',
              style: UrbText.meta.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: UrbColors.muted),
            ),
            const SizedBox(height: 8),
            Container(
              height: height,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: first ? UrbColors.lime : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14), bottom: Radius.circular(6)),
                border: first ? null : Border.all(color: mine ? UrbColors.blue : UrbColors.line),
              ),
              child: Text(
                '${entry.position}',
                style: UrbText.h2.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: UrbColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({super.key, required this.entry, required this.mine, required this.last});

  final CitizenRankingEntry entry;
  final bool mine;
  final bool last;

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
