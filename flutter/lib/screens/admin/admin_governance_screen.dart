import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Governança técnica (spec §3.5): parâmetros de validação, troca de gestão,
/// categorias, responsabilidade categoria → órgão, duplicidades e competência.
/// Nenhuma operação permite editar indicadores diretamente.
class AdminGovernanceScreen extends StatefulWidget {
  const AdminGovernanceScreen({super.key});

  @override
  State<AdminGovernanceScreen> createState() => _AdminGovernanceScreenState();
}

class _AdminGovernanceScreenState extends State<AdminGovernanceScreen> {
  final _service = InstitutionalService();
  final _occurrences = OccurrenceService();

  final _confirmations = TextEditingController();
  final _rejections = TextEditingController();
  final _radius = TextEditingController();
  final _duration = TextEditingController();
  final _cooldown = TextEditingController();
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
  List<CategoryOption> _categories = const [];
  List<AgencyChoice> _agencies = const [];
  CityOption? _city;
  int? _categoryId;
  int? _agencyId;
  String _jurisdiction = 'state';
  DateTime _administrationStart = DateTime.now();
  DateTime _administrationEnd = DateTime(DateTime.now().year + 4, 12, 31);
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _confirmations, _rejections, _radius, _duration, _cooldown, _administrationName, _mayorName,
      _responsibilityReason, _categoryName, _categorySlug, _categoryDescription, _primaryOccurrence,
      _duplicateOccurrence, _mergeReason, _jurisdictionOccurrence, _externalResponsible, _jurisdictionReason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([_occurrences.fetchCities(), _occurrences.fetchCategories()]);
      if (!mounted) return;
      setState(() {
        _cities = results[0] as List<CityOption>;
        _categories = results[1] as List<CategoryOption>;
        _categoryId = _categories.firstOrNull?.id;
      });
      final first = _cities.firstOrNull;
      if (first != null) await _selectCity(first);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectCity(CityOption city) async {
    setState(() => _city = city);
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchAgenciesForCity(city.id),
        _service.fetchValidationSettings(city.id),
      ]);
      final settings = results[1] as ValidationSettingsInfo;
      if (!mounted) return;
      setState(() {
        _agencies = results[0] as List<AgencyChoice>;
        _agencyId = _agencies.firstOrNull?.id;
        _confirmations.text = '${settings.confirmations}';
        _rejections.text = '${settings.rejections}';
        _radius.text = formatDecimal(settings.radiusKm, digits: settings.radiusKm % 1 == 0 ? 0 : 1).replaceAll(',', '.');
        _duration.text = '${settings.durationHours}';
        _cooldown.text = '${settings.cooldownHours}';
      });
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _run(Future<void> Function() operation, String success) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await operation();
      if (mounted) showUrbToast(context, success);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _int(TextEditingController controller, String label) {
    final value = int.tryParse(controller.text.trim());
    if (value == null) throw Exception('$label inválido.');
    return value;
  }

  Widget _card({required String title, required String subtitle, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: UrbColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: UrbText.title),
          const SizedBox(height: 4),
          Text(subtitle, style: UrbText.caption.copyWith(fontSize: 12)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _number(TextEditingController controller, String label, {bool decimal = false}) => UrbTextField(
        label: label,
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      );

  Widget _dropdown<T>({required String label, required T? value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: UrbText.label),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(initialValue: value, isExpanded: true, items: items, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Governança'),
      body: _loading
          ? const UrbLoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(13)),
                  child: Text(
                    'Todas as alterações ficam auditadas e não reescrevem ciclos, indicadores ou históricos anteriores. '
                    'Indicadores públicos não podem ser editados manualmente.',
                    style: UrbText.bodySmall.copyWith(color: UrbColors.navy),
                  ),
                ),
                CitySelectorButton(
                  city: _city,
                  label: 'Cidade configurada',
                  onTap: () async {
                    final picked = await showCityPicker(context, cities: _cities, selected: _city);
                    if (picked != null) _selectCity(picked);
                  },
                ),
                const SizedBox(height: 14),
                _card(
                  title: 'Validação comunitária',
                  subtitle: 'Novos valores valem apenas para ciclos abertos depois da mudança.',
                  children: [
                    Row(children: [
                      Expanded(child: _number(_confirmations, 'Confirmações')),
                      const SizedBox(width: 10),
                      Expanded(child: _number(_rejections, 'Rejeições')),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _number(_radius, 'Raio (km)', decimal: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _number(_duration, 'Prazo (h)')),
                      const SizedBox(width: 10),
                      Expanded(child: _number(_cooldown, 'Espera (h)')),
                    ]),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Salvar parâmetros',
                      expand: true,
                      loading: _saving,
                      onPressed: _city == null
                          ? null
                          : () => _run(
                                () => _service.configureValidation(
                                  cityId: _city!.id,
                                  confirmations: _int(_confirmations, 'Confirmações'),
                                  rejections: _int(_rejections, 'Rejeições'),
                                  radiusKm: double.tryParse(_radius.text.replaceAll(',', '.')) ?? (throw Exception('Raio inválido.')),
                                  durationHours: _int(_duration, 'Prazo'),
                                  cooldownHours: _int(_cooldown, 'Espera'),
                                ),
                                'Parâmetros de validação atualizados.',
                              ),
                    ),
                  ],
                ),
                _card(
                  title: 'Mudança de gestão municipal',
                  subtitle: 'Ocorrências ativas passam a ser herdadas pela nova gestão; o histórico da anterior é preservado.',
                  children: [
                    UrbTextField(label: 'Nome da gestão', hint: 'Ex.: Gestão 2029–2032', controller: _administrationName),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Prefeito(a)', controller: _mayorName),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: UrbButton(
                          label: 'Início ${formatDate(_administrationStart)}',
                          tone: UrbButtonTone.outline,
                          onPressed: () async {
                            final picked = await showDatePicker(
                                context: context, initialDate: _administrationStart, firstDate: DateTime(2000), lastDate: DateTime(2100));
                            if (picked != null) setState(() => _administrationStart = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: UrbButton(
                          label: 'Fim ${formatDate(_administrationEnd)}',
                          tone: UrbButtonTone.outline,
                          onPressed: () async {
                            final picked = await showDatePicker(
                                context: context, initialDate: _administrationEnd, firstDate: DateTime(2000), lastDate: DateTime(2100));
                            if (picked != null) setState(() => _administrationEnd = picked);
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Registrar nova gestão',
                      expand: true,
                      loading: _saving,
                      onPressed: _city == null
                          ? null
                          : () async {
                              final confirmed = await UrbConfirmSheet.show(
                                context,
                                title: 'Registrar nova gestão?',
                                message: 'As ocorrências ativas de ${_city!.name} passarão a ser herdadas pela nova gestão.',
                                confirmLabel: 'Registrar',
                              );
                              if (!confirmed) return;
                              await _run(
                                () => _service.rolloverMunicipalAdministration(
                                  cityId: _city!.id,
                                  name: _administrationName.text,
                                  mayorName: _mayorName.text,
                                  startsOn: _administrationStart,
                                  endsOn: _administrationEnd,
                                ),
                                'Nova gestão registrada.',
                              );
                            },
                    ),
                  ],
                ),
                _card(
                  title: 'Categoria → órgão responsável',
                  subtitle: 'Define o órgão associado automaticamente às novas ocorrências desta cidade.',
                  children: [
                    _dropdown<int>(
                      label: 'Categoria',
                      value: _categoryId,
                      items: [for (final category in _categories) DropdownMenuItem(value: category.id, child: Text(category.name))],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<int>(
                      label: 'Órgão',
                      value: _agencyId,
                      items: [for (final agency in _agencies) DropdownMenuItem(value: agency.id, child: Text(agency.name))],
                      onChanged: (value) => setState(() => _agencyId = value),
                    ),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Motivo da alteração', controller: _responsibilityReason),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Salvar responsabilidade',
                      expand: true,
                      loading: _saving,
                      onPressed: _city == null || _categoryId == null || _agencyId == null
                          ? null
                          : () => _run(
                                () => _service.configureAgencyResponsibility(
                                  cityId: _city!.id,
                                  categoryId: _categoryId!,
                                  agencyId: _agencyId!,
                                  reason: _responsibilityReason.text,
                                ),
                                'Responsabilidade atualizada.',
                              ),
                    ),
                  ],
                ),
                _card(
                  title: 'Categorias',
                  subtitle: 'Crie categorias e defina se exigem foto recente para informar resolução.',
                  children: [
                    UrbTextField(label: 'Nome', controller: _categoryName),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Identificador (slug)', hint: 'ex.: iluminacao-publica', controller: _categorySlug),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Descrição', controller: _categoryDescription),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Criar categoria',
                      expand: true,
                      loading: _saving,
                      onPressed: () => _run(() async {
                        await _service.upsertProblemCategory(
                          name: _categoryName.text,
                          slug: _categorySlug.text,
                          description: _categoryDescription.text,
                        );
                        final categories = await _occurrences.fetchCategories();
                        if (mounted) setState(() => _categories = categories);
                      }, 'Categoria salva.'),
                    ),
                    const SizedBox(height: 14),
                    for (final category in _categories)
                      UrbSettingsRow(
                        label: category.name,
                        subtitle: 'Exigir foto para informar resolução',
                        trailing: UrbSwitch(
                          value: category.requiresResolutionEvidence,
                          onChanged: (value) => _run(() async {
                            await _service.setCategoryResolutionEvidence(categoryId: category.id, required: value);
                            final categories = await _occurrences.fetchCategories();
                            if (mounted) setState(() => _categories = categories);
                          }, 'Regra da categoria atualizada.'),
                        ),
                      ),
                  ],
                ),
                _card(
                  title: 'Consolidar duplicidade',
                  subtitle: 'Os relatos da duplicada passam para a principal sem perder autoria; a ocorrência conta uma vez.',
                  children: [
                    Row(children: [
                      Expanded(
                        child: UrbTextField(
                          label: 'Nº principal',
                          controller: _primaryOccurrence,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: UrbTextField(
                          label: 'Nº duplicada',
                          controller: _duplicateOccurrence,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Justificativa', controller: _mergeReason),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Consolidar ocorrências',
                      expand: true,
                      loading: _saving,
                      onPressed: () => _run(
                        () => _service.mergeOccurrences(
                          primaryOccurrenceId: _int(_primaryOccurrence, 'Ocorrência principal'),
                          duplicateOccurrenceId: _int(_duplicateOccurrence, 'Ocorrência duplicada'),
                          reason: _mergeReason.text,
                        ),
                        'Ocorrências consolidadas.',
                      ),
                    ),
                  ],
                ),
                _card(
                  title: 'Competência',
                  subtitle: 'Casos de outra esfera, concessionária ou propriedade privada não distorcem indicadores municipais.',
                  children: [
                    UrbTextField(
                      label: 'Nº da ocorrência',
                      controller: _jurisdictionOccurrence,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _dropdown<String>(
                      label: 'Competência',
                      value: _jurisdiction,
                      items: [
                        for (final code in const ['municipal', 'state', 'federal', 'concessionaire', 'private', 'unknown'])
                          DropdownMenuItem(value: code, child: Text(jurisdictionLabel(code))),
                      ],
                      onChanged: (value) => setState(() => _jurisdiction = value ?? 'state'),
                    ),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Responsável externo (se conhecido)', controller: _externalResponsible),
                    const SizedBox(height: 12),
                    UrbTextField(label: 'Justificativa', controller: _jurisdictionReason),
                    const SizedBox(height: 14),
                    UrbButton(
                      label: 'Atualizar competência',
                      expand: true,
                      loading: _saving,
                      onPressed: () => _run(
                        () => _service.setOccurrenceJurisdiction(
                          occurrenceId: _int(_jurisdictionOccurrence, 'Ocorrência'),
                          jurisdiction: _jurisdiction,
                          externalResponsible: _externalResponsible.text,
                          reason: _jurisdictionReason.text,
                        ),
                        'Competência atualizada.',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const UrbIcon(UrbIcons.lock, size: 13, color: UrbColors.muted),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Acesso restrito à administração do UrbApp.', style: UrbText.caption)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Use o número exibido no link da ocorrência (urbapp://occurrences/<nº>).', style: UrbText.caption),
              ],
            ),
    );
  }
}
