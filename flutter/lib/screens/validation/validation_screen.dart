import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../services/location_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../occurrence/occurrence_sheets.dart';

enum _Outcome { positiveRecorded, resolved, negativeRecorded, rejected }

/// Validação comunitária (spec §30). A elegibilidade (raio, iniciador, voto
/// único, prazo) é aplicada pelo backend em `vote_resolution_cycle`.
class ValidationScreen extends StatefulWidget {
  const ValidationScreen({super.key, required this.occurrence});

  final Occurrence occurrence;

  @override
  State<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends State<ValidationScreen> {
  final _service = OccurrenceService();
  final _location = const LocationService();

  ResolutionContext? _context;
  GeoPoint? _position;
  bool _loading = true;
  String? _error;
  _Outcome? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await _service.fetchResolutionContext(widget.occurrence.id);
      final position = AppSession.instance.position.value ?? await AppSession.instance.requestPosition();
      if (!mounted) return;
      setState(() {
        _context = context;
        _position = position;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? get _distance => _position == null
      ? null
      : _location.distanceKm(_position!, widget.occurrence.latitude, widget.occurrence.longitude);

  Future<void> _vote(bool confirm) async {
    final cycle = _context?.cycle;
    if (cycle == null) return;
    final result = await showUrbSheet<({String? comment, XFile? photo})>(
      context: context,
      eyebrow: confirm ? 'Confirmação da resolução' : 'Validação negativa',
      title: confirm ? 'Registre o que você encontrou' : 'O que você encontrou?',
      intro: confirm
          ? 'A foto e o comentário são opcionais. Você pode confirmar a resolução sem adicionar nenhuma evidência.'
          : 'Conte rapidamente por que o problema continua. Essas informações ajudam a comunidade a entender a rejeição.',
      builder: (_) => _VoteForm(confirm: confirm),
    );
    if (result == null || !mounted) return;

    var position = _position;
    position ??= await AppSession.instance.requestPosition();
    if (position == null) {
      if (mounted) showUrbToast(context, 'Permita o acesso à localização para validar. Só é possível validar estando próximo ao local.');
      return;
    }
    try {
      final status = await _service.vote(
        cycleId: cycle.id,
        confirm: confirm,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final comment = result.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        await _service.addComment(widget.occurrence.id, comment);
      }
      if (result.photo != null) {
        await _service.addReport(
          occurrenceId: widget.occurrence.id,
          description: comment?.isNotEmpty == true
              ? comment!
              : (confirm ? 'Foto da situação atual registrada na validação comunitária.' : 'Foto mostrando que o problema continua.'),
          anonymous: false,
          photos: [result.photo!],
        );
      }
      final updated = await _service.fetchById(widget.occurrence.id);
      if (updated != null) AppSession.instance.publish(updated);
      if (!mounted) return;
      setState(() {
        _outcome = switch (status) {
          'approved' => _Outcome.resolved,
          'rejected' => _Outcome.rejected,
          _ => confirm ? _Outcome.positiveRecorded : _Outcome.negativeRecorded,
        };
      });
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Validação comunitária'),
      body: _outcome != null
          ? _OutcomeView(outcome: _outcome!, onDone: () => Navigator.of(context).pop())
          : (_loading
              ? const UrbLoadingView()
              : (_error != null ? UrbErrorState(message: _error!, onRetry: _load) : _content())),
    );
  }

  Widget _content() {
    final cycle = _context?.cycle;
    final occurrence = widget.occurrence;
    final distance = _distance;
    if (cycle == null) {
      return UrbEmptyState(
        icon: UrbIcons.check,
        title: 'Nenhuma validação aberta',
        message: occurrence.status == OccurrenceStatus.resolved
            ? 'A comunidade já confirmou a resolução desta ocorrência.'
            : 'Esta ocorrência não está aguardando validação no momento.',
        actionLabel: 'Ver ocorrência',
        onAction: () => openOccurrence(context, occurrenceId: occurrence.id, initial: occurrence),
      );
    }
    final outOfRadius = distance != null && distance > cycle.radiusKm;
    final blockedReason = cycle.initiatedByMe
        ? 'Você informou esta possível resolução e não participa da contagem deste ciclo.'
        : cycle.myVote != null
            ? 'Sua validação já foi registrada neste ciclo. Obrigado por participar.'
            : outOfRadius
                ? 'Você está a ${formatDistance(distance)} do local. A validação é aberta a quem está a até ${formatDecimal(cycle.radiusKm, digits: 0)} km.'
                : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        UrbEyebrow(distance == null ? 'Perto do local' : 'A ${formatDistance(distance)} de você'),
        const SizedBox(height: 10),
        Text('Ajude a confirmar o que aconteceu no local', style: UrbText.h1),
        const SizedBox(height: 10),
        Text(
          '${cycle.initiatorLabel} informou que este problema foi solucionado. Sua confirmação ajuda a manter os dados da cidade confiáveis.',
          style: UrbText.body,
        ),
        if (cycle.description != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: UrbColors.line)),
            child: Text('“${cycle.description}”', style: UrbText.bodySmall.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
        const SizedBox(height: 20),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFDFE4E5))),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => openOccurrence(context, occurrenceId: occurrence.id, initial: occurrence),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  OccurrenceImage(
                    url: occurrence.primaryImageUrl,
                    categoryName: occurrence.categoryName,
                    categorySlug: occurrence.categorySlug,
                    width: 72,
                    height: 72,
                    radius: 9,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(occurrence.categoryName.toUpperCase(), style: UrbText.eyebrow.copyWith(fontSize: 10)),
                        const SizedBox(height: 2),
                        Text(occurrence.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                        Text('${occurrence.locationLabel} · ${formatRelativeTime(occurrence.createdAt).toLowerCase()}', style: UrbText.caption),
                      ],
                    ),
                  ),
                  const UrbIcon(UrbIcons.chevron, size: 17, color: UrbColors.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF2F4F0), borderRadius: BorderRadius.circular(13)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: '${cycle.confirmations} de ${cycle.confirmationsRequired} confirmações',
                child: Row(
                  children: [
                    for (var index = 0; index < cycle.confirmationsRequired; index++)
                      Expanded(
                        child: Container(
                          height: 5,
                          margin: EdgeInsets.only(right: index == cycle.confirmationsRequired - 1 ? 0 : 5),
                          decoration: BoxDecoration(
                            color: index < cycle.confirmations ? UrbColors.blue : const Color(0xFFDCE1DF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${cycle.confirmations} de ${cycle.confirmationsRequired} confirmações recebidas',
                style: UrbText.titleSmall.copyWith(color: const Color(0xFF28384E), fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'O ciclo termina em ${formatRemaining(cycle.remaining)}. '
                '${cycle.rejections} de ${cycle.rejectionsRequired} indicações de que o problema continua.',
                style: UrbText.caption,
              ),
            ],
          ),
        ),
        if (cycle.evidenceUrl != null) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(cycle.evidenceUrl!, height: 170, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 4),
          Text('Foto enviada com a possível resolução', style: UrbText.caption),
        ],
        const SizedBox(height: 22),
        Text('Confirme apenas se você consegue verificar a situação atual do local.', style: UrbText.caption),
        const SizedBox(height: 5),
        Text('O problema foi realmente resolvido?', style: UrbText.h3),
        const SizedBox(height: 13),
        if (blockedReason != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(12)),
            child: Text(blockedReason, style: UrbText.bodySmall.copyWith(color: UrbColors.navy)),
          )
        else ...[
          UrbButton(label: 'Sim, foi resolvido', icon: UrbIcons.check, expand: true, height: 50, onPressed: () => _vote(true)),
          const SizedBox(height: 9),
          UrbButton(label: 'Não, o problema continua', tone: UrbButtonTone.outline, expand: true, height: 50, onPressed: () => _vote(false)),
        ],
      ],
    );
  }
}

