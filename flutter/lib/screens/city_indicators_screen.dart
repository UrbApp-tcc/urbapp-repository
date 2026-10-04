import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../services/indicator_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class CityIndicatorsScreen extends StatefulWidget {
  const CityIndicatorsScreen({super.key, this.initialCityId});

  final int? initialCityId;

  static Future<void> open(BuildContext context, {int? initialCityId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CityIndicatorsScreen(initialCityId: initialCityId),
      ),
    );
  }

  @override
  State<CityIndicatorsScreen> createState() => _CityIndicatorsScreenState();
}

class _CityIndicatorsScreenState extends State<CityIndicatorsScreen> {
  final _cityService = CityService();
  final _indicatorService = IndicatorService();

  List<CityOption> _cities = const [];
  int? _selectedCityId;
  CityIndicatorBundle? _bundle;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final cities = await _cityService.fetchCities();
      final preferred =
          widget.initialCityId ?? await _cityService.fetchCurrentUserCityId();
      final selected = cities.any((city) => city.id == preferred)
          ? preferred
          : cities.firstOrNull?.id;
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _selectedCityId = selected;
      });
      if (selected != null) await _loadMetrics(selected);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMetrics(int cityId) async {
    setState(() {
      _selectedCityId = cityId;
      _isLoading = true;
    });
    try {
      final bundle = await _indicatorService.fetchCityIndicators(cityId);
      if (!mounted) return;
      setState(() => _bundle = bundle);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _bundle?.metrics;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Indicadores públicos')),
      body: RefreshIndicator(
        onRefresh: () async {
          final cityId = _selectedCityId;
          if (cityId != null) await _loadMetrics(cityId);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedCityId,
              decoration: const InputDecoration(
                labelText: 'Cidade',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: _cities
                  .map(
                    (city) => DropdownMenuItem<int>(
                      value: city.id,
                      child: Text(city.name),
                    ),
                  )
                  .toList(),
              onChanged: (cityId) {
                if (cityId != null) _loadMetrics(cityId);
              },
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (metrics == null)
              const _EmptyIndicators()
            else ...[
              _ResolutionHero(metrics: metrics),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  _MetricCard(
                    label: 'Abertas',
                    value: '${metrics.openOccurrences}',
                    icon: Icons.fiber_new_outlined,
                    color: const Color(0xFFDC6B37),
                  ),
                  _MetricCard(
                    label: 'Em andamento',
                    value: '${metrics.activeOccurrences}',
                    icon: Icons.construction_outlined,
                    color: const Color(0xFF315E9E),
                  ),
                  _MetricCard(
                    label: 'Em validação',
                    value: '${metrics.awaitingValidationOccurrences}',
                    icon: Icons.fact_check_outlined,
                    color: const Color(0xFF7654A7),
                  ),
                  _MetricCard(
                    label: 'Fora da competência',
                    value: '${metrics.outsideMunicipalOccurrences}',
                    icon: Icons.call_split_outlined,
                    color: const Color(0xFF667085),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _BreakdownSection(
                title: 'Categorias mais frequentes',
                entries: _bundle!.categories,
              ),
              const SizedBox(height: 16),
              _BreakdownSection(
                title: 'Regiões com maior demanda',
                entries: _bundle!.neighborhoods,
              ),
              const SizedBox(height: 16),
              _MonthlySection(entries: _bundle!.monthly),
              const SizedBox(height: 18),
              const _MethodologyNotice(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResolutionHero extends StatelessWidget {
  const _ResolutionHero({required this.metrics});

  final PublicCityMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17222D), Color(0xFF294762)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metrics.cityName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${metrics.resolutionRate.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          const Text(
            'taxa de resolução confirmada pela comunidade',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Text(
            '${metrics.resolvedOccurrences} resolvidas de ${metrics.totalOccurrences} ocorrências municipais',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (metrics.medianResolutionSeconds != null) ...[
            const SizedBox(height: 6),
            Text(
              'Tempo mediano: ${_formatDuration(metrics.medianResolutionSeconds!)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDuration(double seconds) {
    final days = Duration(seconds: seconds.round()).inDays;
    if (days >= 1) return '$days ${days == 1 ? 'dia' : 'dias'}';
    final hours = Duration(seconds: seconds.round()).inHours;
    return '$hours ${hours == 1 ? 'hora' : 'horas'}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({required this.title, required this.entries});

  final String title;
  final List<IndicatorBreakdown> entries;

  @override
  Widget build(BuildContext context) {
    final maximum = entries.isEmpty
        ? 1
        : entries.map((entry) => entry.total).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Text(
              'Ainda não há dados suficientes.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text('${entry.total}'),
                      ],
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: entry.total / maximum,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: const Color(0xFFE9EDF1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthlySection extends StatelessWidget {
  const _MonthlySection({required this.entries});

  final List<MonthlyIndicator> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evolução mensal',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            const Text(
              'Ainda não há dados suficientes.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ...entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${entry.month.month.toString().padLeft(2, '0')}/${entry.month.year}',
                ),
                subtitle: Text('${entry.resolved} resolvidas'),
                trailing: Text(
                  '${entry.registered} registradas',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodologyNotice extends StatelessWidget {
  const _MethodologyNotice();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Metodologia: cada ocorrência urbana conta uma única vez, mesmo com vários relatos ou vereadores acompanhando. Encerramentos administrativos e itens fora da competência municipal não contam como resolução.',
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.5,
      ),
    );
  }
}

class _EmptyIndicators extends StatelessWidget {
  const _EmptyIndicators();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 46, color: AppColors.textHint),
          SizedBox(height: 12),
          Text('Nenhum indicador disponível para esta cidade.'),
        ],
      ),
    );
  }
}
