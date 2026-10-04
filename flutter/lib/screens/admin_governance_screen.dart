import 'package:flutter/material.dart';

import '../services/agency_service.dart';
import '../services/city_service.dart';
import '../services/institutional_service.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class AdminGovernanceScreen extends StatefulWidget {
  const AdminGovernanceScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AdminGovernanceScreen()),
    );
  }

  @override
  State<AdminGovernanceScreen> createState() => _AdminGovernanceScreenState();
}

class _AdminGovernanceScreenState extends State<AdminGovernanceScreen> {
  final _service = InstitutionalService();
  final _cityService = CityService();
  final _postService = PostService();
  final _agencyService = AgencyService();

  final _confirmations = TextEditingController(text: '3');
  final _rejections = TextEditingController(text: '2');
  final _radius = TextEditingController(text: '5');
  final _duration = TextEditingController(text: '72');
  final _cooldown = TextEditingController(text: '24');
  final _administrationName = TextEditingController();
  final _mayorName = TextEditingController();
  final _responsibilityReason = TextEditingController();
  final _categoryName = TextEditingController();
  final _categorySlug = TextEditingController();
  final _categoryDescription = TextEditingController();
  final _primaryOccurrence = TextEditingController();
  final _duplicateOccurrence = TextEditingController();
  final _mergeReason = TextEditingController();
  final _jurisdictionOccurrence = TextEditingController();
  final _externalResponsible = TextEditingController();
  final _jurisdictionReason = TextEditingController();

