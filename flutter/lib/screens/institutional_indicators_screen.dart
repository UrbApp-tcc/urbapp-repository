import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../services/institutional_indicator_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class InstitutionalIndicatorsScreen extends StatefulWidget {
  const InstitutionalIndicatorsScreen({super.key, this.initialCityId});

  final int? initialCityId;

  static Future<void> open(BuildContext context, {int? initialCityId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            InstitutionalIndicatorsScreen(initialCityId: initialCityId),
      ),
    );
  }

  @override
  State<InstitutionalIndicatorsScreen> createState() =>
      _InstitutionalIndicatorsScreenState();
}

class _InstitutionalIndicatorsScreenState
    extends State<InstitutionalIndicatorsScreen> {
  final _cityService = CityService();
  final _service = InstitutionalIndicatorService();

  List<CityOption> _cities = const [];
  int? _selectedCityId;
  InstitutionalIndicatorBundle? _bundle;
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
      if (selected != null) await _load(selected);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _load(int cityId) async {
    setState(() {
      _selectedCityId = cityId;
      _isLoading = true;
    });
    try {
      final bundle = await _service.fetchForCity(cityId);
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
    final bundle = _bundle;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Indicadores institucionais')),
      body: RefreshIndicator(
        onRefresh: () async {
          final cityId = _selectedCityId;
          if (cityId != null) await _load(cityId);
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
                      child: Text('${city.name} · ${city.stateAbbreviation}'),
                    ),
                  )
                  .toList(),
              onChanged: (cityId) {
                if (cityId != null) _load(cityId);
              },
            ),
            const SizedBox(height: 16),
            const _MethodCard(),
            if (_isLoading) ...[
              const SizedBox(height: 48),
              const Center(child: CircularProgressIndicator()),
            ] else if (bundle != null) ...[
              const SizedBox(height: 24),
              _SectionTitle(
                icon: Icons.account_balance_outlined,
                title: 'Gestões municipais',
                subtitle:
                    'Cada período administrativo possui métricas próprias.',
              ),
              const SizedBox(height: 12),
              if (bundle.administrations.isEmpty)
                const _EmptyCard('Nenhuma gestão cadastrada para esta cidade.')
              else
                ...bundle.administrations.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _AdministrationCard(item: item),
                  ),
                ),
              const SizedBox(height: 14),
              _SectionTitle(
                icon: Icons.apartment_outlined,
                title: 'Órgãos municipais',
                subtitle:
                    'Associações automáticas existem mesmo sem perfil reivindicado.',
              ),
              const SizedBox(height: 12),
              if (bundle.agencies.isEmpty)
                const _EmptyCard('Nenhum órgão cadastrado para esta cidade.')
              else
                ...bundle.agencies.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _AgencyCard(item: item),
                  ),
                ),
              const SizedBox(height: 14),
              _SectionTitle(
                icon: Icons.how_to_vote_outlined,
                title: 'Vereadores',
                subtitle:
                    'Atuação registrada no UrbApp, sem atribuir autoria pela solução.',
              ),
              const SizedBox(height: 12),
              if (bundle.councilors.isEmpty)
                const _EmptyCard(
                  'Nenhum perfil de vereador verificado nesta cidade.',
                )
              else
                ...bundle.councilors.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _CouncilorCard(item: item),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17222D), Color(0xFF37536B)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dados objetivos e rastreáveis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'O UrbApp separa dados calculados automaticamente de ações oficiais. Acompanhar uma demanda não significa ter causado sua resolução.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdministrationCard extends StatelessWidget {
  const _AdministrationCard({required this.item});

  final AdministrationIndicator item;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      title: item.name,
      subtitle: [
        if (item.mayorName?.trim().isNotEmpty == true) item.mayorName!,
        '${_date(item.startsOn)} — ${item.endsOn == null ? 'atual' : _date(item.endsOn!)}',
      ].join(' · '),
      badge: item.isPlaceholder
          ? 'Cadastro automático'
          : item.isVerified
          ? 'Gestão verificada'
          : 'Gestão cadastrada',
      badgeColor: item.isVerified ? AppColors.resolved : AppColors.pending,
      calculated: [
        _Metric('Registradas', item.registered),
        _Metric('Herdadas', item.inherited),
        _Metric('Ativas', item.active),
        _Metric('Resolvidas no período', item.resolved),
        _Metric('Deixadas pendentes', item.leftPending),
      ],
      official: [
        _Metric('Com manifestação', item.manifested),
        _Metric('Priorizadas', item.prioritized),
        _Metric('Encaminhadas', item.forwarded),
        _Metric('Com previsão', item.forecasted),
        _Metric('Conclusões informadas', item.conclusions),
        _Metric('Conclusões confirmadas', item.confirmedConclusions),
        _Metric('Conclusões rejeitadas', item.rejectedConclusions),
        _Metric.text(
          '1ª manifestação',
          _duration(item.averageFirstResponseSeconds),
        ),
        _Metric.text('Até conclusão', _duration(item.averageConclusionSeconds)),
      ],
    );
  }
}

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({required this.item});

  final AgencyIndicator item;

  @override
  Widget build(BuildContext context) {
    final status = switch (item.profileStatus) {
      'participant' => ('Participante', AppColors.resolved),
      'verified' => ('Verificado', AppColors.primary),
      _ => ('Não reivindicado', AppColors.pending),
    };
    return _MetricCard(
      title: item.name,
      subtitle:
          '${item.categoriesCount} categorias · ${item.neighborhoodsCount} regiões com demanda',
      badge: status.$1,
      badgeColor: status.$2,
      calculated: [
        _Metric('Associadas', item.assigned),
        _Metric('Abertas/reabertas', item.open),
        _Metric('Em andamento', item.inProgress),
        _Metric('Em validação', item.awaitingValidation),
        _Metric('Resolvidas', item.resolved),
        _Metric.text(
          'Tempo mediano sob responsabilidade',
          _duration(item.medianResponsibilitySeconds),
        ),
      ],
      official: [
        _Metric('Ações oficiais', item.officialActions),
        _Metric('Demandas respondidas', item.officiallyAnswered),
        _Metric.text(
          'Percentual respondido',
          '${item.officialResponsePercentage.toStringAsFixed(1)}%',
        ),
        _Metric('Conclusões informadas', item.conclusions),
        _Metric('Confirmadas', item.confirmedConclusions),
        _Metric('Rejeitadas', item.rejectedConclusions),
        _Metric.text(
          'Tempo até 1ª resposta',
          _duration(item.averageFirstResponseSeconds),
        ),
      ],
    );
  }
}

