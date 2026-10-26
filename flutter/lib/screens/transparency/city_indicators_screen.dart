import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'transparency_kit.dart';

/// Panorama da cidade (spec §33, §44.6): o mesmo número e o mesmo anel do hub,
/// com o detalhe — situação, tempos, categorias, evolução mensal e bairros.
/// Tudo calculado pelo UrbApp; não reinicia com a troca de gestão.
class CityIndicatorsScreen extends StatefulWidget {
  const CityIndicatorsScreen({super.key, required this.cityId, required this.cityName});

  final int cityId;
  final String cityName;

  @override
  State<CityIndicatorsScreen> createState() => _CityIndicatorsScreenState();
}

class _CityIndicatorsScreenState extends State<CityIndicatorsScreen> {
  final _service = TransparencyService();

  CityPanorama? _panorama;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final panorama = await _service.fetchCityPanorama(widget.cityId, detailed: true);
      if (mounted) setState(() => _panorama = panorama);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final panorama = _panorama;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Panorama da cidade'),
      body: _error != null
          ? UrbErrorState(message: _error!, onRetry: _load)
          : panorama == null
          ? const UrbLoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                children: [
                  _headline(panorama),
                  const SizedBox(height: 10),
                  _times(panorama),
                  if (panorama.categories.isNotEmpty) ...[
                    SectionTitle('Por categoria', trailing: plural(panorama.total, 'ocorrência', 'ocorrências')),
                    const SizedBox(height: 6),
                    _Bars(items: panorama.categories),
                  ],
                  if (panorama.monthly.any((point) => point.registered > 0)) ...[
                    SectionTitle('Registros por mês', trailing: 'últimos ${math.min(6, panorama.monthly.length)}'),
                    const SizedBox(height: 6),
                    _Months(points: panorama.monthly.length > 6
                        ? panorama.monthly.sublist(panorama.monthly.length - 6)
                        : panorama.monthly),
                  ],
                  if (panorama.neighborhoods.isNotEmpty) ...[
                    const SectionTitle('Bairros com mais registros'),
                    const SizedBox(height: 6),
                    _Neighborhoods(items: panorama.neighborhoods.take(5).toList()),
                  ],
                  if (panorama.outsideMunicipal > 0) ...[
                    const SizedBox(height: 12),
                    RuleNote(
                      '${plural(panorama.outsideMunicipal, 'ocorrência está', 'ocorrências estão')} fora da '
                      'competência municipal e não ${panorama.outsideMunicipal == 1 ? 'entra' : 'entram'} nestes indicadores.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Provenance.calculated('Tudo nesta página é calculado pelo UrbApp'),
                ],
              ),
            ),
    );
  }

  Widget _headline(CityPanorama panorama) {
    final segments = [
      (panorama.resolved, UrbColors.navy, pluralWord(panorama.resolved, 'resolvida', 'resolvidas')),
      (panorama.inProgress, UrbColors.blue, 'em andamento'),
      (panorama.awaitingValidation, UrbColors.lime, 'aguardando validação'),
      (panorama.open, const Color(0xFFD5DBE1), pluralWord(panorama.open, 'aberta', 'abertas')),
      if (panorama.closed > 0)
        (panorama.closed, const Color(0xFF9AA6B7), pluralWord(panorama.closed, 'encerrada sem resolução', 'encerradas sem resolução')),
    ];
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      semanticsLabel: '${panorama.resolved} de ${panorama.total} ocorrências resolvidas, confirmadas por vizinhos. '
          '${segments.map((segment) => '${segment.$1} ${segment.$3}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TileStat(
                      value: formatCount(panorama.resolved),
                      valueSuffix: ' de ${formatCount(panorama.total)}',
                      valueSize: 50,
                      title: pluralWord(panorama.resolved, 'ocorrência resolvida', 'ocorrências resolvidas'),
                      subtitle: 'confirmadas por vizinhos · ${panorama.cityName}',
                      titleSize: 15,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ResolutionRing(total: panorama.total, resolved: panorama.resolved, active: panorama.inProgress),
            ],
          ),
          const SizedBox(height: 18),
          if (panorama.total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (final segment in segments.where((segment) => segment.$1 > 0)) ...[
                      Expanded(
                        flex: segment.$1,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(color: segment.$2, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final segment in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: segment.$1 == 0 ? Colors.white : segment.$2,
                        borderRadius: BorderRadius.circular(3),
                        border: segment.$1 == 0 ? Border.all(color: const Color(0xFFC9D0D8), width: 1.5) : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${segment.$1} ${segment.$3}',
                      style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF3B4858)),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _times(CityPanorama panorama) {
    final median = panorama.medianResolutionSeconds;
    return TilePair(
      left: StatTile(
        height: 176,
        tone: median == null ? TileTone.white : TileTone.lime,
        glyph: RoundGlyph(
          UrbIcons.clock,
          size: 36,
          background: median == null ? kSoft : UrbColors.navy,
          color: median == null ? kFaint : UrbColors.lime,
        ),
        stat: TileStat(
          tone: median == null ? TileTone.white : TileTone.lime,
          value: shortDays(median),
          valueSize: 32,
          faintValue: median == null,
          title: 'até a resolução',
          subtitle: median == null ? 'Sem resoluções ainda' : 'Mediana das resolvidas',
        ),
      ),
      right: StatTile(
        height: 176,
        glyph: DotsGlyph(colors: [
          for (var index = 0; index < panorama.reopened.clamp(1, 6); index++)
            panorama.reopened == 0 ? UrbColors.line : UrbColors.blue,
        ]),
        stat: TileStat(
          value: formatCount(panorama.reopened),
          faintValue: panorama.reopened == 0,
          title: pluralWord(panorama.reopened, 'reaberta', 'reabertas'),
          subtitle: 'após conclusão rejeitada',
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.items});

  final List<Breakdown> items;

  @override
  Widget build(BuildContext context) {
    final top = items.fold<int>(0, (value, item) => math.max(value, item.total));
    return BentoCard(
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    items[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.label.copyWith(fontWeight: FontWeight.w700, color: UrbColors.ink),
                  ),
                ),
                Text(
                  items[index].resolved > 0
                      ? '${items[index].total} · ${items[index].resolved} ${pluralWord(items[index].resolved, 'resolvida', 'resolvidas')}'
                      : '${items[index].total}',
                  style: UrbText.label.copyWith(fontWeight: FontWeight.w700, color: UrbColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFFEEF1F3)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: top == 0 ? 0 : items[index].total / top,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: UrbColors.navy, borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Months extends StatelessWidget {
  const _Months({required this.points});

  final List<MonthlyPoint> points;

  @override
  Widget build(BuildContext context) {
    final top = points.fold<int>(0, (value, point) => math.max(value, point.registered));
    return BentoCard(
      child: SizedBox(
        height: 112,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < points.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  label: '${monthShort(points[index].month)}: ${points[index].registered} registradas',
                  excludeSemantics: true,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (points[index].registered > 0)
                        Text(
                          '${points[index].registered}',
                          style: UrbText.meta.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: UrbColors.ink),
                        ),
                      const SizedBox(height: 4),
                      Container(
                        height: top == 0 || points[index].registered == 0 ? 6 : 6 + 58 * points[index].registered / top,
                        decoration: BoxDecoration(
                          color: points[index].registered == 0
                              ? const Color(0xFFEEF1F3)
                              : (index == points.length - 1 ? UrbColors.navy : UrbColors.blue),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        monthShort(points[index].month),
                        style: UrbText.meta.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: index == points.length - 1 ? UrbColors.ink : UrbColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Neighborhoods extends StatelessWidget {
  const _Neighborhoods({required this.items});

  final List<Breakdown> items;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: index == items.length - 1 ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: UrbText.title.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: UrbColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[index].label, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            plural(items[index].total, 'registrada', 'registradas'),
                            if (items[index].resolved > 0)
                              plural(items[index].resolved, 'resolvida', 'resolvidas'),
                          ].join(' · '),
                          style: tileSubtitleStyle(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
