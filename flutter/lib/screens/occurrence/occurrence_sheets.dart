import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Campo de foto opcional/obrigatória das sheets (estilo "evidence-upload").
class EvidencePickerField extends StatelessWidget {
  const EvidencePickerField({
    super.key,
    required this.file,
    required this.onChanged,
    this.label = 'Adicionar foto',
    this.required = false,
  });

  final XFile? file;
  final ValueChanged<XFile?> onChanged;
  final String label;
  final bool required;

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 2000,
        imageQuality: 82,
      );
      if (picked != null) onChanged(picked);
    } catch (_) {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 82);
      if (picked != null) onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFCBD4DB)),
        ),
        child: Row(
          children: [
            const UrbIcon(UrbIcons.camera, size: 18, color: UrbColors.blue),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label, style: UrbText.label.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800)),
            ),
            if (file != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(file!.name, overflow: TextOverflow.ellipsis, style: UrbText.caption),
              ),
              IconButton(
                tooltip: 'Remover foto',
                onPressed: () => onChanged(null),
                icon: const UrbIcon(UrbIcons.close, size: 14, color: UrbColors.muted),
              ),
            ] else
              Text(required ? 'Obrigatória' : 'Opcional', style: UrbText.caption.copyWith(color: const Color(0xFF8A95A2))),
          ],
        ),
      ),
    );
  }
}

/// "Informe uma possível resolução". Abre validação comunitária; nunca resolve
/// diretamente (spec §5.3, §30).
Future<bool> showResolutionSheet(
  BuildContext context, {
  required Occurrence occurrence,
  required ResolutionContext resolution,
  String initiatorKind = 'citizen',
}) async {
  final result = await showUrbSheet<bool>(
    context: context,
    eyebrow: 'Possível resolução',
    title: 'O que você encontrou?',
    intro: 'Isso inicia a validação da comunidade e não encerra a ocorrência imediatamente. '
        'Moradores próximos confirmam o que aconteceu no local.',
    builder: (sheetContext) => _ResolutionForm(
      occurrence: occurrence,
      resolution: resolution,
      initiatorKind: initiatorKind,
    ),
  );
  return result ?? false;
}

class _ResolutionForm extends StatefulWidget {
  const _ResolutionForm({required this.occurrence, required this.resolution, required this.initiatorKind});

  final Occurrence occurrence;
  final ResolutionContext resolution;
  final String initiatorKind;

  @override
  State<_ResolutionForm> createState() => _ResolutionFormState();
}

class _ResolutionFormState extends State<_ResolutionForm> {
  final _description = TextEditingController();
  XFile? _photo;
  bool _sending = false;

  bool get _photoRequired => widget.resolution.evidenceRequired && widget.initiatorKind == 'citizen';

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_description.text.trim().length < 3) {
      showUrbToast(context, 'Descreva o que você encontrou no local.');
      return;
    }
    if (_photoRequired && _photo == null) {
      showUrbToast(context, 'Esta categoria exige uma foto recente.');
      return;
    }
    setState(() => _sending = true);
    try {
      await OccurrenceService().reportPossibleResolution(
        occurrenceId: widget.occurrence.id,
        description: _description.text,
        initiatorKind: widget.initiatorKind,
        evidence: _photo,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showUrbToast(context, friendlyError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.resolution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EvidencePickerField(
          file: _photo,
          label: 'Adicionar foto da situação atual',
          required: _photoRequired,
          onChanged: (file) => setState(() => _photo = file),
        ),
        const SizedBox(height: 14),
        UrbTextField(
          label: 'Descrição',
          controller: _description,
          hint: 'Ex.: passei pelo local hoje e o reparo foi feito.',
          maxLines: 4,
          minLines: 3,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: UrbColors.canvasAlt, borderRadius: BorderRadius.circular(11)),
          child: Text(
            'São necessárias ${settings.confirmationsRequired} confirmações de pessoas a até '
            '${formatDecimal(settings.radiusKm, digits: 0)} km do local em até ${settings.durationHours.round()} horas. '
            'Você não participa da contagem deste ciclo.',
            style: UrbText.caption.copyWith(fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        UrbButton(label: 'Informar possível resolução', expand: true, height: 50, loading: _sending, onPressed: _send),
      ],
    );
  }
}

/// Reabertura exige descrição e nova evidência (spec §32).
Future<bool> showReopenSheet(BuildContext context, Occurrence occurrence) async {
  final result = await showUrbSheet<bool>(
    context: context,
    eyebrow: 'Reabertura',
    title: 'O problema voltou?',
    intro: 'Reabra apenas se o mesmo problema reapareceu ou a solução não durou. '
        'Se for um problema novo no mesmo local, registre uma nova ocorrência.',
    builder: (_) => _ReopenForm(occurrence: occurrence),
  );
  return result ?? false;
}

class _ReopenForm extends StatefulWidget {
  const _ReopenForm({required this.occurrence});

  final Occurrence occurrence;

  @override
  State<_ReopenForm> createState() => _ReopenFormState();
}

class _ReopenFormState extends State<_ReopenForm> {
  final _description = TextEditingController();
  XFile? _photo;
  bool _sending = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_photo == null || _description.text.trim().length < 3) {
      showUrbToast(context, 'A reabertura exige uma descrição e uma nova foto.');
      return;
    }
    setState(() => _sending = true);
    try {
      await OccurrenceService().reopen(occurrenceId: widget.occurrence.id, description: _description.text, evidence: _photo!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showUrbToast(context, friendlyError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EvidencePickerField(file: _photo, required: true, label: 'Nova foto do local', onChanged: (file) => setState(() => _photo = file)),
        const SizedBox(height: 14),
        UrbTextField(
          label: 'O que aconteceu?',
          controller: _description,
          hint: 'Ex.: o buraco reapareceu depois das chuvas.',
          maxLines: 4,
          minLines: 3,
          maxLength: 600,
        ),
        const SizedBox(height: 14),
        UrbButton(label: 'Reabrir ocorrência', expand: true, height: 50, loading: _sending, onPressed: _send),
      ],
    );
  }
}