  List<CityOption> _cities = const [];
  List<LookupOption> _categories = const [];
  List<AgencyOption> _agencies = const [];
  int? _cityId;
  int? _categoryId;
  int? _agencyId;
  String _jurisdiction = 'municipal';
  bool _isLoading = true;
  bool _isSaving = false;
  late DateTime _administrationStartsOn;
  late DateTime _administrationEndsOn;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _administrationStartsOn = DateTime(now.year, now.month, now.day);
    _administrationEndsOn = DateTime(now.year + 4, 12, 31);
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _confirmations,
      _rejections,
      _radius,
      _duration,
      _cooldown,
      _administrationName,
      _mayorName,
      _responsibilityReason,
      _categoryName,
      _categorySlug,
      _categoryDescription,
      _primaryOccurrence,
      _duplicateOccurrence,
      _mergeReason,
      _jurisdictionOccurrence,
      _externalResponsible,
      _jurisdictionReason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _cityService.fetchCities(),
        _postService.fetchCategories(),
      ]);
      final cities = results[0] as List<CityOption>;
      final categories = results[1] as List<LookupOption>;
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _categories = categories;
        _cityId = cities.firstOrNull?.id;
        _categoryId = categories.firstOrNull?.id;
      });
      if (_cityId != null) await _selectCity(_cityId!);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAgencies(int cityId) async {
    try {
      final agencies = await _agencyService.fetchAgenciesByCity(cityId);
      if (!mounted) return;
      setState(() {
        _agencies = agencies;
        _agencyId = agencies.firstOrNull?.id;
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadValidationSettings(int cityId) async {
    try {
      final settings = await _service.fetchValidationSettings(cityId);
      if (!mounted || _cityId != cityId) return;
      setState(() {
        _confirmations.text = '${settings.confirmations}';
        _rejections.text = '${settings.rejections}';
        _radius.text = settings.radiusKm.toStringAsFixed(
          settings.radiusKm == settings.radiusKm.roundToDouble() ? 0 : 1,
        );
        _duration.text = '${settings.durationHours}';
        _cooldown.text = '${settings.cooldownHours}';
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _selectCity(int cityId) async {
    if (mounted) setState(() => _cityId = cityId);
    await Future.wait<void>([
      _loadAgencies(cityId),
      _loadValidationSettings(cityId),
    ]);
  }

  Future<void> _run(Future<void> Function() operation, String success) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: AppColors.resolved),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  int _requiredInt(TextEditingController controller, String label) {
    final value = int.tryParse(controller.text.trim());
    if (value == null) throw Exception('$label inválido.');
    return value;
  }

  Future<void> _pickAdministrationDate(bool start) async {
    final current = start ? _administrationStartsOn : _administrationEndsOn;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _administrationStartsOn = selected;
        if (_administrationEndsOn.isBefore(selected)) {
          _administrationEndsOn = DateTime(selected.year + 4, 12, 31);
        }
      } else {
        _administrationEndsOn = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Governança da plataforma')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const _GovernanceNotice(),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Validação comunitária',
                  subtitle:
                      'Novos valores afetam apenas ciclos abertos depois da mudança.',
                  children: [
                    _CityDropdown(
                      cities: _cities,
                      value: _cityId,
                      onChanged: (value) {
                        if (value == null) return;
                        _selectCity(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _confirmations,
                            label: 'Confirmações',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _rejections,
                            label: 'Rejeições',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _radius,
                            label: 'Raio km',
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _duration,
                            label: 'Prazo h',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _cooldown,
                            label: 'Cooldown h',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Salvar parâmetros',
                      onPressed: _cityId == null
                          ? null
                          : () => _run(
                              () => _service.configureValidation(
                                cityId: _cityId!,
                                confirmations: _requiredInt(
                                  _confirmations,
                                  'Confirmações',
                                ),
                                rejections: _requiredInt(
                                  _rejections,
                                  'Rejeições',
                                ),
                                radiusKm:
                                    double.tryParse(_radius.text.trim()) ?? 0,
                                durationHours: _requiredInt(_duration, 'Prazo'),
                                cooldownHours: _requiredInt(
                                  _cooldown,
                                  'Cooldown',
                                ),
                              ),
                              'Parâmetros registrados com histórico.',
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Mudança de gestão municipal',
                  subtitle:
                      'Encerra o período atual, preserva seus indicadores e transfere ocorrências ativas como herdadas.',
                  children: [
                    _CityDropdown(
                      cities: _cities,
                      value: _cityId,
                      onChanged: (value) {
                        if (value != null) _selectCity(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _administrationName,
                      decoration: const InputDecoration(
                        labelText: 'Nome da nova gestão',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mayorName,
                      decoration: const InputDecoration(
                        labelText: 'Prefeito(a) do período',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAdministrationDate(true),
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text(
                              'Início ${_formatDate(_administrationStartsOn)}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAdministrationDate(false),
                            icon: const Icon(Icons.event_busy_outlined),
                            label: Text(
                              'Fim ${_formatDate(_administrationEndsOn)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Registrar nova gestão',
                      onPressed: _cityId == null
                          ? null
                          : () => _run(
                              () => _service.rolloverMunicipalAdministration(
                                cityId: _cityId!,
                                name: _administrationName.text,
                                mayorName: _mayorName.text,
                                startsOn: _administrationStartsOn,
                                endsOn: _administrationEndsOn,
                              ),
                              'Nova gestão registrada; histórico preservado.',
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Categoria → órgão responsável',
                  subtitle:
                      'Define o encaminhamento automático para novos relatos da cidade.',
                  children: [
                    _CityDropdown(
                      cities: _cities,
                      value: _cityId,
                      onChanged: (value) {
                        if (value == null) return;
                        _selectCity(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _categoryId,
                      items: _categories
                          .map(
                            (category) => DropdownMenuItem<int>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _categoryId = value),
                      decoration: const InputDecoration(labelText: 'Categoria'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _agencyId,
                      items: _agencies
                          .map(
                            (agency) => DropdownMenuItem<int>(
                              value: agency.id,
                              child: Text(agency.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _agencyId = value),
                      decoration: const InputDecoration(
                        labelText: 'Órgão responsável',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _responsibilityReason,
                      decoration: const InputDecoration(
                        labelText: 'Motivo da alteração',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Atualizar responsabilidade',
                      onPressed:
                          _cityId == null ||
                              _categoryId == null ||
                              _agencyId == null
                          ? null
                          : () => _run(
                              () => _service.configureAgencyResponsibility(
                                cityId: _cityId!,
                                categoryId: _categoryId!,
                                agencyId: _agencyId!,
                                reason: _responsibilityReason.text,
                              ),
                              'Responsabilidade atualizada.',
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Nova categoria',
                  subtitle: 'Cria uma classificação pública de problema.',
                  children: [
                    TextField(
                      controller: _categoryName,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categorySlug,
                      decoration: const InputDecoration(
                        labelText: 'Identificador (ex.: iluminacao-publica)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categoryDescription,
                      decoration: const InputDecoration(labelText: 'Descrição'),
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Criar categoria',
                      onPressed: () => _run(
                        () => _service.upsertProblemCategory(
                          name: _categoryName.text,
                          slug: _categorySlug.text,
                          description: _categoryDescription.text,
                        ),
                        'Categoria criada.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Consolidar duplicidade',
                  subtitle:
                      'Move os relatos para a ocorrência principal sem apagar autoria ou histórico.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _primaryOccurrence,
                            label: 'ID principal',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _duplicateOccurrence,
                            label: 'ID duplicada',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mergeReason,
                      decoration: const InputDecoration(
                        labelText: 'Justificativa auditável',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Consolidar ocorrências',
                      onPressed: () => _run(
                        () => _service.mergeOccurrences(
                          primaryOccurrenceId: _requiredInt(
                            _primaryOccurrence,
                            'ID principal',
                          ),
                          duplicateOccurrenceId: _requiredInt(
                            _duplicateOccurrence,
                            'ID duplicada',
                          ),
                          reason: _mergeReason.text,
                        ),
                        'Ocorrências consolidadas.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _GovernanceCard(
                  title: 'Corrigir competência',
                  subtitle:
                      'Casos estaduais, federais, privados ou de concessionária não prejudicam indicadores municipais.',
                  children: [
                    _NumberField(
                      controller: _jurisdictionOccurrence,
                      label: 'ID da ocorrência',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _jurisdiction,
                      items:
                          const {
                                'municipal': 'Municipal',
                                'state': 'Estadual',
                                'federal': 'Federal',
                                'concessionaire': 'Concessionária',
                                'private': 'Propriedade privada',
                                'unknown': 'A confirmar',
                              }.entries
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _jurisdiction = value);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Competência',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _externalResponsible,
                      decoration: const InputDecoration(
                        labelText: 'Responsável externo, se conhecido',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _jurisdictionReason,
                      decoration: const InputDecoration(
                        labelText: 'Justificativa auditável',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SaveButton(
                      isSaving: _isSaving,
                      label: 'Salvar competência',
                      onPressed: () => _run(
                        () => _service.setOccurrenceJurisdiction(
                          occurrenceId: _requiredInt(
                            _jurisdictionOccurrence,
                            'ID da ocorrência',
                          ),
                          jurisdiction: _jurisdiction,
                          externalResponsible: _externalResponsible.text,
                          reason: _jurisdictionReason.text,
                        ),
                        'Competência atualizada com histórico.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

class _GovernanceNotice extends StatelessWidget {
  const _GovernanceNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1D99C)),
      ),
      child: const Text(
        'Todas as correções são operações críticas do backend. Elas preservam autoria, histórico e regras temporais e não podem marcar uma ocorrência como resolvida.',
        style: TextStyle(color: Color(0xFF674A0A), height: 1.45),
      ),
    );
  }
}

class _GovernanceCard extends StatelessWidget {
  const _GovernanceCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

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
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _CityDropdown extends StatelessWidget {
  const _CityDropdown({
    required this.cities,
    required this.value,
    required this.onChanged,
  });

  final List<CityOption> cities;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      items: cities
          .map(
            (city) =>
                DropdownMenuItem<int>(value: city.id, child: Text(city.name)),
          )
          .toList(),
      onChanged: onChanged,
      decoration: const InputDecoration(labelText: 'Cidade'),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.isSaving,
    required this.label,
    required this.onPressed,
  });

  final bool isSaving;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isSaving ? null : onPressed,
        child: Text(isSaving ? 'Salvando...' : label),
      ),
    );
  }
}