class _VoteForm extends StatefulWidget {
  const _VoteForm({required this.confirm});

  final bool confirm;

  @override
  State<_VoteForm> createState() => _VoteFormState();
}

class _VoteFormState extends State<_VoteForm> {
  final _comment = TextEditingController();
  XFile? _photo;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EvidencePickerField(
          file: _photo,
          label: widget.confirm ? 'Adicionar foto da situação atual' : 'Adicionar foto',
          onChanged: (file) => setState(() => _photo = file),
        ),
        if (_photo != null) ...[
          const SizedBox(height: 6),
          Text('A foto será adicionada como um relato com evidência nesta ocorrência.', style: UrbText.caption),
        ],
        const SizedBox(height: 14),
        UrbTextField(
          label: 'Comentário público (opcional)',
          controller: _comment,
          hint: widget.confirm
              ? 'Ex.: passei pelo local hoje e a iluminação voltou a funcionar.'
              : 'Ex.: o poste continua apagado e a rua segue sem iluminação.',
          maxLines: 4,
          minLines: 3,
          maxLength: 500,
        ),
        Text('Este comentário será publicado na conversa geral da ocorrência.', style: UrbText.caption),
        const SizedBox(height: 14),
        UrbButton(
          label: widget.confirm ? 'Confirmar que o problema foi resolvido' : 'Confirmar que o problema continua',
          expand: true,
          height: 50,
          onPressed: () => Navigator.of(context).pop((comment: _comment.text, photo: _photo)),
        ),
      ],
    );
  }
}

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.outcome, required this.onDone});

  final _Outcome outcome;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final (eyebrow, title, description) = switch (outcome) {
      _Outcome.positiveRecorded => (
          'Sua validação foi registrada',
          'Você confirmou que o problema foi resolvido.',
          'A ocorrência será marcada como resolvida caso o ciclo atinja o quórum necessário.',
        ),
      _Outcome.resolved => (
          'Problema resolvido!',
          'A comunidade confirmou a resolução.',
          'Esta ocorrência recebeu as confirmações necessárias e agora está marcada como resolvida.',
        ),
      _Outcome.negativeRecorded => (
          'Sua validação foi registrada',
          'Você informou que o problema ainda continua.',
          'Obrigado por ajudar a manter as informações da cidade atualizadas.',
        ),
      _Outcome.rejected => (
          'A validação foi concluída',
          'A comunidade informou que o problema continua.',
          'A ocorrência retornou ao status anterior.',
        ),
    };
    final neutral = outcome == _Outcome.negativeRecorded || outcome == _Outcome.rejected;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 34, 28, 34),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (neutral)
                const UrbBrandMark(size: 66)
              else
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: outcome == _Outcome.resolved ? UrbColors.lime : UrbColors.blueSoft,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: outcome == _Outcome.resolved
                        ? [BoxShadow(color: UrbColors.lime.withValues(alpha: 0.3), blurRadius: 32, offset: const Offset(0, 12))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: UrbIcon(UrbIcons.check, size: 30, color: outcome == _Outcome.resolved ? UrbColors.navy : UrbColors.blue),
                ),
              const SizedBox(height: 20),
              UrbEyebrow(eyebrow),
              const SizedBox(height: 7),
              Text(title, textAlign: TextAlign.center, style: UrbText.h1.copyWith(fontSize: 25)),
              const SizedBox(height: 10),
              Text(description, textAlign: TextAlign.center, style: UrbText.body),
              const SizedBox(height: 24),
              UrbButton(label: 'Voltar', onPressed: onDone, height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