/// Denúncia de relato ou comentário (spec §38).
Future<void> showReportContentSheet(BuildContext context, {required String targetType, required int targetId}) {
  const reasons = [
    'Informação falsa ou enganosa',
    'Conteúdo ofensivo ou discriminatório',
    'Exposição de dados pessoais',
    'Spam ou propaganda',
    'Não é um problema urbano',
  ];
  return showUrbSheet<void>(
    context: context,
    eyebrow: 'Denúncia',
    title: targetType == 'comment' ? 'Denunciar comentário' : 'Denunciar relato',
    intro: 'A moderação analisa a denúncia. O conteúdo só é removido se a denúncia for considerada procedente.',
    builder: (sheetContext) {
      String? selected;
      final details = TextEditingController();
      var sending = false;
      return StatefulBuilder(
        builder: (context, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UrbChip(
                  label: reason,
                  selected: selected == reason,
                  onTap: () => setSheetState(() => selected = reason),
                ),
              ),
            const SizedBox(height: 6),
            UrbTextField(label: 'Detalhes (opcional)', controller: details, maxLines: 3, maxLength: 300),
            const SizedBox(height: 14),
            UrbButton(
              label: 'Enviar denúncia',
              expand: true,
              height: 50,
              loading: sending,
              onPressed: selected == null
                  ? null
                  : () async {
                      setSheetState(() => sending = true);
                      try {
                        final reason = details.text.trim().isEmpty ? selected! : '${selected!}: ${details.text.trim()}';
                        await OccurrenceService().reportContent(targetType: targetType, targetId: targetId, reason: reason);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                        if (context.mounted) {
                          showUrbToast(context, 'Denúncia enviada para análise.');
                        }
                      } catch (error) {
                        setSheetState(() => sending = false);
                        if (context.mounted) {
                          showUrbToast(context, friendlyError(error));
                        }
                      }
                    },
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Atuação institucional
// ---------------------------------------------------------------------------

class _ActionOption {
  const _ActionOption(this.type, this.label, this.description, {this.needsAgency = false, this.needsDate = false});

  final String type;
  final String label;
  final String description;
  final bool needsAgency;
  final bool needsDate;
}

const _administrationActions = [
  _ActionOption('priority', 'Priorizar', 'Reconhecer oficialmente a prioridade desta ocorrência.'),
  _ActionOption('priority_removed', 'Retirar prioridade', 'Retirar a prioridade administrativa e registrar a justificativa.'),
  _ActionOption('forwarding', 'Encaminhar ao órgão competente', 'Reencaminhar mantendo o histórico do órgão anterior.', needsAgency: true),
  _ActionOption('request', 'Solicitar providências', 'Solicitar providências ao órgão responsável.'),
  _ActionOption('official_position', 'Manifestação oficial', 'Publicar posicionamento oficial da gestão.'),
  _ActionOption('forecast', 'Informar previsão', 'Informar previsão oficial de atendimento.', needsDate: true),
  _ActionOption('progress_update', 'Atualizar andamento', 'Registrar andamento acompanhado pela gestão.'),
  _ActionOption('conclusion', 'Informar conclusão', 'A administração informa que o serviço foi concluído. Abre validação comunitária.'),
];

const _agencyActions = [
  _ActionOption('received', 'Confirmar recebimento', 'O órgão confirma que recebeu a demanda.'),
  _ActionOption('analysis', 'Informar análise', 'Equipe técnica analisando a ocorrência.'),
  _ActionOption('forecast', 'Informar previsão', 'Informar data prevista de atendimento.', needsDate: true),
  _ActionOption('scheduled', 'Serviço programado', 'Incluir na programação operacional.'),
  _ActionOption('in_progress', 'Serviço em execução', 'Equipe atuando no local.'),
  _ActionOption('progress_update', 'Atualizar andamento', 'Publicar atualização oficial de andamento.'),
  _ActionOption('observation', 'Observação oficial', 'Registrar observação oficial do órgão.'),
  _ActionOption('conclusion', 'Informar conclusão', 'O órgão informa a conclusão. Abre validação comunitária.'),
];

const _councilorActions = [
  _ActionOption('forwarding', 'Encaminhamento', 'Encaminhar a demanda à comissão, secretaria ou órgão.'),
  _ActionOption('request', 'Solicitação de providência', 'Solicitar formalmente providências.'),
  _ActionOption('charge', 'Cobrança', 'Cobrar retorno do órgão responsável.'),
  _ActionOption('official_letter', 'Ofício', 'Registrar ofício protocolado.'),
  _ActionOption('agency_contact', 'Contato com órgão', 'Registrar contato realizado com o órgão.'),
  _ActionOption('visit', 'Visita ao local', 'Registrar visita in loco.'),
  _ActionOption('verification', 'Verificação', 'Registrar verificação da situação.'),
  _ActionOption('response_received', 'Retorno recebido', 'Documentar retorno recebido do órgão.'),
  _ActionOption('public_update', 'Atualização pública', 'Publicar atualização do acompanhamento.'),
  _ActionOption('possible_resolution', 'Informar possível resolução', 'Abre validação comunitária; não marca como resolvida.'),
];

/// Ações oficiais da Gestão ou do órgão. `actor` é 'administration' ou 'agency'.
Future<bool> showInstitutionalActionSheet(
  BuildContext context, {
  required Occurrence occurrence,
  required String actor,
  String? initialActionType,
}) async {
  final options = actor == 'administration'
      ? _administrationActions
          .where((option) => occurrence.administrativePriority
              ? option.type != 'priority'
              : option.type != 'priority_removed')
          .toList()
      : _agencyActions;
  final initialOption = initialActionType == null
      ? null
      : options.where((option) => option.type == initialActionType).firstOrNull;
  final option = initialOption ??
      await _pickAction(
        context,
        title: actor == 'administration' ? 'Ação da gestão municipal' : 'Atualização oficial do órgão',
        options: options,
      );
  if (option == null || !context.mounted) return false;
  final result = await showUrbSheet<bool>(
    context: context,
    eyebrow: actor == 'administration' ? 'Gestão municipal' : (occurrence.agencyName ?? 'Órgão responsável'),
    title: option.label,
    intro: '${option.description} A ação fica registrada publicamente na linha do tempo.',
    builder: (_) => _ActionForm(
      occurrence: occurrence,
      option: option,
      actorKind: actor,
      councilorFollowingId: null,
    ),
  );
  return result ?? false;
}

/// Atuação de vereador sobre uma demanda que acompanha (spec §3.4).
Future<bool> showCouncilorActionSheet(
  BuildContext context, {
  required Occurrence occurrence,
  required int followingId,
}) async {
  final option = await _pickAction(context, title: 'Registrar atuação', options: _councilorActions);
  if (option == null || !context.mounted) return false;
  final result = await showUrbSheet<bool>(
    context: context,
    eyebrow: 'Acompanhamento parlamentar',
    title: option.label,
    intro: '${option.description} A ação aparece no histórico público da ocorrência.',
    builder: (_) => _ActionForm(
      occurrence: occurrence,
      option: option,
      councilorFollowingId: followingId,
    ),
  );
  return result ?? false;
}

Future<_ActionOption?> _pickAction(BuildContext context, {required String title, required List<_ActionOption> options}) {
  return showUrbSheet<_ActionOption>(
    context: context,
    eyebrow: 'Registrar',
    title: title,
    builder: (sheetContext) => Column(
      children: [
        for (var index = 0; index < options.length; index++)
          UrbDotRow(
            title: options[index].label,
            subtitle: options[index].description,
            dotColor: actionDotColor(options[index].type),
            last: index == options.length - 1,
            onTap: () => Navigator.of(sheetContext).pop(options[index]),
          ),
      ],
    ),
  );
}

class _ActionForm extends StatefulWidget {
  const _ActionForm({
    required this.occurrence,
    required this.option,
    required this.councilorFollowingId,
    this.actorKind,
  });

  final Occurrence occurrence;
  final _ActionOption option;
  final int? councilorFollowingId;
  final String? actorKind;

  @override
  State<_ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<_ActionForm> {
  final _institutional = InstitutionalService();
  final _occurrences = OccurrenceService();
  final _description = TextEditingController();
  List<AgencyChoice> _agencies = const [];
  List<AgencyAssignmentRecord> _assignmentHistory = const [];
  int? _targetAgencyId;
  DateTime? _forecast;
  XFile? _evidence;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.option.needsAgency) {
      Future.wait<dynamic>([
        _institutional.fetchAgenciesForCity(
          widget.occurrence.cityId,
          categoryId: widget.occurrence.categoryId,
        ),
        _institutional.fetchAgencyAssignmentHistory(widget.occurrence.id),
      ]).then((values) {
        if (!mounted) return;
        setState(() {
          _agencies = (values[0] as List<AgencyChoice>)
              .where((agency) => agency.id != widget.occurrence.agencyId)
              .toList();
          _assignmentHistory = values[1] as List<AgencyAssignmentRecord>;
        });
      });
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_description.text.trim().length < 3) {
      showUrbToast(context, 'Descreva a ação registrada.');
      return;
    }
    if (widget.option.needsAgency && _targetAgencyId == null) {
      showUrbToast(context, 'Selecione o órgão competente.');
      return;
    }
    if (widget.option.needsDate && _forecast == null) {
      showUrbToast(context, 'Informe a data prevista.');
      return;
    }
    setState(() => _sending = true);
    String? evidencePath;
    try {
      if (_evidence != null) {
        evidencePath = await _occurrences.uploadInstitutionalEvidence(widget.occurrence.id, _evidence!);
      }
      if (widget.councilorFollowingId != null) {
        await _institutional.registerCouncilorAction(
          followingId: widget.councilorFollowingId!,
          actionType: widget.option.type,
          description: _description.text,
          evidenceStoragePath: evidencePath,
        );
      } else {
        await _institutional.registerInstitutionalAction(
          occurrenceId: widget.occurrence.id,
          actorKind: widget.actorKind!,
          actionType: widget.option.type,
          description: _description.text,
          targetAgencyId: _targetAgencyId,
          forecastAt: _forecast,
          evidenceStoragePath: evidencePath,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showUrbToast(context, friendlyError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.option.needsAgency) ...[
          if (widget.occurrence.agencyName != null) ...[
            Text(
              'Responsável atual: ${widget.occurrence.agencyName}',
              style: UrbText.caption.copyWith(fontSize: 12),
            ),
            if (_assignmentHistory.isNotEmpty)
              Text(
                'Desde ${formatDate(_assignmentHistory.first.startsAt)} · ${_assignmentHistory.length} ${_assignmentHistory.length == 1 ? 'encaminhamento registrado' : 'encaminhamentos registrados'}',
                style: UrbText.caption,
              ),
            if (_assignmentHistory.length > 1) ...[
              const SizedBox(height: 8),
              Text('Histórico recente', style: UrbText.label),
              const SizedBox(height: 4),
              for (final assignment in _assignmentHistory.skip(1).take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${assignment.agencyName ?? 'Órgão'} · ${formatDate(assignment.startsAt)} a ${assignment.endsAt == null ? 'atual' : formatDate(assignment.endsAt!)}',
                    style: UrbText.caption,
                  ),
                ),
            ],
            const SizedBox(height: 12),
          ],
          Text('Órgão competente', style: UrbText.label),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _targetAgencyId,
            isExpanded: true,
            hint: const Text('Selecione o órgão'),
            items: [
              for (final agency in _agencies)
                DropdownMenuItem(
                  value: agency.id,
                  child: Text(
                    agency.recommended
                        ? '${agency.name} · recomendado para a categoria'
                        : agency.name,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _targetAgencyId = value),
          ),
          const SizedBox(height: 14),
        ],
        if (widget.option.needsDate) ...[
          Text('Data prevista', style: UrbText.label),
          const SizedBox(height: 8),
          UrbButton(
            label: _forecast == null ? 'Selecionar data' : formatDate(_forecast!),
            tone: UrbButtonTone.outline,
            icon: UrbIcons.clock,
            expand: true,
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: now,
                lastDate: now.add(const Duration(days: 730)),
                initialDate: now.add(const Duration(days: 7)),
              );
              if (picked != null) setState(() => _forecast = picked);
            },
          ),
          const SizedBox(height: 14),
        ],
        UrbTextField(
          label: 'Descrição pública',
          controller: _description,
          hint: 'Descreva a ação de forma objetiva.',
          maxLines: 4,
          minLines: 3,
          maxLength: 800,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        EvidencePickerField(file: _evidence, label: 'Anexar evidência', onChanged: (file) => setState(() => _evidence = file)),
        const SizedBox(height: 16),
        UrbButton(label: 'Registrar ação', expand: true, height: 50, loading: _sending, onPressed: _send),
      ],
    );
  }
}