class _CouncilorCard extends StatelessWidget {
  const _CouncilorCard({required this.item});

  final CouncilorIndicator item;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      title: item.name,
      subtitle: item.party?.trim().isNotEmpty == true
          ? item.party!
          : 'Partido não informado',
      badge: item.profileStatus == 'participant'
          ? 'Participante'
          : 'Verificado',
      badgeColor: AppColors.primary,
      calculated: [
        _Metric('Demandas acompanhadas', item.followed),
        _Metric('Ainda abertas', item.openDemands),
        _Metric(
          'Acompanhadas que chegaram à resolução',
          item.reachedResolution,
        ),
        _Metric('Encerradas sem resolução', item.endedWithoutResolution),
        _Metric.text(
          'Tempo médio de acompanhamento',
          _duration(item.averageFollowupSeconds),
        ),
      ],
      official: [
        _Metric('Ações registradas', item.actions),
        _Metric('Encaminhamentos/solicitações', item.forwardingActions),
        _Metric('Cobranças', item.chargeActions),
        _Metric('Ofícios', item.officialLetters),
        _Metric('Aguardando retorno', item.awaitingResponse),
      ],
      officialLabel: 'Atuação pública registrada',
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.calculated,
    required this.official,
    this.officialLabel = 'Informações oficiais registradas',
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final List<_Metric> calculated;
  final List<_Metric> official;
  final String officialLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _MetricGroupLabel(
            icon: Icons.calculate_outlined,
            text: 'Calculado pelo UrbApp',
          ),
          const SizedBox(height: 8),
          _MetricWrap(items: calculated),
          const SizedBox(height: 16),
          _MetricGroupLabel(icon: Icons.verified_outlined, text: officialLabel),
          const SizedBox(height: 8),
          _MetricWrap(items: official),
        ],
      ),
    );
  }
}

class _MetricGroupLabel extends StatelessWidget {
  const _MetricGroupLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textHint),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.items});

  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Container(
              constraints: const BoxConstraints(minWidth: 100),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _Metric {
  _Metric(this.label, int value) : value = '$value';
  const _Metric.text(this.label, this.value);

  final String label;
  final String value;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _duration(double? seconds) {
  if (seconds == null) return 'Sem dado';
  final duration = Duration(seconds: seconds.round());
  if (duration.inDays > 0) return '${duration.inDays} d';
  if (duration.inHours > 0) return '${duration.inHours} h';
  return '${duration.inMinutes} min';
}
